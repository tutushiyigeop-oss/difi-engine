"""Qt orchestration for Stage D; socket calls run on one dedicated worker."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from pathlib import Path
from queue import Empty, Queue
import threading
import struct

from PySide6.QtCore import QObject, QTimer, Signal

from dashboard.app.models.events import Event
from .client import StageDClient, StageDError, legacy_iq
from .models import ExperimentSession
from .profile import ProfileConfig, parse_packet
from .replay import ReplayClient


class ExperimentController(QObject):
    event = Signal(object)
    log = Signal(str, str, str)
    changed = Signal(object)
    finished = Signal(object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = ExperimentSession()
        self.config = ProfileConfig()
        self.state = "DISCONNECTED"
        self._busy = False
        self._client = None
        self._future = None
        self._operation = None
        self._stop = threading.Event()
        self._messages = Queue()
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="stage-d-udp")
        self._timer = QTimer(self)
        self._timer.setInterval(20)
        self._timer.timeout.connect(self._poll)
        self._timer.start()
        self._status, self._caps = {}, {}
        self._connected, self._protocol = False, 0

    @property
    def busy(self):
        return self._busy

    @property
    def running(self):
        return self._busy

    @property
    def connected(self):
        return self._connected

    @property
    def protocol_version(self):
        return self._protocol

    def snapshot(self):
        # Admitted records are immutable. Copy only the history containers for
        # the UI; recursive IQ/packet serialization belongs in export workers.
        session_view = {"id": self.session.id, "source": self.session.source, "state": self.session.state,
                        "parameters": deepcopy(self.session.parameters), "transactions": list(self.session.transactions),
                        "captures": list(self.session.captures), "events": list(self.session.events),
                        "capabilities": deepcopy(self.session.capabilities), "errors": list(self.session.errors),
                        "started_at": self.session.started_at, "ended_at": self.session.ended_at}
        return {"state": self.state, "busy": self.busy, "connected": self.connected,
                "protocol_version": self._protocol, "capabilities": deepcopy(self._caps),
                "caps": deepcopy(self._caps), "status": deepcopy(self._status),
                "config": self.config.to_dict(), "session": session_view}

    def _emit(self, kind, **data):
        event = Event(kind, self.session.source, data)
        self.session.apply_event(event)
        self.event.emit(event)

    def _worker_event(self, value):
        self._messages.put(("event", value))

    def _submit(self, operation, function, state):
        if self.busy:
            self.log.emit("WARN", self.session.source, "A Stage D command is already in progress")
            return False
        self._busy, self._operation = True, operation
        self._stop.clear()
        self.state = state
        self._future = self._executor.submit(function)
        self.changed.emit(self.snapshot())
        return True

    def connect_board(self, params: dict, source="LIVE"):
        if self.busy or self.connected:
            self.log.emit("WARN", self.session.source, "Disconnect before opening another Stage D session")
            return False
        source = str(source).upper()
        if source not in {"LIVE", "REPLAY"}:
            raise ValueError("Source must be LIVE or REPLAY")
        self.session = ExperimentSession(source=source, parameters=deepcopy(params))
        self._client = None
        self._emit("CONNECTION_START")
        allowed = {key: value for key, value in params.items() if key in {"board", "local_ip", "port", "local_port", "timeout"}}
        if source == "REPLAY":
            allowed["replay_version"] = int(params.get("replay_version", 4))
        def connect_worker():
            self._client = (StageDClient if source == "LIVE" else ReplayClient)(
                **allowed, event_callback=self._worker_event, stop_event=self._stop)
            return self._client.connect()
        return self._submit("connect", connect_worker, "CONNECTING")

    def initialize_utc(self, sec, ns=0):
        if not self.connected:
            return False
        return self._submit("utc", lambda: self._client.initialize_utc(sec, ns), "CONFIGURING")

    def configure(self, config):
        if not self.connected:
            return False
        config = config if isinstance(config, ProfileConfig) else ProfileConfig.from_dict(config)
        config.validate()
        def configure_worker():
            return self._client.configure(config)
        return self._submit("configure", configure_worker, "CONFIGURING")

    def refresh_status(self):
        if not self.connected:
            return False
        return self._submit("status", self._client.status, "CHECKING_STATUS")

    def run(self, direction, iq=None, packet=None, rounds=1, alternate=False, config=None):
        if not self.connected or self.busy:
            self.log.emit("WARN", self.session.source, "Connect and wait for the current command to finish")
            return False
        direction = str(direction).upper()
        if direction not in {"TX", "RX"} or isinstance(rounds, bool) or not isinstance(rounds, int) or not 1 <= rounds <= 1000:
            raise ValueError("Direction must be TX/RX and rounds must be 1..1000")
        chosen = config if isinstance(config, ProfileConfig) else ProfileConfig.from_dict(config) if config is not None else None
        if chosen:
            chosen.validate()
        frozen_iq = deepcopy(iq)
        frozen_packet = bytes(packet) if packet is not None else None
        if self.state != "WAITING_RX" and (self.session.transactions or self.session.state in {"COMPLETED", "FAILED", "STOPPED"}):
            previous = self.session
            self.session = ExperimentSession(source=previous.source, parameters=deepcopy(previous.parameters))
            self.session.capabilities = deepcopy(self._caps)
            self._emit("SESSION_CONTEXT", protocol=self._protocol, wire_session_id=self._client.session_id,
                       status=deepcopy(self._status), config=self.config.to_dict(),
                       message="New experiment evidence session; existing UDP connection and board counters retained")
            self.changed.emit(self.snapshot())
        self._emit("TRANSACTION_START", direction=direction, rounds=rounds, alternate=bool(alternate))

        def transfer_worker():
            client = self._client
            transactions = []
            if chosen and chosen.to_dict() != client.config.to_dict():
                client.configure(chosen)
            elif chosen and client.protocol_version == 4 and not client.configured:
                client.configure(chosen)
            if client.protocol_version == 3 and frozen_iq is not None and direction == "TX":
                if list(map(tuple, frozen_iq)) != legacy_iq(int(client.last_status["TX"])):
                    raise StageDError("v0.3 TX cannot accept custom IQ; select the firmware fixed pattern")
            def record(result):
                transactions.append(result)
                self._messages.put(("transaction", result))
                if not result["comparison"].get("exact", False):
                    raise StageDError("Actual FPGA IQ differs from the reference; mismatch evidence was retained")
                return result
            def transfer(phase, raw=None, basis=None):
                self._messages.put(("phase", f"{phase}_ACTIVE"))
                result = client.tx(None if client.protocol_version == 3 else frozen_iq) if phase == "TX" else client.rx(raw)
                if basis:
                    result["reference_basis"] = basis
                return record(result)
            def resequence(raw):
                if raw is None or client.protocol_version == 3:
                    return raw
                parsed = parse_packet(raw, client.config)
                key = f"RX_{parsed['packet_type']}_NEXT"
                if key not in client.last_status:
                    return raw
                word0 = int.from_bytes(raw[:4], "big")
                word0 = (word0 & ~0x000F0000) | ((int(client.last_status[key]) & 15) << 16)
                return struct.pack("!I", word0) + raw[4:]
            for _ in range(rounds):
                if self._stop.is_set():
                    break
                if direction == "TX":
                    result = transfer("TX")
                    if alternate and not self._stop.is_set():
                        if client.protocol_version == 3:
                            transfer("RX")
                        else:
                            for item in result["packets"]:
                                if self._stop.is_set():
                                    break
                                transfer("RX", resequence(item["raw"]),
                                         "FPGA TX payload; RX sequence managed independently")
                else:
                    transfer("RX", resequence(frozen_packet))
                    if alternate and not self._stop.is_set():
                        transfer("TX")
            return {"transactions": transactions, "stopped": self._stop.is_set()}
        return self._submit("run", transfer_worker, f"{direction}_ACTIVE")

    def stop(self):
        if not self.busy:
            return False
        self._stop.set()
        self.state = "DRAINING"
        self._emit("STOP_REQUESTED", message="Stop requested; draining the in-flight transaction and confirming board state")
        self.changed.emit(self.snapshot())
        return True

    def disconnect(self):
        if self.busy:
            self.log.emit("WARN", self.session.source, "Stop and drain the active command before disconnecting")
            return False
        if self._client is None:
            self._connected, self.state = False, "DISCONNECTED"
            self.changed.emit(self.snapshot())
            return True
        return self._submit("disconnect", self._client.disconnect, "DISCONNECTING")

    def reset(self):
        if self.busy or self.connected:
            self.log.emit("WARN", self.session.source, "Disconnect before resetting the experiment evidence")
            return False
        source = self.session.source
        self.session = ExperimentSession(source=source)
        self._status, self._caps, self._protocol = {}, {}, 0
        self.state = "DISCONNECTED"
        self.changed.emit(self.snapshot())
        return True

    def _poll(self):
        while True:
            try:
                kind, value = self._messages.get_nowait()
            except Empty:
                break
            if kind == "phase":
                self.state = value
                self.changed.emit(self.snapshot())
            elif kind == "transaction":
                self.session.record_transaction(value)
                event = Event("TRANSACTION_CAPTURED", self.session.source, {"transaction": value})
                self.session.events.append(event)
                self.event.emit(event)
                self._status = deepcopy(value.get("status", self._status))
                self.state = value.get("state", self.state)
                self.changed.emit(self.snapshot())
                self.log.emit("PASS" if value["comparison"].get("exact") else "FAIL", self.session.source,
                              f"{value['provenance']} {value['direction']} transaction {value['transaction']}: "
                              f"{len(value['actual_iq'])} IQ samples, mismatches={value['comparison'].get('mismatches')}")
            else:
                event = Event(value["kind"], self.session.source, value.get("data", {}))
                self.session.apply_event(event)
                self.event.emit(event)
                message = value.get("data", {}).get("message")
                if message:
                    self.log.emit("ERROR" if event.kind == "SESSION_ERROR" else "INFO", self.session.source, message)
        if self._future is None or not self._future.done():
            return
        if not self._messages.empty():
            # Once Future.done is true every worker message is already queued.
            # Drain that final batch before publishing finished/changed.
            self._poll()
            return
        future, operation = self._future, self._operation
        self._future = None
        preserve_measurement = operation == "disconnect" and self.session.state in {"COMPLETED", "FAILED", "STOPPED"}
        error, result = "", None
        try:
            result = future.result()
        except Exception as exc:
            error = str(exc)
            if preserve_measurement:
                event = Event("CONNECTION_ERROR", self.session.source, {"message": error})
                self.session.events.append(event)
                self.event.emit(event)
            else:
                self._emit("SESSION_ERROR", message=error)
            self.log.emit("ERROR", self.session.source, error)
        client = self._client
        if client:
            self._connected, self._protocol = client.connected, client.protocol_version
            self._status, self._caps = deepcopy(client.last_status), deepcopy(client.capabilities)
            self.config = deepcopy(client.config)
            self.state = client.state
        self.session.capabilities = deepcopy(self._caps)
        stopped = self._stop.is_set()
        if error and not preserve_measurement:
            if self._connected and self.state in {"READY", "WAITING_RX"}:
                # Local validation failed before issuing a board command.
                self.session.transition("FAILED")
            else:
                self.state = client.state if client else "FAULT"
        elif stopped:
            self.session.transition("STOPPED")
        elif operation == "run":
            self.session.transition("COMPLETED")
        elif operation == "disconnect":
            if preserve_measurement:
                event = Event("CONNECTION_CLOSED", self.session.source, {"measurement_state_retained": self.session.state})
                self.session.events.append(event)
                self.event.emit(event)
            else:
                self._emit("DISCONNECTED")
        else:
            self.session.transition("READY" if self.state == "READY" else "CONNECTED")
        self._busy = False
        self.changed.emit(self.snapshot())
        self.finished.emit({"success": not bool(error), "operation": operation, "error": error,
                            "stopped": stopped, "state": self.state,
                            "transactions": result.get("transactions", []) if isinstance(result, dict) else []})

    def export(self, destination):
        from .exporter import export_experiment
        snapshot = self.snapshot()["session"]
        snapshot.update(status=deepcopy(self._status), config=self.config.to_dict())
        return self._executor.submit(export_experiment, snapshot, Path(destination))

    def shutdown(self):
        """Request stop; GUI should wait for busy=False before destroying itself."""
        self.stop()
        if not self.busy and self._client:
            self._executor.submit(self._client.disconnect)
        self._executor.shutdown(wait=False)


StageDController = ExperimentController
