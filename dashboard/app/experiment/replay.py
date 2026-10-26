"""Explicit offline fixtures for the same experiment transaction interface."""
from __future__ import annotations

import secrets

from .client import StageDClient, StageDError, legacy_iq
from .profile import ProfileConfig, build_packet, parse_packet


class ReplayClient(StageDClient):
    def __init__(self, *args, **kwargs):
        self.replay_version = int(kwargs.pop("replay_version", 4))
        if self.replay_version not in {3, 4}:
            raise ValueError("Replay firmware version must be 3 or 4")
        super().__init__(*args, **kwargs)
        self._next = {"DATA": 0, "CONTEXT": 0, "VERSION": 0}
        self._startup = True
        self._context_pending = True
        self._last_packet = None

    def _event(self, kind, **data):
        if self.event_callback:
            self.event_callback({"kind": kind, "source": "REPLAY", "data": {**data, "fixture": True}})

    def connect(self):
        if self.connected:
            raise StageDError("Replay is already connected")
        self.session_id = secrets.randbelow(0xFFFFFFFE) + 1
        self._next = {"DATA": 0, "CONTEXT": 0, "VERSION": 0}
        self._pending_packets = []
        self._startup, self._context_pending, self.configured = True, True, False
        self.connected, self.protocol_version, self.state = True, self.replay_version, "READY"
        legacy = self.replay_version == 3
        self.capabilities = {"PROTO": self.replay_version, "MIN_SAMPLES": 256 if legacy else 1, "MAX_SAMPLES": 256,
                             "CUSTOM_TX": int(not legacy), "CUSTOM_RX": int(not legacy), "CONFIG": int(not legacy),
                             "REPLAY_FIXTURE": True, "VERSION_ON_DEMAND": 0}
        self.last_status = {"STATE": "READY", "UTC": 0, "SESSION": self.session_id,
                            "NEXT_DATA": 0, "NEXT_CONTEXT": 0, "NEXT_VERSION": 0,
                            "RX_DATA_NEXT": 0, "RX_CONTEXT_NEXT": 0, "RX_VERSION_NEXT": 0}
        if legacy:
            self.last_status.update(MODE=0, TX=0, RX=0, PENDING=0, STEP=0, MON=0, ENGINE=0)
            self.capabilities.update(MAX_ROUNDS=16, DATA_SID=1, VERSION_SID=2)
        self._event("BOARD_READY", message="REPLAY FIXTURE / OFFLINE; no UDP or physical FPGA validation",
                    state=self.state, capabilities=self.capabilities)
        return {"caps": dict(self.capabilities), "capabilities": dict(self.capabilities),
                "status": dict(self.last_status), "protocol_version": self.protocol_version, "state": self.state}

    def status(self):
        if not self.connected:
            raise StageDError("Replay is disconnected")
        self.last_status.update({"STATE": "READY", **{f"NEXT_{key}": value for key, value in self._next.items()}})
        return dict(self.last_status)

    def initialize_utc(self, seconds, ns=0):
        if not self.connected or self.last_status.get("UTC"):
            raise StageDError("Replay UTC requires a connected session with UTC=0")
        if not 0 <= int(seconds) <= 0xFFFFFFFF or not 0 <= int(ns) < 1_000_000_000:
            raise ValueError("Invalid UTC seconds / nanoseconds")
        self._seconds, self._picoseconds = int(seconds), int(ns) * 1000
        self.last_status["UTC"] = 1
        return self.status()

    def configure(self, config):
        if not self.connected or self.state != "READY":
            raise StageDError("Replay configuration requires READY")
        candidate = config if isinstance(config, ProfileConfig) else ProfileConfig.from_dict(config)
        candidate.validate()
        if self.protocol_version == 3 and candidate.to_dict() != ProfileConfig().to_dict():
            raise StageDError("v0.3 Replay supports only the fixed 256-sample SID 1/2 profile")
        self.config = candidate
        self.configured = True
        self._context_pending = True
        return self.status()

    def _fixture_result(self, direction, packets, reference, actual):
        self.state = "WAITING_RX" if self.protocol_version == 3 and direction == "TX" else "READY"
        self.status()
        result = self._result(direction, packets, reference, actual, self._tx_round, self._new_id())
        self._tx_round += 1
        result.update(source="REPLAY", fixture=True, provenance="REPLAY FIXTURE / " + result["provenance"])
        self.stop_event.wait(.025)  # Worker-only pacing; never blocks the Qt thread.
        result["stopped"] = self.stop_event.is_set()
        return result

    def tx(self, iq=None, config=None):
        if config is not None:
            self.configure(config)
        self._require_transfer("TX")
        if self.protocol_version == 3:
            if self.last_status["TX"] >= 16:
                raise StageDError("v0.3 Replay supports at most 16 TX rounds")
            reference = legacy_iq(self.last_status["TX"])
            if iq is not None and list(map(tuple, iq)) != reference:
                raise StageDError("v0.3 Replay cannot accept arbitrary custom TX IQ")
            iq = reference
        iq = list(map(tuple, iq or []))
        if len(iq) != self.config.samples:
            raise ValueError("Replay IQ count must match configured samples")
        self.state = "TX_ACTIVE"
        kinds = (["VERSION"] if self._startup else []) + (["CONTEXT"] if self._context_pending else []) + ["DATA"]
        packets = []
        for kind in kinds:
            raw = build_packet(kind, self.config, iq if kind == "DATA" else None,
                               sequence=self._next[kind] & 15, seconds=getattr(self, "_seconds", 1700000000),
                               picoseconds=getattr(self, "_picoseconds", 0), changed=self._next[kind] == 0)
            packets.append({"raw": raw, "parsed": self._parse_tx(raw)})
            self._next[kind] += 1
        self._startup, self._context_pending = False, False
        self._last_packet = packets[-1]["raw"]
        if self.protocol_version == 3:
            self._pending_packets = packets
            self.last_status.update(TX=self.last_status["TX"] + 1, PENDING=1)
        return self._fixture_result("TX", packets, iq, packets[-1]["parsed"]["iq"])

    def rx(self, packet=None, config=None):
        if config is not None:
            self.configure(config)
        self._require_transfer("RX")
        if self.protocol_version == 3:
            if packet is not None and bytes(packet) != self._last_packet:
                raise StageDError("v0.3 Replay RX must use its cached TX bytes")
            self.last_status.update(RX=self.last_status["RX"] + 1, PENDING=0)
            packets = self._pending_packets
            self._pending_packets = []
            iq = packets[-1]["parsed"]["iq"]
            return self._fixture_result("RX", packets, iq, list(iq))
        raw = packet if packet is not None else self._last_packet
        if raw is None:
            raise ValueError("Replay RX requires an explicitly constructed or captured packet")
        parsed = parse_packet(raw, self.config)
        key = f"RX_{parsed['packet_type']}_NEXT"
        if parsed["sequence"] != (self.last_status[key] & 15):
            raise StageDError("Replay RX sequence disagrees with the managed board counter")
        self.last_status[key] += 1
        self.state = "RX_ACTIVE"
        iq = parsed.get("iq", [])
        result = self._fixture_result("RX", [{"raw": raw, "parsed": parsed}], iq, list(iq))
        result["verification"] = {"STATE": "READY", "TYPE": parsed["packet_type"], "META": 1 if not iq else 0,
                                  "SAMPLES": len(iq), "PACKETS": 1, "SEQ": parsed["sequence"], "fixture": True}
        return result

    def disconnect(self):
        self.connected, self.state = False, "DISCONNECTED"
