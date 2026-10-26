"""Pure experiment evidence records with explicit provenance and lifecycle."""

from copy import deepcopy
from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4

from dashboard.app.models.events import Event, utc_now

STATES = {"DISCONNECTED", "CONNECTING", "CONNECTED", "CONFIGURING", "READY",
          "RUNNING", "COMPLETED", "FAILED", "STOPPING", "STOPPED"}


def _json_value(value: Any) -> Any:
    if isinstance(value, (bytes, bytearray, memoryview)):
        return bytes(value).hex()
    if isinstance(value, Event):
        return _json_value(value.to_dict())
    if isinstance(value, dict):
        return {str(key): _json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    return deepcopy(value)


@dataclass
class ExperimentSession:
    source: str = "REPLAY"
    parameters: dict[str, Any] = field(default_factory=dict)
    id: str = field(default_factory=lambda: uuid4().hex)
    state: str = "DISCONNECTED"
    events: list[Event] = field(default_factory=list)
    transactions: list[dict[str, Any]] = field(default_factory=list)
    captures: list[dict[str, Any]] = field(default_factory=list)
    capabilities: dict[str, Any] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    started_at: str | None = None
    ended_at: str | None = None

    def __post_init__(self) -> None:
        self.source = self.source.upper()
        if self.source not in {"LIVE", "REPLAY"}:
            raise ValueError("Experiment source must be LIVE or REPLAY")
        if self.state not in STATES:
            raise ValueError(f"Unknown experiment state: {self.state}")
        self.parameters = deepcopy(self.parameters)

    def _check_source(self, record: Any) -> None:
        if isinstance(record, dict):
            if "source" in record:
                origin = str(record["source"]).upper()
                if origin in {"LIVE", "REPLAY"} and origin != self.source:
                    raise ValueError("Cannot mix Live and Replay experiment evidence")
                if self.source == "LIVE" and (origin.startswith("REPLAY") or "FIXTURE" in origin or "SIMULATED" in origin):
                    raise ValueError("Synthetic fixture evidence cannot be labeled Live")
            if self.source == "LIVE" and (record.get("fixture") or record.get("synthetic") or record.get("simulated")):
                raise ValueError("Synthetic fixture evidence cannot be labeled Live")
            for value in record.values():
                self._check_source(value)
        elif isinstance(record, (list, tuple)):
            for value in record:
                self._check_source(value)

    def transition(self, state: str) -> None:
        if state not in STATES:
            raise ValueError(f"Unknown experiment state: {state}")
        if state == "RUNNING" and self.state == "RUNNING":
            raise RuntimeError("An experiment transaction is already running")
        self.state = state
        if state == "RUNNING" and self.started_at is None:
            self.started_at = utc_now()
        if state in {"COMPLETED", "FAILED", "STOPPED", "DISCONNECTED"} and self.started_at:
            self.ended_at = utc_now()

    def record_transaction(self, transaction: dict[str, Any]) -> None:
        self._check_source(transaction)
        entry = deepcopy(transaction)
        entry.setdefault("source", self.source)
        entry.setdefault("timestamp", utc_now())
        self.transactions.append(entry)

    def record_capture(self, capture: dict[str, Any]) -> None:
        self._check_source(capture)
        entry = deepcopy(capture)
        entry.setdefault("source", self.source)
        entry.setdefault("timestamp", utc_now())
        self.captures.append(entry)

    def apply_event(self, event: Event) -> None:
        if event.source.upper() != self.source:
            raise ValueError("Cannot mix Live and Replay experiment events")
        self._check_source(event.data)
        self.events.append(deepcopy(event))
        kind = event.kind.upper()
        data = event.data
        if kind in {"CONNECTION_START", "CONNECTING"}:
            self.transition("CONNECTING")
        elif kind in {"BOARD_READY", "CONNECTED", "CONNECTION_OPEN"}:
            self.transition("CONNECTED")
            if isinstance(data.get("capabilities"), dict):
                self.capabilities.update(deepcopy(data["capabilities"]))
        elif kind == "CAPABILITIES":
            self.capabilities.update(deepcopy(data))
        elif kind == "CONFIG_APPLIED":
            self.transition("READY")
        elif kind in {"SESSION_START", "TRANSACTION_START"}:
            self.transition("RUNNING")
        elif kind in {"PACKET_CAPTURE", "IQ_CAPTURE", "CAPTURE"}:
            self.record_capture(data.get("capture", data))
        elif kind == "TRANSACTION_COMPLETE":
            self.record_transaction(data.get("transaction", data))
            self.transition("READY")
        elif kind in {"SESSION_ERROR", "TRANSACTION_ERROR"}:
            self.errors.append(str(data.get("message", "Experiment error")))
            self.transition("FAILED")
        elif kind in {"STOP_REQUESTED", "STOPPING"}:
            self.transition("STOPPING")
        elif kind in {"SESSION_STOPPED", "STOPPED"}:
            self.transition("STOPPED")
        elif kind in {"DISCONNECTED", "CONNECTION_CLOSED"}:
            self.transition("DISCONNECTED")
        # An arbitrary summary event does not prove a successful transaction.

    apply = apply_event

    def to_dict(self) -> dict[str, Any]:
        self._check_source([self.parameters, self.transactions, self.captures, self.capabilities])
        for event in self.events:
            if event.source.upper() != self.source:
                raise ValueError("Cannot mix Live and Replay experiment events")
            self._check_source(event.data)
        return _json_value({"id": self.id, "source": self.source, "state": self.state,
                            "parameters": self.parameters, "events": self.events,
                            "transactions": self.transactions, "captures": self.captures,
                            "capabilities": self.capabilities, "errors": self.errors,
                            "started_at": self.started_at, "ended_at": self.ended_at,
                            "classification": "REPLAY / OFFLINE" if self.source == "REPLAY" else "LIVE"})
