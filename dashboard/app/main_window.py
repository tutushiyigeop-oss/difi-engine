"""Session orchestration and desktop shell; protocol tools run outside Qt's UI thread."""
from __future__ import annotations

import json
from queue import SimpleQueue
import struct
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import (
    QComboBox, QDialog, QDialogButtonBox, QDoubleSpinBox, QFileDialog,
    QFormLayout, QFrame, QHBoxLayout, QLabel, QLineEdit, QMainWindow, QSizePolicy,
    QMessageBox, QPushButton, QScrollArea, QSpinBox, QSplitter, QStackedWidget, QVBoxLayout, QWidget,
)

from .config import DemoConfig
from .models.events import Event
from .models.session import Session
from .services.capture_decoder import decode_capture
from .services.process_runner import ProcessRunner
from .services.replay_service import ReplayService
from .services.result_exporter import export_session
from .widgets.topology_widget import TopologyWidget
from .widgets.packet_summary import PacketSummary
from .widgets.iq_verification import IQVerification
from .widgets.sequence_monitor import SequenceMonitor
from .widgets.metadata_monitor import MetadataMonitor
from .widgets.packet_timeline import PacketTimeline
from .widgets.iq_waveform import IQWaveform
from .widgets.log_console import LogConsole
from .widgets.historical_metrics import HistoricalMetrics
from .experiment.panel import ExperimentPanel

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "dashboard" / "output"


def _append_raw(path: Path, line: str, errors: SimpleQueue):
    """Worker function must not retain a QWidget or destroy it on a worker."""
    try:
        with path.open("a", encoding="utf-8") as log:
            log.write(line)
    except OSError as exc:
        errors.put(f"Log save failed: {exc}")


class SettingsDialog(QDialog):
    def __init__(self, mode: str, values: dict, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"{mode} · Session settings")
        self.setMinimumWidth(510)
        outer = QVBoxLayout(self)
        intro = QLabel("Board and PC must be on the same subnet. Hardware / ELF selection is manual.")
        intro.setWordWrap(True)
        outer.addWidget(intro)
        form = QFormLayout()
        self.board = QLineEdit(values["board"])
        self.local_ip = QLineEdit(values["local_ip"])
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        self.port.setValue(values["port"])
        self.timeout = QDoubleSpinBox()
        self.timeout.setRange(0.1, 3600)
        self.timeout.setValue(values["timeout"])
        self.timeout.setSuffix(" s / packet")
        self.types = QLineEdit(values["types"])
        self.rounds = QSpinBox()
        self.rounds.setRange(1, 1000)
        self.rounds.setValue(values["rounds"])
        for label, widget in (("Board IPv4", self.board), ("PC bind IPv4", self.local_ip),
                              ("UDP port", self.port), ("Receive timeout", self.timeout),
                              ("B6 types / order", self.types), ("B6 Data rounds", self.rounds)):
            form.addRow(label, widget)
        self.types.setEnabled(mode == "B6")
        self.rounds.setEnabled(mode == "B6")
        outer.addLayout(form)
        note = QLabel("B5: load B5 bitstream + ELF, enter UTC over UART, then wait for START.\n"
                      "B6: load B6 v0.2 bitstream + difi_b6_udp_rx_pro ELF.\n"
                      "UART monitoring is optional; GPIO details remain Not Observable.")
        note.setWordWrap(True)
        outer.addWidget(note)
        self.error = QLabel()
        self.error.setStyleSheet("color: #ff6c86")
        self.error.setWordWrap(True)
        outer.addWidget(self.error)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self.validate_accept)
        buttons.rejected.connect(self.reject)
        outer.addWidget(buttons)

    def values(self) -> dict:
        return dict(board=self.board.text().strip(), local_ip=self.local_ip.text().strip(),
                    port=self.port.value(), timeout=self.timeout.value(),
                    types=self.types.text().strip().lower(), rounds=self.rounds.value())

    def validate_accept(self):
        try:
            DemoConfig(**self.values()).validate()
        except (ValueError, TypeError) as exc:
            self.error.setText(str(exc))
            return
        self.accept()


