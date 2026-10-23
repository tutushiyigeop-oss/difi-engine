"""An event-driven, single-direction view of the two supported board images."""
import math
import time
from PySide6.QtCore import QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QWidget
from .common import Card, enum_text, label
from ..theme import COLORS


class _TopologyCanvas(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.mode = "B5"
        self.pulses = []
        self.timer = QTimer(self)
        self.timer.setInterval(33)
        self.timer.timeout.connect(self._tick)
        self.setMinimumHeight(170)
        self.setToolTip("Animation is triggered only by a validated packet event. The topology follows the selected board image.")

    def _tick(self):
        now = time.monotonic()
        self.pulses = [(kind, start) for kind, start in self.pulses if now - start < 1.65]
        if not self.pulses:
            self.timer.stop()
        self.update()

    def pulse(self, kind):
        if not self.isVisible():
            return
        self.pulses.append((kind.upper(), time.monotonic()))
        self.pulses = self.pulses[-10:]
        self.timer.start()
        self.update()

    def hideEvent(self, event):
        self.timer.stop()
        self.pulses.clear()
        super().hideEvent(event)

    def _geometry(self):
        if self.mode == "B5":
            nodes = [
                ("IQ SOURCE", "I16 / Q16", 112, 33, "source"),
                ("AXI DMA", "MM2S", 328, 33, "dma"),
                ("PL DIFI TX", "Encapsulation", 328, 101, "pl"),
                ("AXI DMA", "S2MM", 112, 101, "dma"),
                ("PS DDR / lwIP", "Packet buffer", 112, 169, "ps"),
                ("UDP", "Ethernet · 4991", 328, 169, "network"),
                ("PC RECEIVER", "Payload verification", 328, 237, "pc"),
            ]
            return nodes, [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)]
        nodes = [
            ("PC SENDER", "DIFI packets", 112, 26, "pc"),
            ("UDP", "Ethernet · 4991", 328, 26, "network"),
            ("PS GEM0", "lwIP receive / buffer", 328, 82, "ps"),
            ("DDR", "Packet staging", 112, 82, "ps"),
            ("AXI DMA", "MM2S", 112, 138, "dma"),
            ("PL DIFI RX", "Parse + validate", 328, 138, "pl"),
            ("IQ OUTPUT", "DATA only", 74, 210, "data"),
            ("AXI DMA", "S2MM", 220, 210, "data"),
            ("PS GOLDEN", "IQ verification", 366, 210, "data"),
            ("METADATA", "Version / Context", 74, 271, "meta"),
            ("AXI GPIO", "Board reads GPIO", 220, 271, "meta"),
            ("PS", "Metadata check", 366, 271, "meta"),
        ]
        return nodes, [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (6, 7), (7, 8), (9, 10), (10, 11)]

    @staticmethod
    def _point_on(points, progress):
        lengths = [math.hypot(b.x() - a.x(), b.y() - a.y()) for a, b in zip(points, points[1:])]
        remaining = progress * sum(lengths)
        for a, b, length in zip(points, points[1:], lengths):
            if remaining <= length:
                t = remaining / length if length else 0
                return QPointF(a.x() + (b.x() - a.x()) * t, a.y() + (b.y() - a.y()) * t)
            remaining -= length
        return points[-1]

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        logical_height = 274 if self.mode == "B5" else 300
        scale = min(self.width() / 440, self.height() / logical_height)
        p.translate((self.width() - 440 * scale) / 2, (self.height() - logical_height * scale) / 2)
        p.scale(scale, scale)
        nodes, links = self._geometry()
        centers = [QPointF(n[2], n[3]) for n in nodes]
        # A restrained alignment grid makes the panel read like a real instrument.
        p.setPen(QPen(QColor("#192b40"), .7))
        for x in range(4, 441, 22):
            for y in range(4, logical_height, 22):
                p.drawPoint(QPointF(x, y))
        p.setPen(QPen(QColor("#395a73"), 1.4))
        for start, end in links:
            a, b = centers[start], centers[end]
            p.drawLine(a, b)
            delta = b - a
            length = math.hypot(delta.x(), delta.y())
            if length:
                ux, uy = delta.x() / length, delta.y() / length
                tip = QPointF((a.x() + b.x()) / 2 + ux * 3, (a.y() + b.y()) / 2 + uy * 3)
                p.drawLine(tip, QPointF(tip.x() - ux * 5 - uy * 3, tip.y() - uy * 5 + ux * 3))
                p.drawLine(tip, QPointF(tip.x() - ux * 5 + uy * 3, tip.y() - uy * 5 - ux * 3))
        if self.mode == "B6":
            for y, kind in ((210, "DATA"), (271, "CONTEXT")):
                branch = QPainterPath(QPointF(328, 157))
                branch.lineTo(328, 174)
                branch.lineTo(16, 174)
                branch.lineTo(16, y)
                branch.lineTo(22, y)
                color = QColor(COLORS[kind])
                color.setAlpha(105)
                p.setPen(QPen(color, 1.3))
                p.drawPath(branch)
        for index, (title, subtitle, x, y, kind) in enumerate(nodes):
            width = 132 if index < 6 or self.mode == "B5" else 108
            rect = QRectF(x - width / 2, y - 22, width, 44)
            accent = COLORS["DATA"] if kind in {"pl", "pc", "data"} else COLORS["CONTEXT"] if kind == "meta" else "#6a8ca8"
            p.setPen(QPen(QColor(accent if kind == "pl" else "#304b66"), 1.2))
            p.setBrush(QColor("#16364a" if kind == "pl" else "#142437"))
            p.drawRoundedRect(rect, 6, 6)
            p.fillRect(QRectF(rect.x() + 1, rect.y() + 10, 2, 18), QColor(accent))
            # Keep labels legible when the overall diagram shrinks to a compact
            # 1080p panel: draw text in canvas pixels, rather than scaling fonts.
            p.save()
            p.translate(x, y)
            p.scale(1 / scale, 1 / scale)
            p.setPen(QColor("#dfecf8"))
            font = QFont("Segoe UI")
            font.setPixelSize(11)
            font.setWeight(QFont.Weight.DemiBold)
            p.setFont(font)
            p.drawText(QRectF(-width * scale / 2, -13, width * scale, 14), Qt.AlignmentFlag.AlignCenter, title)
            font.setPixelSize(8)
            font.setWeight(QFont.Weight.Normal)
            p.setFont(font)
            p.setPen(QColor("#86a2bc"))
            p.drawText(QRectF(-width * scale / 2, 1, width * scale, 10), Qt.AlignmentFlag.AlignCenter, subtitle)
            p.restore()
        # These are visual confirmations, never a second source of packet statistics.
        now = time.monotonic()
        for kind, start in self.pulses:
            progress = min(1, (now - start) / 1.65)
            points = centers[:7] if self.mode == "B5" else centers[:6] + [QPointF(328, 174), QPointF(16, 174), QPointF(16, 210 if kind == "DATA" else 271)] + centers[6:9 if kind == "DATA" else 6]
            if self.mode == "B6" and kind != "DATA":
                points += centers[9:12]
            point = self._point_on(points, progress)
            color = QColor(COLORS.get(kind, COLORS["DATA"]))
            glow = QColor(color)
            glow.setAlpha(30)
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(glow)
            p.drawEllipse(point, 9, 9)
            p.setBrush(color)
            p.drawEllipse(point, 3.4, 3.4)


