"""Reference/received comparison. Actual traces require returned byte evidence."""
from __future__ import annotations

import time

import pyqtgraph as pg
from PySide6.QtCore import QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QComboBox, QHeaderView, QLabel, QSplitter, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget

from ..theme import COLORS
from ..widgets.common import Card, label
from ..widgets.iq_waveform import IQWaveform
from .iq import compare_iq
from .profile import decode_iq, encode_iq, parse_packet


class _StageCanvas(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.direction = "TX"
        self.state = "DISCONNECTED"
        self.packet_type = "DATA"
        self.started = None
        self.timer = QTimer(self)
        self.timer.setInterval(33)
        self.timer.timeout.connect(self._tick)
        self.setMinimumHeight(155)

    def _tick(self):
        if self.started is None or time.monotonic() - self.started > 1.2:
            self.timer.stop()
            self.started = None
        self.update()

    def pulse(self):
        if self.isVisible():
            self.started = time.monotonic()
            self.timer.start()

    def hideEvent(self, event):
        self.timer.stop()
        self.started = None
        super().hideEvent(event)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        scale = min(self.width() / 700, self.height() / 160)
        painter.translate((self.width() - 700 * scale) / 2, (self.height() - 160 * scale) / 2)
        painter.scale(scale, scale)
        tx = self.direction == "TX"
        titles = [("PC IQ", "User input"), ("PS / UDP", "DDR staging"), ("DMA1 MM2S", "IQ → AXIS"),
                  ("PL DIFI TX", "Packetizer"), ("DMA1 S2MM", "Real packet"), ("PC CAPTURE", "DIFI payload")] if tx else [
                  ("PC DIFI", "Validated packet"), ("PS / UDP", "DDR staging"), ("DMA0 MM2S", "Packet → AXIS"),
                  ("PL DIFI RX", "Parser"), ("DMA0 S2MM", "Real IQ"), ("PC IQ", "Actual returned words")]
        if not tx and self.packet_type != "DATA":
            titles[0] = ("PC " + self.packet_type, "Validated metadata")
            titles[4:] = [("META MONITOR", "PL handshake"), ("AXI GPIO / PS", "Metadata verification")]
        centers = [QPointF(64 + (i % 3) * 274, 35 if i < 3 else 114) for i in range(6)]
        centers[3:] = list(reversed(centers[3:]))
        accent = QColor(COLORS["DATA"] if tx else COLORS["VERSION"])
        painter.setPen(QPen(QColor("#395a73"), 1.5))
        for start, end in zip(centers, centers[1:]):
            painter.drawLine(start, end)
        for index, (title, subtitle) in enumerate(titles):
            center = centers[index]
            box = QRectF(center.x() - 60, center.y() - 20, 120, 40)
            painter.setBrush(QColor("#16364a" if index == 3 else "#142437"))
            painter.setPen(QPen(accent if index == 3 else QColor("#304b66"), 1.2))
            painter.drawRoundedRect(box, 5, 5)
            font = QFont("Segoe UI")
            font.setPixelSize(11)
            font.setWeight(QFont.Weight.DemiBold)
            painter.setFont(font)
            painter.setPen(QColor("#dceafa"))
            painter.drawText(QRectF(box.x(), box.y() + 4, box.width(), 16), Qt.AlignmentFlag.AlignCenter, title)
            font.setPixelSize(9)
            font.setWeight(QFont.Weight.Normal)
            painter.setFont(font)
            painter.setPen(QColor("#86a2bc"))
            painter.drawText(QRectF(box.x(), box.y() + 23, box.width(), 13), Qt.AlignmentFlag.AlignCenter, subtitle)
        if self.started is not None:
            progress = min(0.999, (time.monotonic() - self.started) / 1.2) * 5
            section = int(progress)
            a, b = centers[section:section + 2]
            position = a + (b - a) * (progress - section)
            painter.setBrush(accent)
            painter.setPen(Qt.PenStyle.NoPen)
            painter.drawEllipse(position, 3.5, 3.5)


class ExperimentTopology(Card):
    def __init__(self, parent=None):
        super().__init__("STAGE D · SINGLE BITSTREAM / HALF DUPLEX", parent=parent)
        self.canvas = _StageCanvas()
        self.body.addWidget(self.canvas, 1)
        self.caption = label("One active direction. Metadata uses the RX monitor / GPIO path; no IQ S2MM is expected for metadata.", "CardSubtitle")
        self.caption.setWordWrap(True)
        self.body.addWidget(self.caption)

    def update_state(self, state, direction="TX"):
        self.canvas.state = state
        if state in {"RX_ACTIVE", "TX_ACTIVE"}:
            self.canvas.direction = state[:2]
            if state == "TX_ACTIVE":
                self.canvas.packet_type = "DATA"
        elif self.canvas.started is None:
            self.canvas.direction = direction
        self.badge.setText(state)
        self.canvas.update()

    def pulse(self, direction, packet_type="DATA"):
        self.canvas.direction = direction
        self.canvas.packet_type = packet_type
        self.canvas.pulse()


class ComparisonWaveform(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.reference = []
        self.records = []
        self.session_id = ""
        self.archived = False
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        self.selector = QComboBox()
        for title, key in (("LOCAL PREVIEW · current PC input", "LOCAL"),
                           ("FPGA TX CAPTURE · latest returned Data", "TX"),
                           ("FPGA RX S2MM · latest returned IQ", "RX"),
                           ("Overlay · TX reference / actual", "OVERLAY_TX"),
                           ("Overlay · RX reference / actual", "OVERLAY_RX")):
            self.selector.addItem(title, key)
        outer.addWidget(self.selector)
        self.legend = label("Solid cyan / amber: returned I / Q · dashed gray / rose: reference I / Q in overlay mode.", "CardSubtitle")
        self.legend.setWordWrap(True)
        outer.addWidget(self.legend)
        split = QSplitter(Qt.Orientation.Vertical)
        self.waveform = IQWaveform()
        self.waveform.setMinimumHeight(230)
        self.reference_i = self.waveform.plot.plot([], [], pen=pg.mkPen("#a0aebd", width=1.5, style=Qt.PenStyle.DashLine))
        self.reference_q = self.waveform.plot.plot([], [], pen=pg.mkPen("#c78aa7", width=1.5, style=Qt.PenStyle.DashLine))
        self.waveform.i_toggle.toggled.connect(lambda value: self.reference_i.setVisible(value))
        self.waveform.q_toggle.toggled.connect(lambda value: self.reference_q.setVisible(value))
        split.addWidget(self.waveform)
        error_card = Card("EXACT SAMPLE COMPARISON", "Δ = actual − reference; units are signed integer codes")
        self.metrics = QLabel("No actual FPGA samples available")
        self.metrics.setWordWrap(True)
        self.metrics.setStyleSheet("font:13px Consolas; color:#a8bdd3;")
        error_card.body.addWidget(self.metrics)
        self.error_plot = pg.PlotWidget(background="#0b1727")
        self.error_plot.setMinimumHeight(95)
        self.error_plot.setLabel("left", "Error / codes")
        self.error_plot.setLabel("bottom", "Sample index")
        self.error_plot.showGrid(x=True, y=True, alpha=.15)
        self.error_i = self.error_plot.plot([], [], pen=pg.mkPen(COLORS["DATA"], width=1.2))
        self.error_q = self.error_plot.plot([], [], pen=pg.mkPen(COLORS["CONTEXT"], width=1.2))
        error_card.body.addWidget(self.error_plot, 1)
        self.table = QTableWidget(0, 8)
        self.table.setHorizontalHeaderLabels(["Index", "Ref I", "Ref Q", "Actual I", "Actual Q", "Δ I", "Δ Q", "Result"])
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        error_card.body.addWidget(self.table, 2)
        split.addWidget(error_card)
        split.setSizes([280, 360])
        outer.addWidget(split, 1)
        self.selector.currentIndexChanged.connect(self.refresh)

    def set_reference(self, samples):
        self.reference = [tuple(pair) for pair in samples]
        self.refresh()

    def set_records(self, records, session_id, archived=False):
        self.records = list(records)
        self.session_id = session_id
        self.archived = archived
        self.refresh()

    def _evidence(self, record):
        """Reject a label if its actual sample array has no matching byte evidence."""
        actual = [tuple(pair) for pair in record.get("actual_iq", [])]
        if record.get("direction") == "TX":
            packets = [packet for packet in record.get("packets", [])
                       if parse_packet(bytes.fromhex(packet["raw"]) if isinstance(packet["raw"], str) else packet["raw"])["packet_type"] == "DATA"]
            if len(packets) != 1:
                return []
            raw = packets[0]["raw"]
            parsed = parse_packet(bytes.fromhex(raw) if isinstance(raw, str) else raw)
            if [tuple(pair) for pair in parsed["iq"]] != actual:
                return []
        elif record.get("direction") == "RX":
            raw = record.get("actual_iq_hex")
            if raw is None:
                return []
            if isinstance(raw, str):
                raw = bytes.fromhex(raw)
            if decode_iq(raw) != actual:
                return []
        else:
            return []
        return actual

    def refresh(self, *_):
        key = self.selector.currentData()
        self.reference_i.setData([], [])
        self.reference_q.setData([], [])
        self.error_i.setData([], [])
        self.error_q.setData([], [])
        self.table.setRowCount(0)
        if key == "LOCAL":
            if self.reference:
                self.waveform.set_samples([p[0] for p in self.reference], [p[1] for p in self.reference],
                                          "LOCAL PREVIEW · current PC input · not FPGA measured")
            else:
                self.waveform.clear()
            self.metrics.setText("LOCAL PREVIEW · no hardware comparison")
            return
        direction = "TX" if key.endswith("TX") else "RX"
        records = [item for item in self.records if item.get("direction") == direction and item.get("actual_iq")]
        if not records:
            self.waveform.clear()
            self.metrics.setText(f"Waiting for actual {direction} returned samples; no measurement has been received.")
            return
        record = records[-1]
        try:
            actual = self._evidence(record)
        except (ValueError, TypeError, KeyError):
            actual = []
        if not actual:
            self.waveform.clear()
            self.metrics.setText("Raw byte evidence is missing or inconsistent; actual trace rejected.")
            return
        reference = [tuple(pair) for pair in record.get("reference_iq", [])]
        source = record.get("source", "UNKNOWN")
        provenance = "FPGA TX CAPTURE" if direction == "TX" else "FPGA RX S2MM"
        if source == "REPLAY" or record.get("fixture"):
            provenance = "REPLAY / OFFLINE · SIMULATED " + provenance
        elif source != "LIVE":
            provenance = "ARCHIVED / UNKNOWN ORIGIN · " + provenance
        if self.archived:
            provenance = "OFFLINE ARCHIVE · recorded " + source + " · " + provenance
        self.waveform.set_samples([p[0] for p in actual], [p[1] for p in actual],
                                  f"{provenance} · Session {self.session_id[:8]} · Round {record.get('round', record.get('transaction', 'N/A'))}")
        if key.startswith("OVERLAY") and reference:
            self.reference_i.setData(list(range(len(reference))), [p[0] for p in reference])
            self.reference_q.setData(list(range(len(reference))), [p[1] for p in reference])
        result = compare_iq(reference, actual)
        self.metrics.setText(f"{source}  ·  {result['actual_samples']}/{result['expected_samples']} IQ  ·  "
                             f"Mismatch {result['mismatches']}  ·  First {result['first_mismatch'] if result['first_mismatch'] is not None else '—'}  ·  Max |Δ| {result['max_abs_error']}")
        self.metrics.setStyleSheet(f"font:13px Consolas; color:{COLORS['success'] if result['exact'] else COLORS['error']};")
        self.error_i.setData(list(range(len(result["error_i"]))), result["error_i"])
        self.error_q.setData(list(range(len(result["error_q"]))), result["error_q"])
        self.table.setRowCount(max(len(reference), len(actual)))
        for row in range(self.table.rowCount()):
            expected = reference[row] if row < len(reference) else (None, None)
            got = actual[row] if row < len(actual) else (None, None)
            bad = expected != got
            errors = tuple(got[i] - expected[i] if got[i] is not None and expected[i] is not None else None for i in (0, 1))
            for col, value in enumerate((row, *expected, *got, *errors, "FAIL" if bad else "PASS")):
                item = QTableWidgetItem("N/A" if value is None else str(value))
                if bad:
                    item.setForeground(QColor(COLORS["error"]))
                self.table.setItem(row, col, item)
