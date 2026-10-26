"""Paged half-duplex experiment workspace, isolated from the legacy runners."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import time
from types import SimpleNamespace

from PySide6.QtCore import QTimer, Signal
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout, QGridLayout,
    QHBoxLayout, QLabel, QLineEdit, QMessageBox, QPlainTextEdit, QPushButton,
    QScrollArea, QSpinBox, QSplitter, QTabWidget, QVBoxLayout, QWidget,
)
from PySide6.QtCore import Qt

from ..models.events import utc_now
from ..theme import COLORS
from ..widgets.common import Card, metric
from ..widgets.historical_metrics import HistoricalMetrics
from ..widgets.log_console import LogConsole
from ..widgets.packet_timeline import PacketTimeline
from ..widgets.sequence_monitor import SequenceMonitor
from .client import legacy_iq
from .controller import ExperimentController
from .editors import IQEditor, PacketEditor, notice
from .exporter import export_experiment, load_experiment
from .iq import import_iq_bin, import_iq_csv
from .profile import ProfileConfig, encode_iq, parse_packet
from .waveforms import ComparisonWaveform, ExperimentTopology


def _load_file(kind, path, endian="big"):
    path = Path(path)
    if kind == "csv":
        samples = import_iq_csv(path)
        if not 1 <= len(samples) <= 256:
            raise ValueError("A hardware IQ dataset must contain 1..256 samples")
        return samples
    if kind == "bin":
        if path.stat().st_size > 1024:
            raise ValueError("IQ BIN exceeds 256 I16/Q16 samples")
        return import_iq_bin(path, endian)
    if kind == "packet":
        if path.stat().st_size > 1052:
            raise ValueError("DIFI packet exceeds the frozen 256-sample profile")
        raw = path.read_bytes()
        parse_packet(raw)
        return raw
    if kind == "evidence":
        return load_experiment(path)
    return json.loads(path.read_text(encoding="utf-8"))


def _write_preset(path, data):
    Path(path).write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    return Path(path)


def _save_evidence(snapshot, destination, image=None):
    """All file encoding/writing is performed outside the Qt thread."""
    paths = export_experiment(snapshot, destination)
    Path(destination, "operator_log.json").write_text(json.dumps(snapshot.get("operator_logs", []), indent=2, ensure_ascii=False), encoding="utf-8")
    if image is not None and not image.save(str(Path(destination) / "dashboard.png")):
        raise OSError("Could not save the Dashboard screenshot")
    return paths


class ExperimentTimeline(PacketTimeline):
    def _show_detail(self, item):
        if item.get("expected"):
            return super()._show_detail(item)
        self.detail.setText(f"{item.get('direction')} · {item.get('packet_type')} · Seq {item.get('sequence')} · "
                            f"{item.get('payload_bytes')} B · {item.get('status')} · "
                            f"Round {item.get('round')} · {item.get('source')} · {item.get('timestamp', 'N/A')}")


class ExperimentPanel(QWidget):
    status_changed = Signal(object)

    def __init__(self, output_root: Path, parent=None):
        super().__init__(parent)
        self.output_root = Path(output_root)
        self.output_root.mkdir(parents=True, exist_ok=True)
        self.controller = ExperimentController(self)
        self.source = "REPLAY"
        self.session_dir = None
        self._directory_session = None
        self.logs = []
        self._snapshot = self.controller.snapshot()
        self._io = ThreadPoolExecutor(max_workers=1, thread_name_prefix="stage-d-evidence")
        self._tasks = []
        self._save_future = None
        self._syncing = False
        self._last_records = None
        self._replay_demo = False
        self._archive = None
        self._closed = False
        self._build_ui()
        self.controller.changed.connect(self._changed)
        self.controller.log.connect(self.log)
        self.controller.event.connect(self._event)
        self.controller.finished.connect(self._finished)
        self.editor.changed.connect(self._profile_changed)
        self.iq_editor.changed.connect(self._iq_changed)
        self.editor.import_requested.connect(self.import_packet)
        self.iq_editor.import_requested.connect(self.import_iq)
        self.iq_editor.save_requested.connect(self.save_preset)
        self.iq_editor.load_requested.connect(self.load_preset)
        self._timer = QTimer(self)
        self._timer.setInterval(100)
        self._timer.timeout.connect(self._poll_files)
        self._timer.start()
        self._auto = QTimer(self)
        self._auto.setInterval(2000)
        self._auto.timeout.connect(self.autosave)
        self._auto.start()
        self._profile_changed()
        self._changed(self._snapshot)
        self.log("INFO", "REPLAY", "Stage D workspace ready. Connect is explicit. Local preview is never an FPGA measurement.")

    def _build_ui(self):
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(9)
        self.tabs = QTabWidget()
        self.overview = QWidget()
        overview = QVBoxLayout(self.overview)
        overview.setContentsMargins(8, 10, 8, 8)
        row = QHBoxLayout()
        connection = Card("BOARD CONNECTION")
        self.board = QLineEdit("192.168.1.10")
        self.local_ip = QLineEdit("192.168.1.20")
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        self.port.setValue(4991)
        self.local_port = QSpinBox()
        self.local_port.setRange(0, 65535)
        self.local_port.setToolTip("v0.3 locks the UDP peer. 0 selects an ephemeral port; keep this connection open for the entire session.")
        self.timeout = QDoubleSpinBox()
        self.timeout.setRange(.2, 120)
        self.timeout.setValue(5)
        self.timeout.setSuffix(" s")
        self.replay_version = QComboBox()
        self.replay_version.addItem("v0.4 · custom IQ / variable length", 4)
        self.replay_version.addItem("v0.3 · fixed profile compatibility", 3)
        form = QFormLayout()
        for title, widget in (("Board IPv4", self.board), ("PC bind IPv4", self.local_ip),
                              ("UDP destination port", self.port), ("PC source port / 0 = auto", self.local_port),
                              ("Timeout", self.timeout), ("Offline firmware fixture", self.replay_version)):
            form.addRow(title, widget)
        connection.body.addLayout(form)
        self.connection_fields = [self.board, self.local_ip, self.port, self.local_port, self.timeout, self.replay_version]
        buttons = QHBoxLayout()
        self.connect_button = QPushButton("Connect")
        self.connect_button.setObjectName("PrimaryButton")
        self.disconnect_button = QPushButton("Disconnect")
        self.utc_button = QPushButton("Initialize UTC once")
        self.connect_button.clicked.connect(self.connect_board)
        self.disconnect_button.clicked.connect(self.disconnect)
        self.utc_button.clicked.connect(self.initialize_utc)
        for button in (self.connect_button, self.disconnect_button, self.utc_button):
            buttons.addWidget(button)
        connection.body.addLayout(buttons)
        self.connection_note = notice("STATUS identifies firmware before any version-specific command. UTC is initialized only by this button when reported invalid.")
        connection.body.addWidget(self.connection_note)
        row.addWidget(connection, 5)

        right = QVBoxLayout()
        summary = Card("TRANSACTION SUMMARY")
        self.metrics = {}
        grid = QGridLayout()
        for index, (key, title, color) in enumerate((("tx", "Validated TX packets", COLORS["DATA"]),
                                                  ("rx", "Confirmed RX packets", COLORS["VERSION"]),
                                                  ("iq", "Verified returned IQ", COLORS["success"]),
                                                  ("mismatch", "Observed mismatches", COLORS["error"]))):
            box, value = metric("0", title, color, 27)
            self.metrics[key] = value
            grid.addLayout(box, index // 2, index % 2)
        summary.body.addLayout(grid)
        self.result_label = notice("No transaction has been measured")
        summary.body.addWidget(self.result_label)
        right.addWidget(summary, 4)
        capabilities = Card("FIRMWARE CAPABILITIES")
        self.capabilities = QPlainTextEdit()
        self.capabilities.setReadOnly(True)
        self.capabilities.setStyleSheet("font:11px Consolas;")
        self.capabilities.setMaximumHeight(135)
        capabilities.body.addWidget(self.capabilities, 1)
        self.restrictions = notice("Not connected. Custom controls will only drive supported firmware capabilities.")
        capabilities.body.addWidget(self.restrictions)
        right.addWidget(capabilities, 5)
        row.addLayout(right, 5)
        overview.addLayout(row, 4)
        self.topology = ExperimentTopology()
        overview.addWidget(self.topology, 3)
        self.live_note = notice("No automatic UDP on launch. The same socket is retained across TX/RX. Stop drains an in-flight operation; an indeterminate board state requires reconnect or board reload.")
        overview.addWidget(self.live_note)
        overview.addStretch(1)
        self.tabs.addTab(self._scroll(self.overview), "Overview")

        self.editor = PacketEditor()
        self.iq_editor = IQEditor()
        self.waveform = ComparisonWaveform()
        self.tabs.addTab(self._scroll(self.editor), "Packet Editor")
        self.tabs.addTab(self._scroll(self.iq_editor), "IQ Generator")
        self.tabs.addTab(self.waveform, "Waveform / Compare")

        timeline_page = QWidget()
        timeline_layout = QVBoxLayout(timeline_page)
        filter_row = QHBoxLayout()
        filter_row.addWidget(QLabel("Sequence observation direction"))
        self.sequence_direction = QComboBox()
        self.sequence_direction.addItems(["TX", "RX"])
        filter_row.addWidget(self.sequence_direction)
        filter_row.addStretch()
        timeline_layout.addLayout(filter_row)
        self.sequence = SequenceMonitor()
        self.timeline = ExperimentTimeline()
        timeline_layout.addWidget(self.sequence)
        timeline_layout.addWidget(self.timeline)
        self.metadata = QPlainTextEdit()
        self.metadata.setReadOnly(True)
        self.metadata.setStyleSheet("font:11px Consolas;")
        timeline_layout.addWidget(self.metadata, 1)
        self.sequence_direction.currentIndexChanged.connect(lambda _: self._update_evidence())
        self.tabs.addTab(timeline_page, "Timeline / Metadata")

        self.console = LogConsole()
        self.tabs.addTab(self.console, "Log Console")
        evidence = QWidget()
        ev_layout = QVBoxLayout(evidence)
        ev_layout.addWidget(HistoricalMetrics())
        ev_layout.addWidget(notice("Archived performance and build reports remain separate from this session. Stage D transactions are functional experiments, not a network bandwidth benchmark."))
        io_buttons = QHBoxLayout()
        self.export_button = QPushButton("Export full evidence + screenshot")
        self.reload_button = QPushButton("Open exported evidence offline")
        self.export_button.clicked.connect(self.export_result)
        self.reload_button.clicked.connect(self.open_evidence)
        io_buttons.addWidget(self.export_button)
        io_buttons.addWidget(self.reload_button)
        ev_layout.addLayout(io_buttons)
        self.evidence_note = notice("Each session retains actual DIFI bytes, actual returned IQ, reference, comparison, configuration, firmware capabilities and timestamps. Offline reload verifies the raw files and never establishes a hardware connection.")
        ev_layout.addWidget(self.evidence_note)
        ev_layout.addStretch(1)
        self.tabs.addTab(evidence, "Export / Archived Metrics")
        outer.addWidget(self.tabs, 1)

        self.status_label = QLabel("DISCONNECTED · REPLAY / OFFLINE")
        self.status_label.setWordWrap(True)
        self.status_label.setObjectName("preflight")
        outer.addWidget(self.status_label)
        controls = QHBoxLayout()
        self.direction = QComboBox()
        self.direction.addItems(["TX", "RX"])
        self.rounds = QSpinBox()
        self.rounds.setRange(1, 1000)
        self.rounds.setValue(2)
        self.rounds.setPrefix("Rounds ")
        self.alternate = QCheckBox("TX → RX → TX · cycles")
        self.alternate.setChecked(True)
        self.run_button = QPushButton("▶ Run experiment")
        self.run_button.setObjectName("PrimaryButton")
        self.stop_button = QPushButton("■ Stop / drain")
        self.reset_button = QPushButton("Reset Session")
        self.apply_button = QPushButton("Apply profile to FPGA")
        self.run_button.clicked.connect(self.start_run)
        self.stop_button.clicked.connect(self.controller.stop)
        self.reset_button.clicked.connect(self.reset_session)
        self.apply_button.clicked.connect(self.apply_config)
        self.direction.currentTextChanged.connect(lambda _: self._update_controls())
        self.alternate.toggled.connect(lambda _: self._update_controls())
        for widget in (self.direction, self.rounds, self.alternate, self.run_button, self.stop_button, self.reset_button, self.apply_button):
            controls.addWidget(widget)
        controls.addStretch(1)
        outer.addLayout(controls)

    @staticmethod
    def _scroll(widget):
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        scroll.setWidget(widget)
        return scroll

    def set_source(self, source):
        source = str(source).upper()
        if self.controller.connected or self.controller.busy:
            raise RuntimeError("Disconnect the Stage D session before changing its source")
        if source != self.source:
            self.autosave(force=True)
            self.controller.reset()
            self.controller.session.source = source
            self.session_dir = None
            self._directory_session = None
            self.logs = []
            self.console.clear()
        self.source = source
        self._archive = None
        self._last_records = None
        self._changed(self.controller.snapshot())
        self._update_controls()

    def connection_parameters(self):
        return dict(board=self.board.text().strip(), local_ip=self.local_ip.text().strip(),
                    port=self.port.value(), local_port=self.local_port.value(), timeout=self.timeout.value(),
                    replay_version=self.replay_version.currentData())

    def connect_board(self):
        if self.controller.busy or self.controller.connected:
            return False
        self.autosave(force=True)
        self._archive = None
        self.logs = []
        self.console.clear()
        self._last_records = None
        try:
            started = self.controller.connect_board(self.connection_parameters(), self.source)
            if started and self._directory_session != self.controller.session.id:
                self.session_dir = self.output_root / f"{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}_{self.source}_{self.controller.session.id[:8]}"
                self.session_dir.mkdir(parents=True, exist_ok=True)
                self._directory_session = self.controller.session.id
            if started:
                self.log("INFO", self.source, "Opening one Stage D connection. " + ("SIMULATED FIXTURE; no UDP or physical FPGA." if self.source == "REPLAY" else "Original board state will be queried before commands are enabled."))
            return started
        except (ValueError, OSError) as exc:
            self.log("ERROR", self.source, str(exc))
            return False

    def disconnect(self):
        self._replay_demo = False
        return self.controller.disconnect()

    def initialize_utc(self):
        ns = time.time_ns()
        return self.controller.initialize_utc(ns // 1_000_000_000, ns % 1_000_000_000)

    def apply_config(self):
        try:
            return self.controller.configure(self.editor.config())
        except (ValueError, RuntimeError) as exc:
            self.log("ERROR", self.source, str(exc))
            return False

    def _profile_changed(self):
        if self._syncing:
            return
        self._syncing = True
        try:
            cfg = self.editor.config()
            self.iq_editor.set_shape(cfg.samples, cfg.sample_rate)
        except (ValueError, TypeError) as exc:
            self.log("WARN", "LOCAL PREVIEW", str(exc))
        finally:
            self._syncing = False
        self._set_managed_sequence(force=True)
        self.waveform.set_reference(self.iq_editor.samples)
        self._update_controls()

    def _iq_changed(self):
        if self._syncing:
            return
        self._syncing = True
        try:
            self.editor.fields["samples"].setValue(self.iq_editor.count.value())
            self.editor.fields["sample_rate"].setValue(self.iq_editor.sample_rate.value())
        finally:
            self._syncing = False
        self.editor.refresh_preview(self.iq_editor.samples)
        self.waveform.set_reference(self.iq_editor.samples)
        self._update_controls()

    def _update_controls(self):
        if not hasattr(self, "run_button"):
            return
        c, snapshot = self.controller, self._snapshot
        status = snapshot.get("status", {})
        legacy = snapshot.get("protocol_version") == 3
        ready = c.connected and c.state in {"READY", "WAITING_RX"} and not c.busy and self._archive is None
        for field in self.connection_fields:
            field.setEnabled(not c.connected and not c.busy)
        self.replay_version.setVisible(self.source == "REPLAY")
        self.connect_button.setEnabled(not c.connected and not c.busy)
        self.disconnect_button.setEnabled(c.connected and not c.busy)
        self.utc_button.setEnabled(ready and not bool(status.get("UTC")))
        caps = snapshot.get("capabilities", {})
        self.apply_button.setEnabled(ready and not legacy and bool(status.get("UTC")) and caps.get("CONFIG") == 1)
        self.stop_button.setEnabled(c.busy)
        self.reset_button.setEnabled(not c.busy and not c.connected)
        self.reload_button.setEnabled(not c.busy and not c.connected)
        self.direction.setEnabled(ready)
        self.rounds.setEnabled(ready)
        self.alternate.setEnabled(ready and self.direction.currentText() == "TX")
        self.editor.setEnabled(not c.busy)
        self.iq_editor.setEnabled(not c.busy)
        if legacy and not c.busy:
            self.direction.blockSignals(True)
            self.direction.setCurrentText("RX" if c.state == "WAITING_RX" else "TX")
            self.direction.blockSignals(False)
            self.direction.setEnabled(False)
        kind_valid = self.direction.currentText() == "RX" or self.editor.kind.currentText() == "DATA"
        direction_supported = legacy or caps.get("CUSTOM_" + self.direction.currentText()) == 1
        sample_supported = legacy or int(caps.get("MIN_SAMPLES", 1)) <= self.editor.fields["samples"].value() <= int(caps.get("MAX_SAMPLES", 256))
        self.run_button.setEnabled(ready and bool(status.get("UTC")) and direction_supported and sample_supported
                                   and (legacy or bool(self.editor.packet)) and (legacy or kind_valid))
        self.run_button.setToolTip("TX packet type is Data; FPGA automatically emits startup Version / configuration Context. Use RX to send an arbitrary supported metadata packet." if not kind_valid else "")
        self.status_label.setText(f"{c.state}  ·  {'REPLAY / OFFLINE' if self.source == 'REPLAY' else 'LIVE / HARDWARE'}  ·  "
                                  f"UTC={status.get('UTC', 'N/A')}  ·  Protocol {snapshot.get('protocol_version') or 'not negotiated'}  ·  Session {c.session.id[:8]}")
        if self._archive:
            self.status_label.setText(f"OFFLINE ARCHIVE · recorded {self._archive['source']} · {self._archive['id'][:8]} · no hardware connection")

    def start_run(self):
        try:
            if not self.controller.connected or self.controller.busy:
                self.log("WARN", self.source, "Connect and wait for READY before Run.")
                return False
            legacy = self._snapshot.get("protocol_version") == 3
            direction = self.direction.currentText()
            if legacy:
                # Firmware, rather than the PC generator, is the v0.3 source.
                config, samples, packet = ProfileConfig(), None, None
                if direction == "TX":
                    fixed = legacy_iq(int(self._snapshot.get("status", {}).get("TX", 0)))
                    self.waveform.set_reference(fixed)
                    self.log("INFO", self.source, "v0.3 fixed firmware pattern selected. Custom local IQ / Packet Editor settings are not uploaded.")
            else:
                config = self.editor.config()
                samples = list(self.iq_editor.samples)
                if direction == "TX" and self.editor.kind.currentText() != "DATA":
                    raise ValueError("Version-on-demand TX is not supported by the frozen RTL. TX Data automatically captures available FPGA metadata.")
                self._set_managed_sequence(force=True)
                packet = self.editor.make_packet(samples) if direction == "RX" else None
                if packet is not None:
                    parse_packet(packet, config)
                encode_iq(samples)
                if (direction == "TX" or self.editor.kind.currentText() == "DATA") and len(samples) != config.samples:
                    raise ValueError("IQ count must match Samples per Packet")
            self._archive = None
            return self.controller.run(direction, samples, packet=packet, rounds=self.rounds.value(),
                                       alternate=self.alternate.isChecked() and direction == "TX", config=config)
        except (ValueError, RuntimeError) as exc:
            self.log("ERROR", self.source, str(exc))
            return False

    def _set_managed_sequence(self, force=False):
        key = {"DATA": "RX_DATA_NEXT", "CONTEXT": "RX_CONTEXT_NEXT", "VERSION": "RX_VERSION_NEXT"}[self.editor.kind.currentText()]
        sequence = int(self._snapshot.get("status", {}).get(key, 0)) & 15
        if force or sequence != self.editor.sequence:
            self.editor.set_sequence(sequence)
            self.editor.refresh_preview(self.iq_editor.samples)

    def _changed(self, snapshot):
        previous_id = self._snapshot.get("session", {}).get("id")
        new_id = snapshot.get("session", {}).get("id")
        if new_id != previous_id:
            self.autosave(force=True)
            self.logs = []
            self.console.clear()
            self._last_records = None
            if snapshot.get("busy") or snapshot.get("connected"):
                self.session_dir = self.output_root / f"{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}_{self.source}_{new_id[:8]}"
                self.session_dir.mkdir(parents=True, exist_ok=True)
                self._directory_session = new_id
            else:
                self.session_dir = None
                self._directory_session = None
        self._snapshot = snapshot
        caps, status = snapshot.get("capabilities", {}), snapshot.get("status", {})
        self.capabilities.setPlainText(json.dumps({"capabilities": caps, "observed_status": status}, indent=2, ensure_ascii=False))
        if snapshot.get("protocol_version") == 3:
            self.restrictions.setText("v0.3 COMPATIBILITY · 256 IQ · SID 1 / 2 · maximum 16 TX rounds · same source port · cached TX must be replayed through RX. Custom upload/configuration is disabled.")
        elif snapshot.get("protocol_version") == 4:
            self.restrictions.setText("v0.4 · custom signed IQ · 1–256 samples · real DMA1 TX and DMA0 RX capture. Only reported capabilities are enabled. FPGA Version is startup-only; PL time cannot be reset during a session.")
        else:
            self.restrictions.setText("Connect to identify v0.3 / v0.4. No capability is inferred from a missing response.")
        self._set_managed_sequence()
        self.topology.update_state(snapshot["state"], self.direction.currentText())
        self._update_evidence()
        self._update_controls()
        self.status_changed.emit(snapshot)

    def _event(self, event):
        if event.kind == "TRANSACTION_CAPTURED":
            record = event.data.get("transaction", {})
            types = [item["parsed"]["packet_type"] for item in record.get("packets", [])]
            self.topology.pulse(record.get("direction", "TX"), "DATA" if "DATA" in types else types[0] if types else "DATA")

    def _finished(self, result):
        if result.get("error"):
            self.status_label.setText(f"{result.get('state')} · {result['error']}")
        if result.get("operation") == "connect" and result.get("success"):
            self._last_records = None
        self.autosave(force=True)
        if self._replay_demo:
            if not result.get("success"):
                self._replay_demo = False
            elif result.get("operation") == "connect":
                if not self._snapshot.get("status", {}).get("UTC"):
                    self.initialize_utc()
                else:
                    self.start_run()
            elif result.get("operation") == "utc":
                self.start_run()
            elif result.get("operation") == "run":
                self._replay_demo = False

    def _display_session(self):
        return self._archive or self._snapshot.get("session", {})

    def _update_evidence(self):
        session = self._display_session()
        records = session.get("transactions", [])
        observed_status = session.get("status", {}) if self._archive else self._snapshot.get("status", {})
        signature = (session.get("id"), len(records), records[-1].get("transaction") if records else None,
                     self.sequence_direction.currentText(), session.get("state"), tuple(sorted(observed_status.items())))
        if self._last_records == signature:
            return
        self._last_records = signature
        flat, histories = [], {direction: {kind: [] for kind in ("VERSION", "CONTEXT", "DATA")} for direction in ("TX", "RX")}
        counts = {"VERSION": 0, "CONTEXT": 0, "DATA": 0}
        totals = {"TX": 0, "RX": 0}
        metadata, mismatches, verified = [], 0, 0
        for record in records:
            good = bool(record.get("comparison", {}).get("exact"))
            mismatches += int(record.get("comparison", {}).get("mismatches", 0))
            if good:
                verified += len(record.get("actual_iq", []))
            direction = record.get("direction", "TX")
            for index, item in enumerate(record.get("packets", [])):
                parsed = item["parsed"]
                kind, seq = parsed["packet_type"], parsed["sequence"]
                packet = dict(packet_id=f"{record.get('transaction')}:{direction}:{index}", packet_type=kind,
                              sequence=seq, payload_bytes=parsed["payload_bytes"], source=session.get("source"),
                              timestamp=record.get("timestamp", "N/A"), direction=direction, round=record.get("round"),
                              status="PASS" if good else "FAIL", verified=good)
                flat.append(packet)
                counts[kind] += 1
                totals[direction] += int(good)
                history = histories[direction][kind]
                previous = history[-1]["sequence"] if history else None
                issue = f"Expected {(previous + 1) & 15}, got {seq}" if previous is not None and seq != (previous + 1) & 15 else None
                history.append({**packet, "wrap": previous == 15 and seq == 0, "issue": issue})
                if kind != "DATA":
                    metadata.append({"direction": direction, "source": session.get("source"), "sequence": seq,
                                     "type": kind, "stream_id": parsed["stream_id"], "fields": parsed["fields"]})
        adapter = SimpleNamespace(packets=flat, expected_counts=counts, expected_iq=0,
                                  sequence_history=histories[self.sequence_direction.currentText()])
        self.timeline.update_session(adapter)
        self.sequence.update_session(adapter)
        self.metadata.setPlainText(json.dumps({"parsed_packet_metadata": metadata,
                                               "observed_status": observed_status,
                                               "GPIO_changed_or_errors": "Only reported STATUS fields are observable; no direct PC GPIO access."}, indent=2, ensure_ascii=False))
        self.metrics["tx"].setText(str(totals["TX"]))
        self.metrics["rx"].setText(str(totals["RX"]))
        self.metrics["iq"].setText(f"{verified:,}")
        self.metrics["mismatch"].setText(str(mismatches) if records else "N/A")
        origin = "REPLAY / OFFLINE" if session.get("source") == "REPLAY" else "LIVE FPGA EVIDENCE"
        if self._archive:
            origin = "OFFLINE ARCHIVE · recorded " + origin
        self.result_label.setText(f"{origin} · {session.get('state', 'DISCONNECTED')} · {len(records)} recorded transactions. " +
                                  ("No hardware PASS is claimed." if session.get("source") == "REPLAY" else "Only returned and verified bytes contribute to successful counts."))
        self.waveform.set_records(records, session.get("id", ""), archived=bool(self._archive))
        if records and records[-1].get("actual_iq"):
            self.waveform.selector.setCurrentIndex(4 if records[-1]["direction"] == "RX" else 3)

    def log(self, level, source, message):
        entry = dict(timestamp=utc_now(), level=level, source=source, message=message)
        self.logs.append(entry)
        self.console.append(level, source, message, entry["timestamp"])

    def reset_session(self):
        self.autosave(force=True)
        if not self.controller.reset():
            return False
        self.session_dir = None
        self._directory_session = None
        self._archive = None
        self.logs = []
        self.console.clear()
        self._last_records = None
        self._changed(self.controller.snapshot())
        return True

    def snapshot(self):
        # Admitted records are immutable. Freeze container membership here;
        # deep copying / JSON conversion of sample arrays happens in the worker.
        data = dict(self._display_session())
        data["transactions"] = list(data.get("transactions", []))
        data["events"] = list(data.get("events", []))
        data["errors"] = list(data.get("errors", []))
        data.update(config=deepcopy(data.get("config", {}) if self._archive else self._snapshot.get("config", {})),
                    local_profile_preview={name: int(field.value()) for name, field in self.editor.fields.items()},
                    status=deepcopy(data.get("status", {}) if self._archive else self._snapshot.get("status", {})),
                    offline_reanalysis=bool(self._archive),
                    local_reference_iq=[list(pair) for pair in self.iq_editor.samples],
                    generator=self.iq_editor.parameters(), operator_logs=deepcopy(self.logs))
        return data

    def autosave(self, force=False):
        if not self.session_dir or (self._save_future is not None and not self._save_future.done() and not force):
            return
        try:
            self._save_future = self._io.submit(_save_evidence, self.snapshot(), self.session_dir)
        except ValueError as exc:
            self.log("ERROR", "EXPORT", f"Cannot save invalid configuration: {exc}")

    def export_result(self):
        folder = QFileDialog.getExistingDirectory(self, "Export full Stage D evidence", str(self.output_root))
        if not folder:
            return
        try:
            data = self.snapshot()
            destination = Path(folder) / f"STAGE_D_{data['source']}_{data['id'][:8]}"
            image = self.window().grab().toImage()
            future = self._io.submit(_save_evidence, data, destination, image)
            self._tasks.append(("export", future, destination))
        except ValueError as exc:
            self.log("ERROR", "EXPORT", str(exc))

    def import_iq(self, kind):
        path, _ = QFileDialog.getOpenFileName(self, "Import local I/Q", "", "CSV (*.csv)" if kind == "csv" else "Raw IQ (*.bin *.iq)")
        if path:
            self._tasks.append(("iq", self._io.submit(_load_file, kind, path, self.iq_editor.byte_order.currentData()), Path(path)))

    def import_packet(self):
        path, _ = QFileDialog.getOpenFileName(self, "Import legal DIFI datagram", "", "DIFI datagram (*.difi *.bin);;All files (*)")
        if path:
            self._tasks.append(("packet", self._io.submit(_load_file, "packet", path), Path(path)))

    def save_preset(self):
        path, _ = QFileDialog.getSaveFileName(self, "Save local IQ / Profile preset", str(self.output_root / "local_preset.json"), "JSON (*.json)")
        if path:
            data = self.iq_editor.preset()
            data["profile"] = self.editor.config().to_dict()
            data["packet_type"] = self.editor.kind.currentText()
            self._tasks.append(("saved", self._io.submit(_write_preset, path, data), Path(path)))

    def load_preset(self):
        path, _ = QFileDialog.getOpenFileName(self, "Load reusable local preset", "", "JSON (*.json)")
        if path:
            self._tasks.append(("preset", self._io.submit(_load_file, "preset", path), Path(path)))

    def open_evidence(self):
        if self.controller.connected or self.controller.busy:
            self.log("WARN", "ARCHIVE", "Disconnect before opening an offline evidence bundle.")
            return
        path, _ = QFileDialog.getOpenFileName(self, "Open exported Stage D evidence", str(self.output_root), "Stage D evidence (experiment.json)")
        if path:
            self._tasks.append(("evidence", self._io.submit(_load_file, "evidence", path), Path(path)))

    def _poll_files(self):
        if self._save_future is not None and self._save_future.done():
            try:
                self._save_future.result()
            except (OSError, ValueError) as exc:
                self.log("ERROR", "AUTOSAVE", str(exc))
            self._save_future = None
        for kind, future, path in list(self._tasks):
            if not future.done():
                continue
            self._tasks.remove((kind, future, path))
            try:
                data = future.result()
                if kind == "iq":
                    self.iq_editor.set_samples(data, f"Imported PC input · {path.name}")
                elif kind == "packet":
                    parsed = self.editor.load_packet(data)
                    if parsed["packet_type"] == "DATA":
                        self.iq_editor.set_samples(parsed["iq"], f"Imported DIFI input · {path.name}")
                    self._profile_changed()
                elif kind == "preset":
                    self.editor.set_config(ProfileConfig.from_dict(data.get("profile", {})))
                    self.editor.kind.setCurrentText(data.get("packet_type", "DATA"))
                    self.iq_editor.load_preset(data)
                elif kind == "evidence":
                    self._archive = data
                    self._last_records = None
                    self._update_evidence()
                    self.tabs.setCurrentIndex(3)
                    self.status_label.setText(f"OFFLINE ARCHIVE · recorded {data['source']} · {data['id'][:8]} · no hardware connection")
                self.log("INFO", "FILES", f"{kind}: {path}")
            except (OSError, ValueError, TypeError, KeyError) as exc:
                self.log("ERROR", "FILES", str(exc))

    def start_replay_demo(self):
        if self.source != "REPLAY" or self.controller.busy:
            return False
        self._replay_demo = True
        self.direction.setCurrentText("TX")
        self.alternate.setChecked(True)
        self.rounds.setValue(2)
        if not self.controller.connected:
            return self.connect_board()
        if not self._snapshot.get("status", {}).get("UTC"):
            return self.initialize_utc()
        return self.start_run()

    def shutdown(self):
        if self._closed:
            return
        self._closed = True
        self.autosave(force=True)
        self._auto.stop()
        self._timer.stop()
        self.controller._timer.stop()
        self.controller.shutdown()
        self._io.shutdown(wait=False)