class TopologyWidget(Card):
    def __init__(self, parent=None):
        super().__init__("SYSTEM TOPOLOGY", parent=parent)
        self.canvas = _TopologyCanvas()
        self.body.addWidget(self.canvas, 1)
        self.caption = label("B5 · FPGA / PS → PC receiver", "CardSubtitle")
        self.body.addWidget(self.caption)
        self.badge.setText("IDLE")
        self.setMinimumHeight(240)

    def set_mode(self, mode):
        mode = "B6" if "B6" in enum_text(mode).upper() else "B5"
        if self.canvas.mode == mode:
            return
        self.canvas.mode = mode
        self.canvas.pulses.clear()
        self.canvas.timer.stop()
        self.caption.setText("B6 · PC → FPGA · separate IQ and metadata paths" if self.canvas.mode == "B6" else "B5 · FPGA / PS → PC receiver")
        self.canvas.update()

    def set_status(self, status):
        text = enum_text(status).upper()
        self.badge.setText(text.replace("_", " "))
        color = COLORS["success"] if text == "COMPLETED" else COLORS["error"] if text in {"FAILED", "ERROR"} else COLORS["DATA"] if text == "RUNNING" else COLORS["muted"]
        self.badge.setStyleSheet(f"color:{color}; font-size:10px;")
        if text in {"FAILED", "ERROR", "STOPPED", "IDLE"}:
            self.canvas.pulses.clear()
            self.canvas.timer.stop()
            self.canvas.update()

    def pulse(self, packet_type):
        self.canvas.pulse(enum_text(packet_type))
