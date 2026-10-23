"""A painted, wrapping packet timeline with O(visible packets) drawing cost."""
import math
from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QScrollArea, QWidget
from .common import Card, enum_text, label, read
from ..theme import COLORS


class _TimelineCanvas(QWidget):
    selected = Signal(object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.items = []
        self.selected_index = -1
        self.columns = 22
        self.setMouseTracking(True)

    def resizeEvent(self, event):
        self.columns = max(1, self.width() // 39)
        self.setMinimumHeight(max(35, math.ceil(len(self.items) / self.columns) * 37))
        super().resizeEvent(event)

    def set_items(self, items):
        self.items = items
        self.selected_index = -1 if self.selected_index >= len(items) else self.selected_index
        self.columns = max(1, self.width() // 39)
        self.setMinimumHeight(max(35, math.ceil(len(items) / self.columns) * 37))
        self.update()

    def _index_at(self, position):
        col = int(position.x()) // 39
        row = int(position.y()) // 37
        index = row * self.columns + col
        return index if col < self.columns and index < len(self.items) else -1

    def mousePressEvent(self, event):
        index = self._index_at(event.position())
        if index >= 0:
            self.selected_index = index
            self.selected.emit(self.items[index])
            self.update()

    def mouseMoveEvent(self, event):
        index = self._index_at(event.position())
        self.setCursor(Qt.CursorShape.PointingHandCursor if index >= 0 else Qt.CursorShape.ArrowCursor)
        if index >= 0:
            item = self.items[index]
            self.setToolTip(f"{item['packet_type']} · " + ("Expected target, no event yet" if item.get("expected") else f"Sequence {item.get('sequence', 'N/A')} · {item.get('status', 'PASS')}"))

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setFont(QFont("Consolas", 9))
        first = max(0, event.rect().top() // 37 * self.columns)
        last = min(len(self.items), (event.rect().bottom() // 37 + 1) * self.columns)
        for index in range(first, last):
            item = self.items[index]
            kind = str(item.get("packet_type", "DATA")).upper()
            expected = item.get("expected", False)
            bad = str(item.get("status", "PASS")).upper() in {"FAIL", "FAILED", "ERROR"} or item.get("verified") is False
            color = QColor(COLORS["error"] if bad else COLORS.get(kind, COLORS["DATA"]))
            rect = QRectF((index % self.columns) * 39 + 1, (index // self.columns) * 37 + 1, 32, 27)
            fill = QColor(color)
            fill.setAlpha(10 if expected else 36)
            p.setBrush(fill)
            border = QColor("#2a3e54") if expected else color
            p.setPen(QPen(border, 2 if index == self.selected_index else 1))
            p.drawRoundedRect(rect, 4, 4)
            p.setPen(QColor("#50647c") if expected else color)
            text = "V" if kind == "VERSION" else "C" if kind == "CONTEXT" else str(item.get("data_index", "D"))
            p.drawText(rect, Qt.AlignmentFlag.AlignCenter, text)
            if expected:
                p.setPen(QPen(QColor("#33495f"), 1, Qt.PenStyle.DotLine))
                p.drawLine(rect.bottomLeft(), rect.bottomRight())


class PacketTimeline(Card):
    def __init__(self, parent=None):
        super().__init__("PACKET TIMELINE", parent=parent)
        self.setMaximumHeight(110)
        self.badge.setText("EVENT ORDER · CLICK TO INSPECT")
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.scroll.setMinimumHeight(38)
        self.scroll.setMaximumHeight(70)
        self.canvas = _TimelineCanvas()
        self.scroll.setWidget(self.canvas)
        self.body.addWidget(self.scroll, 1)
        self.detail = label("Outlined cells are expected targets; colored cells are actual packet events.", "CardSubtitle")
        self.detail.setWordWrap(True)
        self.body.addWidget(self.detail)
        self.canvas.selected.connect(self._show_detail)
        self._last_length = 0

    def update_session(self, session):
        packets = read(session, "packets", []) or []
        # Confirmed packets own the counters. Support both retained failures and
        # older sessions that stored failed arrivals only in the event history.
        retained_failures = any(str(read(packet, "status", "PASS")).upper() in {"FAIL", "FAILED", "ERROR"} for packet in packets)
        packets_by_id = {read(packet, "packet_id"): packet for packet in packets}
        visual_packets = list(packets) if retained_failures else []
        seen = set()
        for event in ([] if retained_failures else read(session, "events", []) or []):
            kind = enum_text(read(event, "kind", ""))
            data = read(event, "data", {}) or {}
            packet_id = read(data, "packet_id")
            if kind == "PACKET_PASS" and packet_id in packets_by_id and packet_id not in seen:
                visual_packets.append(packets_by_id[packet_id])
                seen.add(packet_id)
            elif kind == "PACKET_FAIL":
                visual_packets.append({**data, "timestamp": read(event, "timestamp", "N/A"), "status": "FAIL", "verified": False})
        if not retained_failures:
            visual_packets.extend(packet for packet in packets if read(packet, "packet_id") not in seen)
        items = []
        data_index = 0
        for packet in visual_packets:
            item = dict(packet) if isinstance(packet, dict) else vars(packet).copy()
            item["packet_type"] = enum_text(item.get("packet_type", "DATA")).upper()
            if item["packet_type"] == "DATA":
                item["data_index"] = data_index
                data_index += 1
            items.append(item)
        expected = read(session, "expected_counts", None)
        if expected is None:
            expected = {"VERSION": 1, "CONTEXT": 1, "DATA": max(0, int(read(session, "expected_iq", 5120) or 0) // 256)}
        observed = {kind: sum(item["packet_type"] == kind for item in items) for kind in ("VERSION", "CONTEXT", "DATA")}
        for kind in ("VERSION", "CONTEXT", "DATA"):
            count = max(0, int(expected.get(kind, expected.get(kind.lower(), 0))) - observed[kind])
            for _ in range(count):
                item = {"packet_type": kind, "expected": True}
                if kind == "DATA":
                    item["data_index"] = data_index
                    data_index += 1
                items.append(item)
        self.canvas.set_items(items)
        self.badge.setText(f"{len(visual_packets):,} EVENTS / {sum(int(v) for v in expected.values()):,} TARGET")
        if not visual_packets:
            self.detail.setText("Outlined cells are expected targets; no packet has been validated yet.")
        if len(visual_packets) != self._last_length and visual_packets:
            self._show_detail(items[len(visual_packets) - 1])
        self._last_length = len(visual_packets)

    def _show_detail(self, item):
        kind = item.get("packet_type", "DATA")
        if item.get("expected"):
            self.detail.setText(f"{kind} · Expected target · no arrival or board ACK observed")
            return
        self.detail.setText(f"{kind}  ·  Seq {item.get('sequence', 'N/A')}  ·  {item.get('payload_bytes', 'N/A')} B  ·  {item.get('status', 'PASS')}  ·  {item.get('timestamp', 'N/A')}")
