from PySide6.QtWidgets import QHBoxLayout
from .common import Card, counts, divider, metric, number, read
from ..theme import COLORS


class PacketSummary(Card):
    def __init__(self, parent=None):
        super().__init__("PACKET SUMMARY", parent=parent)
        row = QHBoxLayout()
        self.values = {}
        for kind, title in (("VERSION", "Version"), ("CONTEXT", "Context"), ("DATA", "Data")):
            box, value = metric("0", title, COLORS[kind], 30)
            row.addLayout(box, 1)
            self.values[kind] = value
        self.body.addLayout(row)
        self.body.addWidget(divider())
        totals = QHBoxLayout()
        box, self.total = metric("0", "Validated packets", size=21)
        totals.addLayout(box, 1)
        box, self.bytes = metric("0", "UDP payload bytes", size=21)
        totals.addLayout(box, 2)
        self.body.addLayout(totals)
        self.badge.setText("ACTUAL EVENTS")
        self.setToolTip("Only validated packet events contribute to these counters.")

    def update_session(self, session):
        values = counts(session)
        for kind, value in values.items():
            self.values[kind].setText(number(value))
        self.total.setText(number(sum(values.values())))
        self.bytes.setText(number(read(session, "payload_bytes", 0)))
