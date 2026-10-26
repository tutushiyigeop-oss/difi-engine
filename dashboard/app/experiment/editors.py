"""Native editors for the frozen DIFI profile and explicitly local IQ data."""
from __future__ import annotations

import json
import math
import time
from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QComboBox, QDoubleSpinBox, QFormLayout, QGridLayout, QHBoxLayout,
    QHeaderView, QLabel, QPushButton, QPlainTextEdit, QSpinBox, QSplitter,
    QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

from ..widgets.common import Card
from ..widgets.iq_waveform import IQWaveform
from .profile import ProfileConfig, build_packet, parse_packet, encode_iq
from .iq import generate_iq


def integer_box(value, maximum=0xFFFFFFFF, minimum=0):
    box = QDoubleSpinBox()
    box.setDecimals(0)
    box.setRange(minimum, maximum)
    box.setValue(value)
    box.setKeyboardTracking(False)
    return box


def notice(text):
    label = QLabel(text)
    label.setWordWrap(True)
    label.setObjectName("CardSubtitle")
    return label


class PacketEditor(QWidget):
    changed = Signal()
    import_requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.sequence = 0
        self._loading = False
        self._iq = []
        self.packet = b""
        outer = QHBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        config_card = Card("PACKET EDITOR", "Frozen RTL / DIFI 1.1 restricted profile")
        config_card.badge.setText("LOCAL PREVIEW")
        self.kind = QComboBox()
        self.kind.addItems(["DATA", "CONTEXT", "VERSION"])
        self.fields = {
            "data_sid": integer_box(1), "version_sid": integer_box(2),
            "samples": integer_box(256, 256, 1),
            "sample_rate": integer_box(20_000_000, minimum=1),
            "bandwidth": integer_box(10_000_000, minimum=1),
            "rf_hz": integer_box(100_000_000, 100_000_000_000),
            "rx_filter": integer_box(3, 3), "rx_data_sid": integer_box(1),
            "rx_version_sid": integer_box(2),
        }
        self.seconds = integer_box(int(time.time()))
        self.picoseconds = integer_box(0, 999_999_999_999)
        self.sequence_label = QLabel("0 · system managed")
        form = QFormLayout()
        form.setVerticalSpacing(7)
        form.addRow("Packet type", self.kind)
        names = {"data_sid": "Data / Context Stream ID", "version_sid": "Version Stream ID",
                 "samples": "Samples per Data Packet", "sample_rate": "Sample rate / Hz",
                 "bandwidth": "Bandwidth / Hz", "rf_hz": "RF reference / Hz",
                 "rx_filter": "RX filter mask / 0..3", "rx_data_sid": "RX Data / Context SID",
                 "rx_version_sid": "RX Version SID"}
        for key, field in self.fields.items():
            form.addRow(names[key], field)
            field.valueChanged.connect(lambda _value: self._emit_changed())
        form.addRow("RX / preview UTC seconds", self.seconds)
        form.addRow("RX / preview picoseconds", self.picoseconds)
        form.addRow("Sequence (read only)", self.sequence_label)
        self.kind.currentIndexChanged.connect(lambda _: self._emit_changed())
        self.seconds.valueChanged.connect(lambda _: self._emit_changed())
        self.picoseconds.valueChanged.connect(lambda _: self._emit_changed())
        config_card.body.addLayout(form)
        config_card.body.addWidget(notice("OUI 0x006A621E · TSI UTC · TSF realtime picoseconds · Class ID, CIF and I16/Q16 DPF are generated read-only. TX uses the running PL clock. These time fields apply to RX and local preview."))
        buttons = QHBoxLayout()
        load = QPushButton("Import legal .difi packet")
        load.clicked.connect(self.import_requested.emit)
        buttons.addWidget(load)
        config_card.body.addLayout(buttons)
        config_card.body.addStretch(1)
        outer.addWidget(config_card, 4)

        preview = Card("PACKET INSPECTOR", "Validated bytes before transmission")
        self.size_label = QLabel("No valid packet")
        self.size_label.setStyleSheet("font:600 17px Consolas; color:#54d3ed;")
        preview.body.addWidget(self.size_label)
        self.error = notice("")
        self.error.setStyleSheet("color:#fa7c87;")
        preview.body.addWidget(self.error)
        splitter = QSplitter(Qt.Orientation.Vertical)
        self.words = QTableWidget(0, 3)
        self.words.setHorizontalHeaderLabels(["Word", "Network hex", "Field / frozen profile meaning"])
        self.words.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self.words.setColumnWidth(0, 55)
        self.words.setColumnWidth(1, 120)
        self.words.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.hex_view = QPlainTextEdit()
        self.hex_view.setReadOnly(True)
        self.hex_view.setStyleSheet("font:11px Consolas;")
        splitter.addWidget(self.words)
        splitter.addWidget(self.hex_view)
        splitter.setSizes([420, 160])
        preview.body.addWidget(splitter, 1)
        outer.addWidget(preview, 7)

    def _emit_changed(self):
        if not self._loading:
            self.changed.emit()

    def config(self):
        return ProfileConfig(**{name: int(field.value()) for name, field in self.fields.items()}).validate()

    def set_config(self, config):
        values = config.to_dict() if hasattr(config, "to_dict") else dict(config)
        self._loading = True
        try:
            for key, field in self.fields.items():
                if key in values:
                    field.setValue(values[key])
        finally:
            self._loading = False
        self.changed.emit()

    def set_sequence(self, value):
        self.sequence = int(value) & 15
        self.sequence_label.setText(f"{self.sequence} · system managed independently for {self.kind.currentText()}")

    def make_packet(self, iq=None):
        kind = self.kind.currentText()
        return build_packet(kind, self.config(), iq=(iq if iq is not None else self._iq) if kind == "DATA" else None,
                            sequence=self.sequence, seconds=int(self.seconds.value()),
                            picoseconds=int(self.picoseconds.value()), changed=True)

    def refresh_preview(self, iq):
        self._iq = list(iq)
        try:
            raw = self.make_packet()
            parsed = parse_packet(raw)
            self.packet = raw
            self.error.clear()
            count = len(parsed.get("iq", []))
            self.size_label.setText(f"{parsed['packet_type']}  ·  {len(raw):,} B  ·  {len(parsed['words'])} words  ·  Seq {parsed['sequence']}" + (f"  ·  {count} IQ" if count else ""))
            descriptions = parsed.get("word_descriptions", [])
            self.words.setRowCount(len(parsed["words"]))
            for row, word in enumerate(parsed["words"]):
                description = descriptions[row] if row < len(descriptions) else "I16 / Q16 payload"
                for col, value in enumerate((row, f"0x{word:08X}", description)):
                    self.words.setItem(row, col, QTableWidgetItem(str(value)))
            self.hex_view.setPlainText("\n".join(f"{off:04X}   " + raw[off:off + 16].hex(" ").upper() for off in range(0, len(raw), 16)))
            return True
        except (ValueError, TypeError, OverflowError) as exc:
            self.packet = b""
            self.size_label.setText("INVALID / SEND DISABLED")
            self.error.setText(str(exc))
            self.words.setRowCount(0)
            self.hex_view.clear()
            return False

    def load_packet(self, raw):
        parsed = parse_packet(raw)
        config = self.config().to_dict()
        kind = parsed["packet_type"]
        config["version_sid" if kind == "VERSION" else "data_sid"] = parsed["stream_id"]
        config["rx_version_sid" if kind == "VERSION" else "rx_data_sid"] = parsed["stream_id"]
        if kind == "DATA":
            config["samples"] = len(parsed["iq"])
        if kind == "CONTEXT":
            for name in ("sample_rate", "bandwidth", "rf_hz"):
                if name in parsed.get("fields", {}):
                    config[name] = parsed["fields"][name]
        self._loading = True
        try:
            self.kind.setCurrentText(kind)
            self.seconds.setValue(parsed["seconds"])
            self.picoseconds.setValue(parsed["picoseconds"])
        finally:
            self._loading = False
        self.set_config(ProfileConfig(**config).validate())
        return parsed


