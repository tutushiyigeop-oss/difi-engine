"""Nonblocking QProcess adapter for the unchanged B5/B6 command line tools."""
from __future__ import annotations

import codecs
from collections import deque
from pathlib import Path
import re
import time
from typing import Any

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, QTimer, Signal

from ..config import REPOSITORY_ROOT, build_command, normalize_mode
from ..models.events import Event
from .output_parser import OutputParser


def log_level(line: str, stderr: bool = False) -> str:
    match = re.match(r"\[(INFO|PASS|WARN|FAIL|ERROR|NOTE)\]", line)
    if match:
        return "INFO" if match.group(1) == "NOTE" else match.group(1)
    return "ERROR" if stderr else "INFO"


def describe_process_error(message: str) -> str:
    """Add an actionable hint without removing any original process output."""
    lowered = message.lower()
    if any(text in lowered for text in ("10048", "address already in use")):
        return "UDP port is already in use. Close the other receiver or select an unused port."
    if any(text in lowered for text in ("10049", "cannot assign requested address", "not valid in its context")):
        return "The configured PC IP is not assigned to a local adapter. Check Settings and Windows network adapters."
    if "timeout" in lowered or "timed out" in lowered:
        return "No expected board response arrived. Check the selected B5/B6 bitstream and ELF, cable, IPs, firewall and UART; B5 also requires UTC initialization."
    if any(text in lowered for text in ("10051", "10065", "unreachable")):
        return "The board network is unreachable. Check the cable and the PC adapter subnet."
    if "wrong elf" in lowered or "board status" in lowered or "missing next_" in lowered:
        return "The response does not match B6 STATUS. Load the matching B6 bitstream and Vitis ELF."
    return ""


