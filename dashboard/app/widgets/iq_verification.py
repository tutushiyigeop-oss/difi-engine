from PySide6.QtWidgets import QHBoxLayout, QProgressBar
from .common import Card, enum_text, label, metric, number, read
from ..theme import COLORS


class IQVerification(Card):
    def __init__(self, parent=None):
        super().__init__("IQ VERIFICATION", parent=parent)
        row = QHBoxLayout()
        self.fields = {}
        for key, title, color in (("expected", "Expected samples", COLORS["muted"]), ("actual", "Verified samples", COLORS["success"]), ("mismatch", "Mismatch count", COLORS["text"])):
            box, value = metric("—", title, color, 24)
            row.addLayout(box, 1)
            self.fields[key] = value
        self.body.addLayout(row)
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.progress.setRange(0, 1000)
        self.progress.setFixedHeight(4)
        self.body.addWidget(self.progress)
        self.provenance = label("Awaiting a verified payload or board ACK", "CardSubtitle")
        self.provenance.setWordWrap(True)
        self.body.addWidget(self.provenance)
        self.badge.setText("AWAITING DATA")

    def update_session(self, session):
        expected = read(session, "expected_iq", 0)
        actual = read(session, "verified_iq", 0)
        mismatch = read(session, "mismatches", None)
        self.fields["expected"].setText(number(expected))
        self.fields["actual"].setText(number(actual))
        self.fields["mismatch"].setText(("≥" if mismatch and read(session, "mismatches_are_minimum", False) else "") + number(mismatch))
        state = enum_text(read(session, "state", "IDLE")).upper()
        if state == "COMPLETED" and expected == 0:
            status, color = "NOT REQUESTED", COLORS["muted"]
        elif mismatch or state == "FAILED":
            status, color = "FAILED", COLORS["error"]
        elif state == "STOPPED":
            status, color = "STOPPED / PARTIAL" if actual else "STOPPED", COLORS["warning"]
        elif state == "COMPLETED" and actual and (not expected or actual >= expected):
            status, color = "VERIFIED", COLORS["success"]
        elif actual:
            status, color = "VERIFYING", COLORS["DATA"]
        else:
            status, color = "AWAITING DATA", COLORS["muted"]
        self.badge.setText(status)
        self.badge.setStyleSheet(f"color:{color}; font-size:10px; font-weight:600;")
        self.progress.setValue(min(1000, round(actual / expected * 1000)) if expected else 0)
        mode = enum_text(read(session, "mode", "B5"))
        source = enum_text(read(session, "source", "LIVE"))
        provenance = "Board ACK: internal Golden comparison; no returned FPGA samples" if "B6" in mode.upper() else "PC verification of received DIFI I16/Q16 payload"
        if state == "COMPLETED" and expected == 0:
            provenance = "Metadata-only session · IQ verification was not requested"
        if "REPLAY" in source.upper():
            provenance = "REPLAY / OFFLINE · " + provenance
        self.provenance.setText(provenance)
