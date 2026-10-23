from PySide6.QtWidgets import QGridLayout
from .common import Card, counts, enum_text, label, read
from ..theme import COLORS


class MetadataMonitor(Card):
    def __init__(self, parent=None):
        super().__init__("METADATA MONITOR", parent=parent)
        grid = QGridLayout()
        grid.setHorizontalSpacing(18)
        grid.setVerticalSpacing(4)
        self.fields = {}
        for row, (key, title) in enumerate((("version", "Version validated"), ("context", "Context validated"), ("status", "Board STATUS"), ("gpio", "PL GPIO / changed flag"))):
            grid.addWidget(label(title, "CardSubtitle"), row, 0)
            value = label("N/A")
            value.setStyleSheet("font:11px Consolas; color:#becfe1;")
            value.setWordWrap(True)
            grid.addWidget(value, row, 1)
            self.fields[key] = value
        grid.setColumnStretch(1, 1)
        self.body.addLayout(grid)
        self.badge.setText("OBSERVABLE EVENTS")

    def update_session(self, session):
        counter = counts(session)
        history = read(session, "sequence_history", {}) or {}
        events = read(session, "events", []) or []
        failure_total = 0
        for key in ("version", "context"):
            kind = key.upper()
            count = counter[key.upper()]
            observed = [event for event in events if enum_text(read(event, "kind", "")) in {"PACKET_PASS", "PACKET_FAIL"} and str(read(read(event, "data", {}), "packet_type", "")).upper() == kind]
            failures = sum(enum_text(read(event, "kind", "")) == "PACKET_FAIL" for event in observed)
            latest = read(observed[-1], "data", {}) if observed else None
            if observed:
                last_status = "FAIL" if enum_text(read(observed[-1], "kind", "")) == "PACKET_FAIL" else "PASS"
            else:
                entries = history.get(kind, history.get(key, []))
                latest = entries[-1] if entries else None
                failures = sum(str(read(item, "status", "")).upper() == "FAIL" for item in entries)
                last_status = str(read(latest, "status", "PASS")) if latest else ""
            failure_total += failures
            text = f"{count:,} confirmed" if count or latest is not None else "— awaiting event"
            if latest is not None:
                text += f" · seq {read(latest, 'sequence', 'N/A')} · {last_status}"
            if failures:
                text += f" · {failures} fail event(s)"
            self.fields[key].setText(text)
            self.fields[key].setStyleSheet(f"font:11px Consolas; color:{COLORS['error'] if failures else COLORS[kind]};")
        if failure_total:
            self.badge.setText(f"{failure_total} FAIL EVENT(S)")
            self.badge.setStyleSheet(f"color:{COLORS['error']}; font-size:10px;")
        else:
            self.badge.setText("0 FAIL EVENTS" if counter["VERSION"] or counter["CONTEXT"] else "AWAITING EVENTS")
            self.badge.setStyleSheet(f"color:{COLORS['muted']}; font-size:10px;")
        status = read(session, "board_status", {}) or {}
        if status:
            fields = []
            for key, value in status.items():
                if key.upper() in {"NEXT_ROUND", "NEXT_VERSION", "NEXT_CONTEXT", "ROUND", "VERSION", "CONTEXT", "READY"}:
                    fields.append(f"{key}={value}")
            self.fields["status"].setText(" · ".join(fields) or str(status))
        else:
            self.fields["status"].setText("N/A · no board STATUS observed")
        gpio = status.get("gpio_errors", status.get("GPIO_ERRORS")) if isinstance(status, dict) else None
        changed = status.get("changed_flag", status.get("CHANGED_FLAG")) if isinstance(status, dict) else None
        self.fields["gpio"].setText(f"errors={gpio if gpio is not None else 'N/A'} / changed={changed if changed is not None else 'N/A'}" if gpio is not None or changed is not None else "Not observable from UDP ACK")
