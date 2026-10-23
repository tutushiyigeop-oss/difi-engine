"""Shared card primitives; widgets accept either dict or dataclass sessions."""
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFrame, QLabel, QHBoxLayout, QVBoxLayout
from ..theme import COLORS


def read(obj, key, default=None):
    return obj.get(key, default) if isinstance(obj, dict) else getattr(obj, key, default)


def enum_text(value):
    return str(getattr(value, "value", value))


def counts(session):
    values = read(session, "counts", {}) or {}
    return {k: int(values.get(k, values.get(k.lower(), 0))) for k in ("VERSION", "CONTEXT", "DATA")}


def number(value):
    return "N/A" if value is None else f"{int(value):,}"


def label(text="", name=None, color=None):
    result = QLabel(text)
    if name:
        result.setObjectName(name)
    if color:
        result.setStyleSheet(f"color: {color};")
    return result


class Card(QFrame):
    def __init__(self, title, subtitle="", parent=None):
        super().__init__(parent)
        self.setObjectName("Card")
        self.body = QVBoxLayout(self)
        self.body.setContentsMargins(14, 9, 14, 9)
        self.body.setSpacing(6)
        self.heading = QHBoxLayout()
        self.title_label = label(title, "CardTitle")
        self.heading.addWidget(self.title_label)
        self.heading.addStretch(1)
        self.badge = label("", "CardSubtitle")
        self.heading.addWidget(self.badge)
        self.body.addLayout(self.heading)
        if subtitle:
            self.subtitle_label = label(subtitle, "CardSubtitle")
            self.subtitle_label.setWordWrap(True)
            self.body.addWidget(self.subtitle_label)


def divider():
    line = QFrame()
    line.setFixedHeight(1)
    line.setStyleSheet(f"background:{COLORS['border']}; border:none;")
    return line


def metric(value="—", title="", color=None, size=26):
    box = QVBoxLayout()
    box.setSpacing(1)
    value_label = label(value, "MetricValue")
    value_label.setStyleSheet(f"font: 600 {size}px Consolas; color: {color or COLORS['text']};")
    box.addWidget(value_label)
    box.addWidget(label(title, "MetricLabel"))
    return box, value_label
