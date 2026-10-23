"""Timer-paced, explicitly synthetic replay. This module never opens a socket."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import struct
import sys
from types import ModuleType
from typing import Any
from uuid import uuid4

from PySide6.QtCore import QObject, QTimer, Signal

from ..config import DemoConfig, REPOSITORY_ROOT, TOOLS_DIRECTORY, normalize_mode
from ..models.events import Event
from .output_parser import OutputParser
from .process_runner import log_level


FIXTURE_NOTICE = "REPLAY / OFFLINE: SIMULATED TEST FIXTURE. No hardware communication or board validation."


def _load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load fixture generator {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_b5_fixture_capture(path: Path) -> None:
    """Use the existing packet constructors without invoking their UDP entry points."""
    sender = _load_module("_dashboard_fixture_sender", TOOLS_DIRECTORY / "difi_b6_sender.py")
    # The original three-types CLI imports its sibling by name. Temporarily supply
    # that sibling while loading only its pure packet-construction functions.
    previous = sys.modules.get("difi_b6_sender")
    sys.modules["difi_b6_sender"] = sender
    try:
        types = _load_module("_dashboard_fixture_types", TOOLS_DIRECTORY / "difi_b6_three_types.py")
    finally:
        if previous is None:
            sys.modules.pop("difi_b6_sender", None)
        else:
            sys.modules["difi_b6_sender"] = previous
    payloads = [types.version_packet(0), types.context_packet(0)]
    payloads.extend(sender.make_packet(round_id) for round_id in range(20))
    with path.open("wb") as capture:
        for payload in payloads:
            capture.write(struct.pack("!I", len(payload)))
            capture.write(payload)


def fixture_lines(mode: str, config: DemoConfig) -> list[str]:
    """Text has the exact original CLI grammar; the event source carries trust."""
    mode = normalize_mode(mode)
    if mode == "B5":
        lines = ["[INFO] UDP listening on replay-fixture:4991",
                 "[INFO] sending START to replay-fixture:4991"]
        packets = [(5, 0, 11), (4, 0, 27)] + [(1, round_id & 15, 263) for round_id in range(20)]
        lines.extend(f"[PASS] #{index:02d} type={kind} seq={seq:2d} words={words:3d} bytes={words * 4:4d}"
                     for index, (kind, seq, words) in enumerate(packets))
        lines.extend(["[PASS] DIFI UDP full chain: 1 Version + 1 Context + 20 Data, 5120 IQ correct",
                      "[INFO] captured 21192 UDP payload bytes in 0.050s; saved to synthetic fixture capture",
                      "[NOTE] Replay sample timing is synthetic; this is NOT a UDP throughput benchmark."])
        return lines
    lines = ["[BOARD] READY NEXT_ROUND=14 NEXT_VERSION=3 NEXT_CONTEXT=7"]
    for kind in config.types.split(","):
        if kind == "version":
            lines.append("[PASS] VERSION bytes=  44 ACK PASS TYPE=VERSION SEQ=3 META=1")
        elif kind == "context":
            lines.append("[PASS] CONTEXT bytes= 108 ACK PASS TYPE=CONTEXT SEQ=7 META=1")
        else:
            lines.extend(f"[PASS] DATA    bytes=1052 ACK PASS ROUND={round_id} SEQ={round_id & 15} IQ=256"
                         for round_id in range(14, 14 + config.rounds))
    lines.append("[PASS] Selected B6 packet types validated by the board")
    return lines


class ReplayService(QObject):
    event = Signal(object)
    log = Signal(str, str, str)
    finished = Signal(int, bool)

    def __init__(self, parent: QObject | None = None, interval_ms: int = 150) -> None:
        super().__init__(parent)
        self._timer = QTimer(self)
        self._timer.setInterval(max(1, int(interval_ms)))
        self._timer.timeout.connect(self._tick)
        self._running = False
        self._parser: OutputParser | None = None
        self._lines: list[str] = []
        self._index = 0
        self._mode = "B5"
        self.capture_path: Path | None = None

    @property
    def running(self) -> bool:
        return self._running

    def start(self, mode: str, parameters: dict[str, Any], output_dir: Path | None = None) -> bool:
        if self.running:
            self.log.emit("WARN", "REPLAY", "A replay is already running.")
            return False
        try:
            self._mode = normalize_mode(mode)
            config = DemoConfig.from_dict(parameters, self._mode)
            self.capture_path = None
            if self._mode == "B5":
                if output_dir is None:
                    output_dir = REPOSITORY_ROOT / "dashboard" / "output" / f"replay_fixture_{uuid4().hex}"
                output_dir = Path(output_dir)
                output_dir.mkdir(parents=True, exist_ok=True)
                self.capture_path = output_dir.resolve() / "replay_fixture_b5_capture.bin"
                write_b5_fixture_capture(self.capture_path)
            self._lines = fixture_lines(self._mode, config)
        except (ValueError, OSError, RuntimeError, ImportError) as exc:
            self.log.emit("ERROR", "REPLAY", str(exc))
            self.event.emit(Event("SESSION_ERROR", "REPLAY", {"message": str(exc)}))
            return False
        self._parser = OutputParser(self._mode, source="REPLAY")
        self._index = 0
        self._running = True
        self.log.emit("WARN", "REPLAY", FIXTURE_NOTICE)
        self.event.emit(Event("SESSION_START", "REPLAY", {"fixture": True, "message": FIXTURE_NOTICE}))
        self._timer.start()
        return True

    def _tick(self) -> None:
        if not self._running:
            return
        if self._index >= len(self._lines):
            self._timer.stop()
            self._running = False
            self.log.emit("INFO", "REPLAY", "Fixture replay complete. Replay PASS is not a hardware test result.")
            self.finished.emit(0, False)
            return
        line = self._lines[self._index]
        self._index += 1
        self.log.emit(log_level(line), f"REPLAY/{self._mode}/fixture", line)
        if self._parser:
            for event in self._parser.feed(line):
                self.event.emit(event)

    def stop(self) -> None:
        if not self.running:
            return
        self._timer.stop()
        self._running = False
        self.log.emit("WARN", "REPLAY", "Fixture replay stopped.")
        self.finished.emit(0, True)
