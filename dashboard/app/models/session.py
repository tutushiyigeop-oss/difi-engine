"""Evidence-based session accounting independent of Qt and transport."""

from copy import deepcopy
from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4

from .events import Event, utc_now

PACKET_TYPES = ("VERSION", "CONTEXT", "DATA")
TERMINAL_STATES = {"COMPLETED", "FAILED", "STOPPED"}
ACTIVE_STATES = {"PREPARING", "RUNNING"}


@dataclass
class Session:
    mode: str = "B5"
    source: str = "REPLAY"
    parameters: dict[str, Any] = field(default_factory=dict)
    id: str = field(default_factory=lambda: uuid4().hex)
    state: str = "IDLE"
    events: list[Event] = field(default_factory=list)
    packets: list[dict[str, Any]] = field(default_factory=list)
    counts: dict[str, int] = field(default_factory=lambda: dict.fromkeys(PACKET_TYPES, 0))
    payload_bytes: int = 0
    verified_iq: int = 0
    mismatches: int | None = None
    mismatches_are_minimum: bool = False
    sequence_history: dict[str, list[dict[str, Any]]] = field(
        default_factory=lambda: {kind: [] for kind in PACKET_TYPES})
    sequence_issues: list[dict[str, Any]] = field(default_factory=list)
    board_status: dict[str, Any] = field(default_factory=dict)
    summary_seen: bool = False
    exit_code: int | None = None
    expected_iq: int = field(init=False)
    expected_packets: int = field(init=False)
    expected_counts: dict[str, int] = field(init=False)
    errors: list[str] = field(default_factory=list)
    started_at: str | None = None
    ended_at: str | None = None
    _seen_packet_ids: set[str] = field(default_factory=set, repr=False)

    def __post_init__(self) -> None:
        self.mode = self.mode.upper()
        self.source = self.source.upper()
        self.parameters = deepcopy(self.parameters)
        if self.mode not in {"B5", "B6"}:
            raise ValueError("mode must be B5 or B6")
        if self.source not in {"LIVE", "REPLAY"}:
            raise ValueError("source must be LIVE or REPLAY")
        if self.mode == "B5":
            self.expected_counts = {"VERSION": 1, "CONTEXT": 1, "DATA": 20}
        else:
            selected = self.parameters.get("types", "version,context,data")
            if isinstance(selected, str):
                selected = selected.split(",")
            selected = [str(kind).strip().upper() for kind in selected if str(kind).strip()]
            if not selected or len(set(selected)) != len(selected) or any(
                    kind not in PACKET_TYPES for kind in selected):
                raise ValueError("types must be a unique subset of version,context,data")
            rounds = int(self.parameters.get("rounds", 20))
            if not 1 <= rounds <= 1000:
                raise ValueError("rounds must be 1..1000")
            self.expected_counts = {
                kind: (rounds if kind == "DATA" else 1) if kind in selected else 0
                for kind in PACKET_TYPES}
        self.expected_packets = sum(self.expected_counts.values())
        self.expected_iq = self.expected_counts["DATA"] * 256

    @property
    def total_packets(self) -> int:
        return sum(self.counts.values())

    @property
    def is_active(self) -> bool:
        return self.state in ACTIVE_STATES

    def start(self) -> None:
        if self.state != "IDLE":
            raise RuntimeError("Create a fresh session before starting another run")
        self.started_at = utc_now()
        self.state = "PREPARING"

    def _record_sequence(self, data: dict[str, Any], event: Event, passed: bool) -> None:
        kind = str(data.get("packet_type", "")).upper()
        seq = data.get("sequence")
        if kind not in self.sequence_history or not isinstance(seq, int):
            return
        history = self.sequence_history[kind]
        issue = None
        wrap = False
        if not 0 <= seq <= 15:
            issue = "Sequence is outside the 4-bit range"
        elif history:
            previous = history[-1]["sequence"]
            wrap = previous == 15 and seq == 0
            if seq == previous:
                issue = f"Repeated sequence {seq}"
            elif seq != (previous + 1) % 16:
                issue = f"Discontinuity: expected {(previous + 1) % 16}, received {seq}"
        elif self.mode == "B6":
            key = {"VERSION": "NEXT_VERSION", "CONTEXT": "NEXT_CONTEXT", "DATA": "NEXT_ROUND"}[kind]
            baseline = self.board_status.get(key)
            if isinstance(baseline, int) and seq != baseline % 16:
                issue = f"STATUS expected sequence {baseline % 16}, received {seq}"
        item = {**deepcopy(data), "sequence": seq, "status": "PASS" if passed else "FAIL",
                "wrap": wrap, "issue": issue, "timestamp": event.timestamp, "source": event.source}
        history.append(item)
        if issue:
            self.sequence_issues.append({"packet_type": kind, "sequence": seq,
                                         "packet_id": data.get("packet_id"), "issue": issue})

    def apply(self, event: Event) -> None:
        if event.source.upper() != self.source:
            raise ValueError("Cannot mix Live and Replay evidence in one session")
        if self.state in TERMINAL_STATES:
            return
        self.events.append(event)
        data = event.data
        if event.kind == "SESSION_START":
            if self.state == "IDLE":
                self.started_at = event.timestamp
            self.state = "RUNNING"
        elif event.kind == "BOARD_READY":
            self.board_status.update(deepcopy(data))
            self.state = "RUNNING"
        elif event.kind == "SESSION_COMPLETE":
            self.summary_seen = bool(data.get("summary"))
        elif event.kind == "SESSION_ERROR":
            self.errors.append(str(data.get("message", "Session error")))
        elif event.kind == "PACKET_FAIL":
            self.errors.append(str(data.get("message", "Packet validation failed")))
            known_mismatches = data.get("mismatches")
            if isinstance(known_mismatches, int):
                self.mismatches = max(self.mismatches or 0, known_mismatches)
                self.mismatches_are_minimum = bool(data.get("mismatches_are_minimum", False))
            if str(data.get("packet_type", "")).upper() in self.counts:
                self.packets.append({**deepcopy(data), "timestamp": event.timestamp,
                                     "source": event.source, "status": "FAIL", "verified": False})
            self._record_sequence(data, event, False)
        elif event.kind == "PACKET_PASS":
            packet_id = str(data.get("packet_id", ""))
            kind = str(data.get("packet_type", "")).upper()
            if packet_id in self._seen_packet_ids:
                return
            if not packet_id or kind not in self.counts or data.get("verified") is not True:
                self.errors.append("Rejected packet event without a verified identity and type")
                return
            self._seen_packet_ids.add(packet_id)
            self.state = "RUNNING"
            packet = {**deepcopy(data), "timestamp": event.timestamp,
                      "source": event.source, "status": "PASS"}
            self.packets.append(packet)
            self.counts[kind] += 1
            self.payload_bytes += int(data.get("payload_bytes", 0))
            if kind == "DATA":
                self.verified_iq += int(data.get("iq_samples", 0))
                if self.mismatches is None:
                    self.mismatches = 0
            self._record_sequence(data, event, True)
        elif event.kind == "IQ_VERIFIED" and isinstance(data.get("mismatches"), int):
            # Per-packet verification events are descriptive; PACKET_PASS owns totals.
            self.mismatches = max(self.mismatches or 0, data["mismatches"])

    def finish(self, exit_code: int, stopped: bool = False) -> None:
        if self.state in TERMINAL_STATES:
            return
        self.exit_code = int(exit_code)
        self.ended_at = utc_now()
        if stopped:
            self.state = "STOPPED"
            return
        success = (self.exit_code == 0 and self.summary_seen
                   and self.counts == self.expected_counts
                   and self.verified_iq == self.expected_iq
                   and not self.errors and not self.sequence_issues
                   and (self.mismatches in {None, 0}))
        self.state = "COMPLETED" if success else "FAILED"
        if not success:
            if self.exit_code != 0:
                self.errors.append(f"Process exited with code {self.exit_code}")
            if not self.summary_seen:
                self.errors.append("Verified completion summary was not observed")
            if self.counts != self.expected_counts:
                self.errors.append(f"Confirmed packet counts {self.counts} differ from expected {self.expected_counts}")
            if self.verified_iq != self.expected_iq:
                self.errors.append(f"Verified IQ {self.verified_iq} differs from expected {self.expected_iq}")

    def to_dict(self) -> dict[str, Any]:
        return deepcopy({
            "id": self.id, "mode": self.mode, "source": self.source,
            "parameters": self.parameters, "state": self.state,
            "started_at": self.started_at, "ended_at": self.ended_at,
            "events": [event.to_dict() for event in self.events], "packets": self.packets,
            "counts": self.counts, "total_packets": self.total_packets,
            "payload_bytes": self.payload_bytes, "verified_iq": self.verified_iq,
            "mismatches": self.mismatches, "mismatches_are_minimum": self.mismatches_are_minimum,
            "sequence_history": self.sequence_history,
            "sequence_issues": self.sequence_issues, "board_status": self.board_status,
            "summary_seen": self.summary_seen, "exit_code": self.exit_code,
            "expected_iq": self.expected_iq, "expected_packets": self.expected_packets,
            "expected_counts": self.expected_counts, "errors": self.errors,
        })
