from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QComboBox, QWidget
from .common import Card, label, read
from ..theme import COLORS


class _SequenceStrip(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.entries = []
        self.kind = "DATA"
        self.setMinimumHeight(35)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        width = (self.width() - 15 * 3) / 16
        p.setFont(QFont("Consolas", 9))
        for index in range(16):
            rect = QRectF(index * (width + 3), 1, width, 27)
            entry = self.entries[index] if index < len(self.entries) else None
            issue = read(entry, "issue", None) if entry else None
            failed = str(read(entry, "status", "PASS")).upper() in {"FAIL", "FAILED", "ERROR"} if entry else False
            wrap = bool(read(entry, "wrap", False)) if entry else False
            color = COLORS["error"] if issue or failed else COLORS["success"] if wrap else COLORS[self.kind]
            p.setBrush(QColor("#1a2c40" if entry else "#0c1828"))
            p.setPen(QPen(QColor(color if entry else COLORS["border"]), 1.2 if wrap else 1))
            p.drawRoundedRect(rect, 4, 4)
            p.setPen(QColor(color if entry else "#3e536b"))
            p.drawText(rect, Qt.AlignmentFlag.AlignCenter, str(read(entry, "sequence", "—")) if entry else "·")
            if wrap:
                p.setPen(QColor(COLORS["success"]))
                p.drawText(QRectF(rect.x(), 27, width, 10), Qt.AlignmentFlag.AlignCenter, "↻")


class SequenceMonitor(Card):
    def __init__(self, parent=None):
        super().__init__("SEQUENCE MONITOR", parent=parent)
        self.selector = QComboBox()
        self.selector.addItems(["DATA", "VERSION", "CONTEXT"])
        self.selector.setFixedWidth(102)
        self.selector.setFixedHeight(24)
        self.heading.insertWidget(1, self.selector)
        self.strip = _SequenceStrip()
        self.body.addWidget(self.strip)
        self.detail = label("4-bit sequence · independent streams · last 16 events", "CardSubtitle")
        self.detail.setWordWrap(True)
        self.body.addWidget(self.detail)
        self.session = None
        self.selector.currentTextChanged.connect(self._refresh)
        self.badge.setText("CURRENT —")

    def update_session(self, session):
        self.session = session
        self._refresh()

    def _refresh(self, *_):
        kind = self.selector.currentText()
        history = read(self.session, "sequence_history", {}) or {}
        entries = history.get(kind, history.get(kind.lower(), []))
        self.strip.entries = entries[-16:]
        self.strip.kind = kind
        self.strip.update()
        current = read(entries[-1], "sequence", "—") if entries else "—"
        self.badge.setText(f"CURRENT {current}")
        issues = [read(e, "issue", "") for e in entries if read(e, "issue", "")]
        wraps = sum(bool(read(e, "wrap", False)) for e in entries)
        if issues:
            self.detail.setText(f"{len(issues)} sequence issue(s) · {issues[-1]}")
            self.detail.setStyleSheet(f"color:{COLORS['error']}; font-size:10px;")
        elif entries:
            self.detail.setText(f"{len(entries)} observed · {wraps} wrap(s) 15 → 0 · independent {kind.lower()} stream")
            self.detail.setStyleSheet(f"color:{COLORS['muted']}; font-size:10px;")
        else:
            self.detail.setText("4-bit sequence · independent streams · last 16 events")
            self.detail.setStyleSheet(f"color:{COLORS['muted']}; font-size:10px;")