class ProcessRunner(QObject):
    event = Signal(object)
    log = Signal(str, str, str)
    finished = Signal(int, bool)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._process: QProcess | None = None
        self._parser: OutputParser | None = None
        self._running = False
        self._stopped = False
        self._completed = False
        self._reported_error = False
        self._finalizing = False
        self._pending_exit_code: int | None = None
        self._mode = "B5"
        self._buffers = {"stdout": "", "stderr": ""}
        self._decoders: dict[str, Any] = {}
        self._pending_lines: deque[tuple[str, str]] = deque()
        self.capture_path: Path | None = None
        self._kill_timer = QTimer(self)
        self._kill_timer.setSingleShot(True)
        self._kill_timer.setInterval(1200)
        self._kill_timer.timeout.connect(self._kill_if_running)
        self._dispatch_timer = QTimer(self)
        self._dispatch_timer.setSingleShot(True)
        self._dispatch_timer.setInterval(0)
        self._dispatch_timer.timeout.connect(self._dispatch_lines)

    @property
    def running(self) -> bool:
        return self._running

    def _build_command(self, mode: str, parameters: dict[str, Any], output_dir: Path) -> list[str]:
        return build_command(mode, parameters, output_dir)

    def start(self, mode: str, parameters: dict[str, Any], output_dir: Path) -> bool:
        if self.running:
            self.log.emit("WARN", "LIVE", "A verification process is already running.")
            return False
        self.capture_path = None
        try:
            self._mode = normalize_mode(mode)
            argv = self._build_command(self._mode, parameters, Path(output_dir))
            Path(output_dir).mkdir(parents=True, exist_ok=True)
        except (ValueError, OSError) as exc:
            self.log.emit("ERROR", "LIVE", str(exc))
            self.event.emit(Event("SESSION_ERROR", "LIVE", {"message": str(exc)}))
            return False
        self.capture_path = Path(output_dir).resolve() / "b5_capture.bin" if self._mode == "B5" else None
        self._parser = OutputParser(self._mode, source="LIVE")
        self._buffers = {"stdout": "", "stderr": ""}
        self._decoders = {channel: codecs.getincrementaldecoder("utf-8")("replace") for channel in self._buffers}
        self._running, self._stopped, self._completed, self._reported_error = True, False, False, False
        self._finalizing, self._pending_exit_code = False, None
        self._pending_lines.clear()
        process = QProcess(self)
        self._process = process
        process.setWorkingDirectory(str(REPOSITORY_ROOT))
        environment = QProcessEnvironment.systemEnvironment()
        environment.insert("PYTHONIOENCODING", "utf-8")
        environment.insert("PYTHONUNBUFFERED", "1")
        process.setProcessEnvironment(environment)
        process.readyReadStandardOutput.connect(lambda: self._read("stdout"))
        process.readyReadStandardError.connect(lambda: self._read("stderr"))
        process.errorOccurred.connect(self._process_error)
        process.finished.connect(self._process_finished)
        self.log.emit("INFO", "LIVE", f"Starting {self._mode} verification with the existing Python tool.")
        process.start(argv[0], argv[1:])
        return True

    def _read(self, channel: str, final: bool = False) -> None:
        if self._process is None:
            return
        read = self._process.readAllStandardError if channel == "stderr" else self._process.readAllStandardOutput
        raw = bytes(read())
        self._buffers[channel] += self._decoders[channel].decode(raw, final=final)
        lines = self._buffers[channel].split("\n")
        self._buffers[channel] = lines.pop()
        self._pending_lines.extend((line.removesuffix("\r"), channel) for line in lines)
        if final and self._buffers[channel]:
            line, self._buffers[channel] = self._buffers[channel], ""
            self._pending_lines.append((line.removesuffix("\r"), channel))
        if self._pending_lines and not self._dispatch_timer.isActive():
            self._dispatch_timer.start()

    def _dispatch_lines(self) -> None:
        # A burst of stdout must leave time for input, painting and Stop. A
        # consumer may update several widgets for each event, so bound both the
        # line count and elapsed dispatch time per event-loop turn.
        deadline = time.monotonic() + 0.006
        dispatched = 0
        while self._pending_lines and dispatched < 32 and time.monotonic() < deadline:
            line, channel = self._pending_lines.popleft()
            self._line(line, channel)
            dispatched += 1
        if self._pending_lines:
            self._dispatch_timer.start()
        elif self._pending_exit_code is not None:
            self._complete_finish()

    def _line(self, line: str, channel: str) -> None:
        self.log.emit(log_level(line, stderr=channel == "stderr"), f"LIVE/{self._mode}/{channel}", line)
        if self._parser:
            for event in self._parser.feed(line):
                self.event.emit(event)
        hint = describe_process_error(line)
        if hint:
            self.log.emit("WARN", "LIVE", hint)

    def _process_error(self, error: QProcess.ProcessError) -> None:
        if self._process is None or self._completed:
            return
        if not self._stopped and not self._reported_error:
            self._reported_error = True
            message = self._process.errorString()
            self.log.emit("ERROR", "LIVE", message)
            self.event.emit(Event("SESSION_ERROR", "LIVE", {"message": message}))
        if error == QProcess.ProcessError.FailedToStart:
            self._finish(-1)

    def _process_finished(self, exit_code: int, exit_status: QProcess.ExitStatus) -> None:
        if exit_status == QProcess.ExitStatus.CrashExit and not self._stopped and not self._reported_error:
            self._reported_error = True
            message = "Verification process crashed. Review the original stderr output."
            self.log.emit("ERROR", "LIVE", message)
            self.event.emit(Event("SESSION_ERROR", "LIVE", {"message": message}))
        self._finish(exit_code)

    def _finish(self, exit_code: int) -> None:
        if self._completed or self._finalizing:
            return
        self._finalizing = True
        self._kill_timer.stop()
        for channel in ("stdout", "stderr"):
            self._read(channel, final=True)
        process, self._process = self._process, None
        if process is not None:
            process.deleteLater()
        self._pending_exit_code = int(exit_code)
        if not self._pending_lines:
            self._complete_finish()

    def _complete_finish(self) -> None:
        if self._completed or self._pending_exit_code is None:
            return
        self._completed = True
        self._running = False
        exit_code = self._pending_exit_code
        self._pending_exit_code = None
        self.log.emit("WARN" if self._stopped else ("INFO" if exit_code == 0 else "ERROR"), "LIVE",
                      f"Verification {'stopped' if self._stopped else 'exited'}; process exit code {exit_code}.")
        self.finished.emit(int(exit_code), self._stopped)

    def stop(self) -> None:
        if not self.running or self._stopped:
            return
        self._stopped = True
        self.log.emit("WARN", "LIVE", "Stopping verification process.")
        if self._process is not None:
            self._process.terminate()
            self._kill_timer.start()

    def _kill_if_running(self) -> None:
        if self._process is not None and self._process.state() != QProcess.ProcessState.NotRunning:
            self.log.emit("WARN", "LIVE", "Process did not terminate; force-stopping the child process.")
            self._process.kill()