class IQEditor(QWidget):
    changed = Signal()
    import_requested = Signal(str)
    save_requested = Signal()
    load_requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.samples = []
        self._loading = False
        self.origin = "Generated on PC"
        outer = QHBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        controls = Card("IQ GENERATOR / IMPORTER")
        controls.badge.setText("LOCAL PREVIEW")
        form = QFormLayout()
        self.kind = QComboBox()
        for title, key in (("Complex sine · I cos / Q sin", "complex_sine"), ("Real sine · Q = 0", "real_sine"),
                           ("Constant I / Q", "constant"), ("Square wave", "square"),
                           ("Linear chirp", "chirp"), ("Seeded pseudorandom", "prbs")):
            self.kind.addItem(title, key)
        self.count = QSpinBox()
        self.count.setRange(1, 256)
        self.count.setValue(256)
        self.count.setKeyboardTracking(False)
        self.amplitude = QDoubleSpinBox()
        self.amplitude.setRange(0, 32767)
        self.amplitude.setValue(12000)
        self.amplitude.setKeyboardTracking(False)
        self.frequency = QDoubleSpinBox()
        self.frequency.setRange(-2_147_483_647, 2_147_483_647)
        self.frequency.setValue(1_000_000)
        self.frequency.setKeyboardTracking(False)
        self.sample_rate = integer_box(20_000_000, minimum=1)
        self.phase = QDoubleSpinBox()
        self.phase.setRange(-360000, 360000)
        self.phase.setValue(0)
        self.phase.setKeyboardTracking(False)
        self.seed = QSpinBox()
        self.seed.setRange(0, 2_147_483_647)
        self.seed.setValue(1)
        self.seed.setKeyboardTracking(False)
        self.constant_i = QSpinBox()
        self.constant_q = QSpinBox()
        for box in (self.constant_i, self.constant_q):
            box.setRange(-32768, 32767)
            box.setKeyboardTracking(False)
        self.chirp_end = QDoubleSpinBox()
        self.chirp_end.setRange(-2_147_483_647, 2_147_483_647)
        self.chirp_end.setValue(4_000_000)
        self.chirp_end.setKeyboardTracking(False)
        self.byte_order = QComboBox()
        self.byte_order.addItem("Network big endian · I16 then Q16", "big")
        self.byte_order.addItem("Little endian · I16 then Q16", "little")
        for title, widget in (("Signal", self.kind), ("Samples", self.count), ("Amplitude", self.amplitude),
                              ("Baseband frequency / Hz", self.frequency), ("Sample rate / Hz", self.sample_rate),
                              ("Initial phase / degrees", self.phase), ("Chirp end / Hz", self.chirp_end),
                              ("Seed", self.seed), ("Constant I", self.constant_i), ("Constant Q", self.constant_q),
                              ("Raw BIN byte order", self.byte_order)):
            form.addRow(title, widget)
        controls.body.addLayout(form)
        imports = QHBoxLayout()
        for title, key in (("Import CSV", "csv"), ("Import IQ BIN", "bin")):
            button = QPushButton(title)
            button.clicked.connect(lambda _checked=False, k=key: self.import_requested.emit(k))
            imports.addWidget(button)
        controls.body.addLayout(imports)
        presets = QHBoxLayout()
        for title, signal in (("Save reusable preset", self.save_requested), ("Load preset", self.load_requested)):
            button = QPushButton(title)
            button.clicked.connect(signal.emit)
            presets.addWidget(button)
        controls.body.addLayout(presets)
        controls.body.addWidget(notice("Signed int16 · −32768…32767. I occupies bits 31:16, Q bits 15:0. Local samples are never labeled as FPGA measurements."))
        self.error = notice("")
        self.error.setStyleSheet("color:#fa7c87;")
        controls.body.addWidget(self.error)
        controls.body.addStretch(1)
        outer.addWidget(controls, 4)
        right = QVBoxLayout()
        self.preview = IQWaveform()
        right.addWidget(self.preview, 5)
        table_card = Card("EDIT SIGNED IQ SAMPLES")
        table_card.badge.setText("PC INPUT ONLY")
        self.table = QTableWidget(0, 3)
        self.table.setHorizontalHeaderLabels(["Index", "I · signed int16", "Q · signed int16"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.cellChanged.connect(self._cell_changed)
        table_card.body.addWidget(self.table, 1)
        right.addWidget(table_card, 5)
        outer.addLayout(right, 7)
        for widget in (self.kind,):
            widget.currentIndexChanged.connect(self.regenerate)
        for widget in (self.count, self.amplitude, self.frequency, self.sample_rate, self.phase, self.seed,
                       self.constant_i, self.constant_q, self.chirp_end):
            widget.valueChanged.connect(self.regenerate)
        self.regenerate()

    def parameters(self):
        return dict(kind=self.kind.currentData(), count=self.count.value(), amplitude=self.amplitude.value(),
                    frequency=self.frequency.value(), sample_rate=self.sample_rate.value(), phase=math.radians(self.phase.value()),
                    seed=self.seed.value(), constant_i=self.constant_i.value(), constant_q=self.constant_q.value(),
                    chirp_end=self.chirp_end.value())

    def regenerate(self, *_):
        if self._loading:
            return
        try:
            self.samples = generate_iq(**self.parameters())
            self.origin = "Generated on PC"
            self.error.clear()
            self._render()
            self.changed.emit()
        except (ValueError, TypeError) as exc:
            self.samples = []
            self.preview.clear()
            self.table.setRowCount(0)
            self.error.setText(str(exc))
            self.changed.emit()

    def set_samples(self, samples, origin="Imported / edited PC input"):
        samples = [tuple(pair) for pair in samples]
        encode_iq(samples)
        if not 1 <= len(samples) <= 256:
            raise ValueError("IQ input must contain 1..256 samples")
        self.samples = samples
        self.origin = origin
        self._loading = True
        try:
            self.count.setValue(len(samples))
        finally:
            self._loading = False
        self.error.clear()
        self._render()
        self.changed.emit()

    def set_shape(self, count, sample_rate):
        if self.count.value() == count and self.sample_rate.value() == sample_rate:
            return
        self._loading = True
        try:
            self.count.setValue(count)
            self.sample_rate.setValue(sample_rate)
        finally:
            self._loading = False
        self.regenerate()

    def _render(self):
        self.preview.set_samples([p[0] for p in self.samples], [p[1] for p in self.samples],
                                 f"LOCAL PREVIEW · {self.origin} · not FPGA measured")
        self.table.blockSignals(True)
        self.table.setRowCount(len(self.samples))
        for row, pair in enumerate(self.samples):
            for column, value in enumerate((row, *pair)):
                item = QTableWidgetItem(str(value))
                if column == 0:
                    item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                self.table.setItem(row, column, item)
        self.table.blockSignals(False)

    def _cell_changed(self, row, column):
        if column == 0 or row >= len(self.samples):
            return
        try:
            raw = self.table.item(row, column).text().strip()
            number = int(raw)
            if not -32768 <= number <= 32767 or str(number) != raw:
                raise ValueError("Each IQ component must be an integer in −32768…32767")
            pair = list(self.samples[row])
            pair[column - 1] = number
            self.samples[row] = tuple(pair)
            self.origin = "Manually edited PC input"
            self.error.clear()
            self.preview.set_samples([p[0] for p in self.samples], [p[1] for p in self.samples],
                                     "LOCAL PREVIEW · manually edited · not FPGA measured")
            self.changed.emit()
        except ValueError as exc:
            self.error.setText(str(exc))
            self._render()

    def preset(self):
        return {"schema": "DIFI_LOCAL_IQ_PRESET_1", "source": "LOCAL PREVIEW",
                "parameters": self.parameters(), "samples": [list(pair) for pair in self.samples]}

    def load_preset(self, data):
        if data.get("schema") != "DIFI_LOCAL_IQ_PRESET_1":
            raise ValueError("Unsupported IQ preset schema")
        parameters = data.get("parameters", {})
        samples = data.get("samples", [])
        if parameters:
            if not 1 <= parameters.get("count", 0) <= 256 or parameters["count"] != len(samples):
                raise ValueError("Preset sample count must match its 1..256 saved IQ pairs")
            generate_iq(**parameters)
            index = self.kind.findData(parameters["kind"])
            if index < 0:
                raise ValueError("Unsupported preset signal")
            self._loading = True
            try:
                self.kind.setCurrentIndex(index)
                for key in ("count", "amplitude", "frequency", "sample_rate", "seed", "constant_i", "constant_q", "chirp_end"):
                    if key in parameters and parameters[key] is not None:
                        getattr(self, key).setValue(parameters[key])
                self.phase.setValue(math.degrees(parameters.get("phase", 0)))
            finally:
                self._loading = False
        self.set_samples(samples, "Loaded local preset")