class MainWindow(QMainWindow):
    """Public start/stop/reset methods also support deterministic GUI tests."""
    def __init__(self, output_root: Path | None = None):
        super().__init__()
        self.output_root = Path(output_root or OUTPUT)
        self.output_root.mkdir(parents=True, exist_ok=True)
        self.configs = {"B5": DemoConfig(timeout=10).to_dict(), "B6": DemoConfig(timeout=5).to_dict()}
        self._load_settings()
        self.session = Session(mode="B5", source="REPLAY", parameters=self.configs["B5"].copy())
        self.process_runner = ProcessRunner(self)
        self.replay_service = ReplayService(self)
        self.active_runner = None
        self.session_dir: Path | None = None
        self.raw_logs: list[dict] = []
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="difi-capture")
        self._io_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="difi-session")
        self._io_errors = SimpleQueue()
        self._save_future = None
        self._export_future = None
        self._wave_future = None
        self._wave_session = None
        self._wave_final = False
        self._capture_last_count = 0
        self._close_pending = False
        self.setWindowTitle("DIFI ENGINE CONTROL CENTER · FPGA Protocol Instrument")
        self.resize(1740, 970)
        self.setMinimumSize(1100, 650)
        self._build_ui()
        for runner in (self.process_runner, self.replay_service):
            runner.event.connect(self._on_event)
            runner.log.connect(self._on_log)
            runner.finished.connect(self._on_finished)
        self._poll_timer = QTimer(self)
        self._poll_timer.setInterval(80)
        self._poll_timer.timeout.connect(self._poll_waveform)
        self._poll_timer.start()
        self._autosave_timer = QTimer(self)
        self._autosave_timer.setInterval(1500)
        self._autosave_timer.timeout.connect(self._autosave)
        self._autosave_timer.start()
        self._refresh()
        self._on_log("INFO", "APP", "Offline mode ready. Replay uses simulated test fixtures; select Live and click Run to use hardware.")

    @property
    def mode(self) -> str:
        return ("B5", "B6", "STAGED")[self.mode_combo.currentIndex()]

    @property
    def source(self) -> str:
        return "REPLAY" if self.source_combo.currentIndex() == 0 else "LIVE"

    @property
    def running(self) -> bool:
        return (self.active_runner is not None and self.active_runner.running) or (hasattr(self, "stage_d") and self.stage_d.controller.busy)

    def _build_ui(self):
        central = QWidget()
        central.setObjectName("centralWidget")
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(24, 18, 24, 16)
        layout.setSpacing(12)
        header = QHBoxLayout()
        identity = QVBoxLayout()
        eyebrow = QLabel("ZYNQ–7020   /   PROTOCOL INSTRUMENT   /   01")
        eyebrow.setObjectName("eyebrow")
        title = QLabel("DIFI ENGINE CONTROL CENTER")
        title.setObjectName("AppTitle")
        subtitle = QLabel("VITA 49.2 / DIFI 1.1 FPGA Protocol Engine")
        subtitle.setObjectName("AppSubtitle")
        identity.addWidget(eyebrow)
        identity.addWidget(title)
        identity.addWidget(subtitle)
        header.addLayout(identity)
        header.addStretch()
        self.source_badge = QLabel("REPLAY / OFFLINE")
        self.source_badge.setObjectName("sourceBadge")
        self.state_badge = QLabel("● IDLE")
        self.state_badge.setObjectName("stateBadge")
        header.addWidget(self.source_badge)
        header.addSpacing(12)
        header.addWidget(self.state_badge)
        layout.addLayout(header)

        nav = QHBoxLayout()
        self.mode_combo = QComboBox()
        self.mode_combo.addItems(["B5 UDP TX", "B6 UDP RX", "Stage D · UDP Half-Duplex"])
        self.mode_combo.setMinimumWidth(155)
        self.source_combo = QComboBox()
        self.source_combo.addItems(["Replay / Offline", "Live / Hardware"])
        self.source_combo.setMinimumWidth(180)
        self.mode_combo.currentIndexChanged.connect(self._selection_changed)
        self.source_combo.currentIndexChanged.connect(self._selection_changed)
        nav.addWidget(self.mode_combo)
        nav.addWidget(self.source_combo)
        self.endpoint_label = QLabel()
        self.endpoint_label.setObjectName("endpoint")
        self.endpoint_label.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
        self.endpoint_label.setMinimumWidth(0)
        nav.addSpacing(12)
        nav.addWidget(self.endpoint_label, 1)
        self.settings_button = QPushButton("Settings")
        self.settings_button.clicked.connect(self.open_settings)
        nav.addWidget(self.settings_button)
        capture = QPushButton("Save screenshot")
        capture.clicked.connect(self.save_screenshot)
        nav.addWidget(capture)
        layout.addLayout(nav)

        self.preflight_label = QLabel()
        self.preflight_label.setWordWrap(True)
        self.preflight_label.setObjectName("preflight")
        self.preflight_label.setMinimumHeight(42)
        layout.addWidget(self.preflight_label)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setChildrenCollapsible(False)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setMinimumWidth(640)
        work = QWidget()
        work_layout = QVBoxLayout(work)
        work_layout.setContentsMargins(0, 0, 8, 0)
        work_layout.setSpacing(8)
        self.topology = TopologyWidget()
        self.packet_summary = PacketSummary()
        self.iq_verification = IQVerification()
        top = QHBoxLayout()
        top.setSpacing(8)
        top.addWidget(self.topology, 11)
        stats = QVBoxLayout()
        stats.setSpacing(8)
        stats.addWidget(self.packet_summary, 5)
        stats.addWidget(self.iq_verification, 4)
        top.addLayout(stats, 10)
        work_layout.addLayout(top, 4)
        monitors = QHBoxLayout()
        monitors.setSpacing(8)
        self.sequence_monitor = SequenceMonitor()
        self.metadata_monitor = MetadataMonitor()
        monitors.addWidget(self.sequence_monitor, 1)
        monitors.addWidget(self.metadata_monitor, 1)
        work_layout.addLayout(monitors, 2)
        self.timeline = PacketTimeline()
        work_layout.addWidget(self.timeline, 2)
        self.waveform = IQWaveform()
        work_layout.addWidget(self.waveform, 3)
        scroll.setWidget(work)
        splitter.addWidget(scroll)
        sidebar = QWidget()
        sidebar.setMinimumWidth(330)
        sidebar.setMaximumWidth(530)
        side = QVBoxLayout(sidebar)
        side.setContentsMargins(4, 0, 0, 0)
        side.setSpacing(12)
        self.console = LogConsole()
        self.history = HistoricalMetrics()
        side.addWidget(self.console, 6)
        side.addWidget(self.history, 4)
        splitter.addWidget(sidebar)
        splitter.setSizes([1210, 430])
        self.workspace_stack = QStackedWidget()
        self.workspace_stack.addWidget(splitter)
        self.stage_d = ExperimentPanel(self.output_root / "stage_d")
        self.workspace_stack.addWidget(self.stage_d)
        self.stage_d.status_changed.connect(self._stage_status_changed)
        self.stage_d.controller.finished.connect(lambda _result: QTimer.singleShot(0, self.close) if self._close_pending else None)
        layout.addWidget(self.workspace_stack, 1)

        self.legacy_controls = QWidget()
        controls = QHBoxLayout(self.legacy_controls)
        controls.setContentsMargins(0, 0, 0, 0)
        self.run_button = QPushButton("▶  Run B5 Demo")
        self.run_button.setObjectName("PrimaryButton")
        self.run_button.setMinimumWidth(185)
        self.run_button.clicked.connect(self.start_demo)
        self.stop_button = QPushButton("■  Stop")
        self.stop_button.clicked.connect(self.stop_demo)
        self.reset_button = QPushButton("Reset Session")
        self.reset_button.clicked.connect(self.reset_session)
        clear = QPushButton("Clear Log")
        clear.clicked.connect(self.clear_log)
        export = QPushButton("Export Result")
        export.clicked.connect(self.export_result)
        for button in (self.run_button, self.stop_button, self.reset_button, clear, export):
            controls.addWidget(button)
        controls.addStretch()
        self.session_label = QLabel()
        self.session_label.setObjectName("footnote")
        controls.addWidget(self.session_label)
        layout.addWidget(self.legacy_controls)

    def _load_settings(self):
        try:
            data = json.loads((self.output_root / "settings.json").read_text(encoding="utf-8"))
            for mode in ("B5", "B6"):
                if mode in data:
                    config = DemoConfig(**data[mode])
                    config.validate()
                    self.configs[mode] = config.to_dict()
        except (OSError, ValueError, TypeError):
            pass

    def _selection_changed(self, _index=None):
        if self.stage_d.controller.connected or self.stage_d.controller.busy:
            self.mode_combo.blockSignals(True)
            self.source_combo.blockSignals(True)
            self.mode_combo.setCurrentIndex(2)
            self.source_combo.setCurrentIndex(0 if self.stage_d.source == "REPLAY" else 1)
            self.mode_combo.blockSignals(False)
            self.source_combo.blockSignals(False)
            self.stage_d.log("WARN", "APP", "Disconnect Stage D before switching workspace or source.")
            return
        if self.running:
            self.mode_combo.blockSignals(True)
            self.source_combo.blockSignals(True)
            self.mode_combo.setCurrentIndex(0 if self.session.mode == "B5" else 1)
            self.source_combo.setCurrentIndex(0 if self.session.source == "REPLAY" else 1)
            self.mode_combo.blockSignals(False)
            self.source_combo.blockSignals(False)
            self._on_log("WARN", "APP", "Stop the current session before switching mode or source.")
            return
        self._autosave(force=True)
        if self.mode == "STAGED":
            self.stage_d.set_source(self.source)
            self._refresh()
            return
        self._new_session()

    def _new_session(self):
        self.session = Session(mode=self.mode, source=self.source, parameters=self.configs[self.mode].copy())
        self.session_dir = None
        self.raw_logs = []
        self.console.clear()
        self.waveform.clear()
        self._wave_future = None
        self._wave_final = False
        self._capture_last_count = 0
        self.topology.set_mode(self.mode)
        self._refresh()

    def start_demo(self) -> bool:
        if self.mode == "STAGED":
            return self.stage_d.start_replay_demo() if self.source == "REPLAY" else self.stage_d.start_run()
        if self.running or self.session.state in ("PREPARING", "RUNNING"):
            self._on_log("WARN", "APP", "A session is already running; duplicate start ignored.")
            return False
        try:
            DemoConfig(**self.configs[self.mode]).validate()
        except (ValueError, TypeError) as exc:
            self._on_log("ERROR", "APP", str(exc))
            return False
        self._autosave(force=True)
        self._new_session()
        self.session.start()
        self.session_dir = self.output_root / f"{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}_{self.mode}_{self.source}"
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.active_runner = self.replay_service if self.source == "REPLAY" else self.process_runner
        self._on_log("INFO", "APP", f"Session source={self.source}; {self.mode}. " +
                     ("SIMULATED FIXTURE — no UDP or hardware connection." if self.source == "REPLAY" else
                      "Launching original validation tool. Board must already run the matching bitstream / ELF."))
        self._refresh()
        if not self.active_runner.start(self.mode, self.configs[self.mode].copy(), self.session_dir):
            if self.session.state in ("PREPARING", "RUNNING"):
                self.session.apply(Event("SESSION_ERROR", self.source, {"message": "Unable to start runner"}))
                self.session.finish(2)
            self.active_runner = None
            self._refresh()
            return False
        return True

    def stop_demo(self):
        if self.mode == "STAGED":
            self.stage_d.controller.stop()
            return
        if self.running:
            self._on_log("WARN", "APP", "Stop requested; waiting for worker process to release resources.")
            self.stop_button.setEnabled(False)
            self.active_runner.stop()

    def reset_session(self) -> bool:
        if self.mode == "STAGED":
            return self.stage_d.reset_session()
        if self.running:
            self._on_log("WARN", "APP", "Stop the active task before resetting its session.")
            return False
        self._autosave(force=True)
        self._new_session()
        self._on_log("INFO", "APP", "Session reset. Previous session artifacts remain in output/.")
        return True

    def _on_event(self, event: Event):
        if event.source != self.session.source or self.session.state not in ("PREPARING", "RUNNING"):
            return
        before = len(self.session.packets)
        self.session.apply(event)
        if event.kind == "PACKET_PASS" and len(self.session.packets) > before:
            kind = event.data.get("packet_type", "DATA")
            self.topology.pulse(kind)
            if kind == "DATA" and self.mode == "B6":
                self._show_golden(int(event.data.get("round", 0)))
        self._refresh()

    def _show_golden(self, round_id: int):
        # Pure deterministic model: this is never represented as FPGA output.
        from scripts.verify.tools.difi_b6_sender import expected_iq
        words = [expected_iq(round_id, i) for i in range(256)]
        signed = lambda value: value - 65536 if value & 0x8000 else value
        self.waveform.set_samples([signed(w >> 16) for w in words], [signed(w & 65535) for w in words],
                                  f"Golden Reference · {self.source} · round {round_id} · NOT FPGA returned IQ")

    def _on_log(self, level: str, source: str, message: str):
        timestamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        entry = dict(timestamp=timestamp, level=level, source=source, message=message)
        self.raw_logs.append(entry)
        self.console.append(level, source, message, timestamp)
        if self.session_dir:
            self._io_executor.submit(_append_raw, self.session_dir / "raw.log.txt",
                                     f"{timestamp} [{self.session.source}] [{source}] [{level}] {message}\n",
                                     self._io_errors)

    def _on_finished(self, exit_code: int, stopped: bool):
        if self.session.state not in ("PREPARING", "RUNNING"):
            return
        runner = self.active_runner
        self.session.finish(exit_code, stopped=stopped)
        self._on_log("PASS" if self.session.state == "COMPLETED" else "WARN" if stopped else "FAIL", "APP",
                     f"{self.session.source} {self.session.state}; exit={exit_code}; "
                     f"{sum(self.session.counts.values())}/{self.session.expected_packets} verified packets. " +
                     ("Offline fixture result only." if self.source == "REPLAY" else ""))
        if self.mode == "B5" and runner is not None:
            capture_path = getattr(runner, "capture_path", None)
            if capture_path and Path(capture_path).exists():
                self._wave_session = self.session.id
                self._wave_final = True
                self._wave_future = self._executor.submit(decode_capture, capture_path)
        self.active_runner = None
        self._refresh()
        self._autosave(force=True)
        if self._close_pending:
            QTimer.singleShot(0, self.close)

    def _poll_waveform(self):
        while not self._io_errors.empty():
            self.session_label.setText(self._io_errors.get_nowait())
        if self._save_future is not None and self._save_future.done():
            try:
                self._save_future.result()
            except OSError as exc:
                self.session_label.setText(f"Auto-save failed: {exc}")
            self._save_future = None
        if self._export_future is not None and self._export_future.done():
            try:
                folder = self._export_future.result()
                self._on_log("INFO", "EXPORT", f"Saved TXT, JSON, Markdown and dashboard.png to {folder}")
            except OSError as exc:
                self._on_log("ERROR", "EXPORT", str(exc))
            self._export_future = None
        future = self._wave_future
        if future is None:
            # The original B5 receiver buffers file writes. Read only already
            # accepted records and retry until its next flush; never invent IQ.
            if self.running and self.mode == "B5" and self.session.counts["DATA"]:
                path = getattr(self.active_runner, "capture_path", None)
                if path and Path(path).exists() and self._capture_last_count < self.session.total_packets:
                    self._wave_session = self.session.id
                    self._wave_final = False
                    self._wave_future = self._executor.submit(decode_capture, path, limit=self.session.total_packets)
            return
        if not future.done():
            return
        self._wave_future = None
        if self._wave_session != self.session.id:
            return
        try:
            accepted_ids = {p["packet_id"] for p in self.session.packets if p.get("verified")}
            records = [record for record in future.result() if record["packet_id"] in accepted_ids]
            self._capture_last_count = len(records)
            data = [packet for packet in records if packet["packet_type"] == "DATA"]
            if data:
                last = data[-1]
                provenance = ("SIMULATED Capture Fixture" if self.source == "REPLAY" else "Received DIFI Payload")
                self.waveform.set_samples(last["i"], last["q"], f"{provenance} · B5 · last validated Data packet")
        except (ValueError, OSError, struct.error) as exc:
            if self._wave_final:
                self._on_log("ERROR", "CAPTURE", f"Cannot decode captured IQ: {exc}")

    def _refresh(self):
        self.workspace_stack.setCurrentIndex(1 if self.mode == "STAGED" else 0)
        self.legacy_controls.setVisible(self.mode != "STAGED")
        self.settings_button.setVisible(self.mode != "STAGED")
        if self.mode == "STAGED":
            self._stage_status_changed(self.stage_d.controller.snapshot())
            return
        state = self.session.state
        active = state in ("PREPARING", "RUNNING")
        self.run_button.setText(f"▶  Run {self.mode} Demo")
        self.run_button.setEnabled(not active)
        self.stop_button.setEnabled(active)
        self.reset_button.setEnabled(not active)
        self.settings_button.setEnabled(not active)
        self.mode_combo.setEnabled(not active)
        self.source_combo.setEnabled(not active)
        self.source_badge.setText("REPLAY / OFFLINE" if self.source == "REPLAY" else "LIVE / HARDWARE")
        self.source_badge.setStyleSheet("color: #ffbd69; background: #2a2319; border: 1px solid #79572c; padding: 10px 14px; border-radius: 6px;" if self.source == "REPLAY" else
                                       "color: #53d7ef; background: #102d38; border: 1px solid #286276; padding: 10px 14px; border-radius: 6px;")
        color = {"COMPLETED": "#5ee2ad", "FAILED": "#ff6c86", "STOPPED": "#ffbd69"}.get(state, "#53d7ef" if active else "#9aaec6")
        self.state_badge.setText(f"●  {state}")
        self.state_badge.setStyleSheet(f"color:{color}; font:600 13px 'Consolas';")
        p = self.configs[self.mode]
        self.endpoint_label.setText(f"BOARD  {p['board']}     PC  {p['local_ip']}     UDP  {p['port']}")
        self.endpoint_label.setToolTip(self.endpoint_label.text())
        if self.source == "REPLAY":
            preflight = "OFFLINE FIXTURE  ·  No hardware connection. All packet events and IQ sources are labeled simulated / Golden Reference."
        elif self.mode == "B5":
            preflight = "B5 HARDWARE REQUIRED  ·  Load B5 bitstream + ELF, initialize UTC through UART, then wait for START. Run launches the receiver, which sends START once."
        else:
            preflight = "B6 HARDWARE REQUIRED  ·  Load B6 v0.2 bitstream + difi_b6_udp_rx_pro ELF. STATUS supplies board counters; ACK validates each packet. IQ curve is Golden Reference."
        self.preflight_label.setText(preflight)
        self.session_label.setText(f"{self.session.source}  /  {self.session.id[:8]}  /  AUTO-SAVE")
        self.topology.set_mode(self.mode)
        self.topology.set_status(state)
        for widget in (self.packet_summary, self.iq_verification, self.sequence_monitor, self.metadata_monitor, self.timeline):
            widget.update_session(self.session)

    def _stage_status_changed(self, snapshot):
        if self.mode != "STAGED":
            return
        locked = snapshot.get("connected") or snapshot.get("busy")
        self.mode_combo.setEnabled(not locked)
        self.source_combo.setEnabled(not locked)
        self.source_badge.setText("REPLAY / OFFLINE" if self.source == "REPLAY" else "LIVE / HARDWARE")
        self.source_badge.setStyleSheet("color:#ffbd69; background:#2a2319; border:1px solid #79572c; padding:10px 14px; border-radius:6px;" if self.source == "REPLAY" else
                                       "color:#53d7ef; background:#102d38; border:1px solid #286276; padding:10px 14px; border-radius:6px;")
        self.state_badge.setText("●  " + snapshot["state"])
        self.state_badge.setStyleSheet(f"color:{'#fa7c87' if snapshot['state'] in {'FAULT', 'RECOVERY_REQUIRED'} else '#54d3ed'}; font:600 13px Consolas;")
        self.endpoint_label.setText(f"STAGE D  ·  {self.stage_d.board.text()}:{self.stage_d.port.value()}  ·  single socket / dual DMA")
        self.preflight_label.setText("STAGE D · ONE BITSTREAM / ONE ELF · HALF DUPLEX  ·  " +
                                     ("Offline fixtures are simulated. Local Preview is never an FPGA measurement." if self.source == "REPLAY" else
                                      "Connect explicitly negotiates v0.3 / v0.4. TX and RX require real returned bytes. Stop drains before direction changes."))

    def open_settings(self):
        if self.mode == "STAGED":
            self.stage_d.tabs.setCurrentIndex(0)
            return
        if self.running:
            return
        dialog = SettingsDialog(self.mode, self.configs[self.mode], self)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self._autosave(force=True)
            self.configs[self.mode] = dialog.values()
            try:
                (self.output_root / "settings.json").write_text(json.dumps(self.configs, indent=2), encoding="utf-8")
            except OSError as exc:
                self._on_log("ERROR", "SETTINGS", str(exc))
            self._new_session()

    def clear_log(self):
        # The visual console may be cleared; raw per-session evidence stays retained.
        self.console.clear()

    def _autosave(self, force=False):
        if self.session_dir and (force or self._save_future is None or self._save_future.done()):
            snapshot = self.session.to_dict()
            logs = [dict(entry) for entry in self.raw_logs]
            self._save_future = self._io_executor.submit(export_session, snapshot, logs, self.session_dir)

    def export_result(self):
        if self.mode == "STAGED":
            self.stage_d.export_result()
            return
        if self._export_future is not None:
            self._on_log("WARN", "EXPORT", "An export is already in progress.")
            return
        destination = QFileDialog.getExistingDirectory(self, "Export session results", str(self.output_root))
        if not destination:
            return
        folder = Path(destination) / f"DIFI_{self.session.mode}_{self.session.source}_{self.session.id[:8]}"
        self._export_future = self._io_executor.submit(self._export_snapshot, self.session.to_dict(),
                                                      [dict(row) for row in self.raw_logs], folder,
                                                      self.grab().toImage())

    @staticmethod
    def _export_snapshot(snapshot, logs, folder, image):
        export_session(snapshot, logs, folder)
        if not image.save(str(folder / "dashboard.png")):
            raise OSError("Could not save the exported dashboard image")
        return folder

    def save_screenshot(self):
        filename, _ = QFileDialog.getSaveFileName(self, "Save dashboard image", str(self.output_root / "dashboard.png"), "PNG image (*.png)")
        if filename and not self.grab().save(filename):
            QMessageBox.warning(self, "Screenshot", "Could not save the image to this location.")

    def closeEvent(self, event: QCloseEvent):
        if self.running:
            self._close_pending = True
            self.stop_demo()
            event.ignore()
            return
        self._autosave(force=True)
        self.stage_d.shutdown()
        self._poll_timer.stop()
        self._autosave_timer.stop()
        self._executor.shutdown(wait=False, cancel_futures=True)
        self._io_executor.shutdown(wait=False)
        event.accept()
