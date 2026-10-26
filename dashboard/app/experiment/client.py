"""Stage D UDP transport. Synchronous methods must run in a worker thread.

Construction is network-free. A connection owns one UDP source port until
disconnect, because v0.3 firmware locks its session to that exact endpoint.
"""
from __future__ import annotations

from ipaddress import IPv4Address
import secrets
import socket
import struct
import threading
import time
from typing import Any, Callable

from .profile import ProfileConfig, decode_iq, encode_config, encode_iq, parse_packet
from .iq import compare_iq

HEADER = struct.Struct("!4sBBHIIII")
MAGIC = b"SDU4"
CAPS, OPEN, CONFIG, UTC, TX, RX, STATUS, CLOSE = range(1, 9)
PACKET, IQ, DONE, ERROR = 0x90, 0x91, 0x92, 0xFF


class StageDError(RuntimeError):
    pass


def fields(raw: bytes | str) -> dict[str, Any]:
    text = raw.decode("ascii", "strict") if isinstance(raw, bytes) else raw
    result: dict[str, Any] = {"raw": text}
    for token in text.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        if key in result:
            raise StageDError(f"Duplicate response field {key}")
        if key in {"MON", "ENGINE", "MON_COUNT", "MON_DETAIL"}:
            try:
                result[key] = int(value, 16)
                continue
            except ValueError:
                raise StageDError(f"Invalid hexadecimal {key}") from None
        result[key] = int(value) if value.isdecimal() else value
    return result


def legacy_iq(round_id: int) -> list[tuple[int, int]]:
    from scripts.verify.tools.difi_b6_sender import expected_iq
    result = []
    for index in range(256):
        word = expected_iq(round_id, index)
        i, q = word >> 16, word & 65535
        result.append((i - 65536 if i & 32768 else i, q - 65536 if q & 32768 else q))
    return result


class StageDClient:
    def __init__(self, board="192.168.1.10", local_ip="192.168.1.20", port=4991,
                 local_port=0, timeout=5, event_callback: Callable | None = None,
                 stop_event: threading.Event | None = None):
        self.board, self.local_ip = str(IPv4Address(board)), str(IPv4Address(local_ip))
        self.port, self.local_port, self.timeout = int(port), int(local_port), float(timeout)
        if not 1 <= self.port <= 65535 or not 0 <= self.local_port <= 65535 or not 0 < self.timeout <= 3600:
            raise ValueError("Invalid UDP port or timeout")
        self.event_callback = event_callback
        self.stop_event = stop_event or threading.Event()
        self.sock: socket.socket | None = None
        self.connected = False
        self.state = "DISCONNECTED"
        self.protocol_version = 0
        self.session_id = secrets.randbelow(0xFFFFFFFE) + 1
        self.transaction_id = 0
        self.capabilities: dict[str, Any] = {}
        self.last_status: dict[str, Any] = {}
        self.config = ProfileConfig()
        self.configured = False
        self._pending_packets: list[dict] = []
        self._tx_round = 0
        self._completed_frames = {}

    def _event(self, kind: str, **data) -> None:
        if self.event_callback:
            self.event_callback({"kind": kind, "source": "LIVE", "data": data})

    def _send(self, raw: bytes) -> None:
        if self.sock is None:
            raise StageDError("Not connected")
        if self.sock.sendto(raw, (self.board, self.port)) != len(raw):
            raise StageDError("Incomplete UDP send")

    def _recv(self, deadline: float) -> bytes:
        if self.sock is None:
            raise StageDError("Not connected")
        while time.monotonic() < deadline:
            if self.stop_event.is_set():
                self.state = "DRAINING"
            self.sock.settimeout(min(.1, max(.001, deadline - time.monotonic())))
            try:
                raw, peer = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            if peer != (self.board, self.port):
                self._event("TRANSPORT_IGNORED", message="Ignoring datagram from another UDP peer")
                continue
            return raw
        raise TimeoutError("Stage D UDP timeout; board state is indeterminate. No TX/RX command was retried.")

    def _deadline(self) -> float:
        return time.monotonic() + self.timeout

    def _fail(self, exc: Exception):
        self.state = "DISCONNECTED_INDETERMINATE" if isinstance(exc, (TimeoutError, OSError)) else "FAULT"
        self.connected = False
        if self.sock:
            self.sock.close()
            self.sock = None
        self._event("SESSION_ERROR", message=str(exc), state=self.state)
        raise exc

    def _ascii(self, command: bytes, prefix: bytes) -> bytes:
        self._send(command)
        deadline = self._deadline()
        while True:
            raw = self._recv(deadline)
            if raw.startswith((b"FAIL", b"ACK FAIL")):
                raise StageDError(raw.decode("ascii", "replace"))
            if raw.startswith(prefix):
                return raw
            # Exact old acknowledgements / payloads may arrive late. They do not
            # satisfy this request and the original timeout is never extended.
            self._event("TRANSPORT_IGNORED", message="Ignoring unrelated legacy datagram")

    def _new_id(self) -> int:
        self.transaction_id += 1
        if self.transaction_id > 0xFFFFFFFF:
            raise StageDError("Transaction ID exhausted; reconnect before another request")
        return self.transaction_id

    def _request(self, opcode: int, payload=b"") -> int:
        txid = self._new_id()
        self._send(HEADER.pack(MAGIC, 4, opcode, 0, self.session_id, txid, len(payload), 0) + payload)
        return txid

    def _frame(self, txid: int, deadline: float) -> tuple[int, bytes]:
        while True:
            raw = self._recv(deadline)
            if len(raw) < HEADER.size or not raw.startswith(MAGIC):
                self._event("TRANSPORT_IGNORED", message="Ignoring unrelated non-v4 datagram")
                continue
            magic, version, opcode, flags, session, transaction, length, code = HEADER.unpack_from(raw)
            if session != self.session_id:
                self._event("TRANSPORT_IGNORED", message="Ignoring stale session or transaction")
                continue
            if transaction != txid:
                previous = self._completed_frames.get(transaction)
                if previous is not None and flags == 0 and version == 4 and length == len(raw) - HEADER.size:
                    body = raw[HEADER.size:]
                    key = None
                    if opcode == PACKET:
                        parsed = parse_packet(body)
                        key = (PACKET, parsed["packet_type"], parsed["sequence"])
                    elif opcode in {IQ, DONE}:
                        key = (opcode,)
                    if key in previous and previous[key] != body:
                        raise StageDError("Conflicting duplicate from a completed transaction")
                self._event("TRANSPORT_IGNORED", message="Ignoring stale session or transaction")
                continue
            if magic != MAGIC or version != 4 or flags != 0 or length != len(raw) - HEADER.size:
                raise StageDError("Malformed v4 response envelope")
            body = raw[HEADER.size:]
            if opcode == ERROR or code:
                raise StageDError(f"Board ERROR {code}: {body.decode('ascii', 'replace')}")
            return opcode, body

    def _simple(self, opcode: int, payload=b"") -> dict:
        txid = self._request(opcode, payload)
        reply, body = self._frame(txid, self._deadline())
        if reply != (opcode | 0x80):
            raise StageDError(f"Unexpected reply opcode 0x{reply:02x}")
        return fields(body)

    def connect(self) -> dict:
        if self.connected:
            raise StageDError("Already connected; disconnect before changing UDP endpoints")
        try:
            self.session_id = secrets.randbelow(0xFFFFFFFE) + 1
            self.transaction_id = 0
            self.configured = False
            self._pending_packets = []
            self._completed_frames = {}
            self.state = "CONNECTING"
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.local_ip, self.local_port))
            discovery = self._ascii(b"STATUS", b"STATUS ")
            stat = fields(discovery)
            if stat.get("PROTO") == 4:
                self.protocol_version = 4
                self.capabilities = self._simple(CAPS)
                if self.capabilities.get("PROTO") != 4 or not 1 <= int(self.capabilities.get("MIN_SAMPLES", 0)) <= int(self.capabilities.get("MAX_SAMPLES", 0)) <= 256:
                    raise StageDError("Malformed or incompatible v4 capabilities")
                self.last_status = self._simple(OPEN)
                if self.last_status.get("SESSION") != self.session_id:
                    raise StageDError("OPEN did not confirm the requested session")
                if self.last_status.get("STATE") != "READY":
                    raise StageDError("Board OPEN did not report READY")
                self.state = "READY"
            elif all(key in stat for key in ("MODE", "UTC", "TX", "RX", "PENDING", "STEP", "MON", "ENGINE")):
                self.protocol_version = 3
                self.capabilities = {"PROTO": 3, "MIN_SAMPLES": 256, "MAX_SAMPLES": 256,
                                     "CUSTOM_TX": 0, "CUSTOM_RX": 0, "CONFIG": 0,
                                     "MAX_ROUNDS": 16, "DATA_SID": 1, "VERSION_SID": 2}
                self.last_status = stat
                self._legacy_state()
            else:
                raise StageDError("Unrecognized Stage D firmware STATUS; no v4 command sent")
            self.connected = True
            self._event("BOARD_READY", protocol=self.protocol_version, status=self.last_status,
                        capabilities=self.capabilities, state=self.state)
            return {"caps": dict(self.capabilities), "capabilities": dict(self.capabilities),
                    "status": dict(self.last_status), "protocol_version": self.protocol_version,
                    "state": self.state, "local_endpoint": self.sock.getsockname()}
        except Exception as exc:
            return self._fail(exc)

    def _legacy_state(self):
        if (self.last_status.get("MODE") not in {0, 1, 2, 3}
                or self.last_status.get("UTC") not in {0, 1}
                or self.last_status.get("PENDING") not in {0, 1}
                or not all(isinstance(self.last_status.get(key), int) and self.last_status[key] >= 0 for key in ("TX", "RX", "STEP"))):
            raise StageDError("Malformed legacy STATUS")
        if self.last_status.get("MODE") != 0:
            self.state = "FAULT" if self.last_status.get("MODE") == 3 else "RECOVERY_REQUIRED"
        elif self.last_status.get("PENDING"):
            self.state = "WAITING_RX" if self._pending_packets else "RECOVERY_REQUIRED"
        else:
            self.state = "READY"

    def status(self) -> dict:
        if not self.connected:
            raise StageDError("Not connected")
        try:
            self.last_status = self._simple(STATUS) if self.protocol_version == 4 else fields(self._ascii(b"STATUS", b"STATUS "))
            if self.protocol_version == 4:
                if self.last_status.get("SESSION") != self.session_id:
                    raise StageDError("Board STATUS returned another session identity")
                if self.last_status.get("STATE") != "READY":
                    raise StageDError("Board STATUS has not confirmed READY")
                self.state = "READY"
            else:
                self._legacy_state()
            return dict(self.last_status)
        except Exception as exc:
            return self._fail(exc)

    def initialize_utc(self, seconds: int, ns: int = 0) -> dict:
        if not self.connected or self.state not in {"READY", "WAITING_RX"}:
            raise StageDError("Connect to an idle board before UTC initialization")
        if self.last_status.get("UTC"):
            raise StageDError("UTC is already initialized; reload PL for a fresh UTC value")
        if not 0 <= int(seconds) <= 0xFFFFFFFF or not 0 <= int(ns) < 1_000_000_000:
            raise ValueError("UTC requires uint32 seconds and nanoseconds 0..999999999")
        try:
            if self.protocol_version == 4:
                self._simple(UTC, struct.pack("!II", int(seconds), int(ns)))
            else:
                self._ascii(f"UTC {int(seconds)} {int(ns)}".encode(), b"OK UTC ENGINE_READY")
            return self.status()
        except Exception as exc:
            return self._fail(exc)

    def configure(self, config: ProfileConfig | dict) -> dict:
        config = config if isinstance(config, ProfileConfig) else ProfileConfig.from_dict(config)
        config.validate()
        if self.state != "READY" or not self.connected:
            raise StageDError("Configuration requires confirmed READY")
        if self.protocol_version == 3:
            if config.to_dict() != ProfileConfig().to_dict():
                raise StageDError("v0.3 supports only the fixed 256-sample SID 1/2 profile; custom configuration requires v4")
            self.config = config
            return dict(self.last_status)
        if self.capabilities.get("CONFIG") != 1:
            raise StageDError("Board capabilities do not support configuration")
        if not int(self.capabilities["MIN_SAMPLES"]) <= config.samples <= int(self.capabilities["MAX_SAMPLES"]):
            raise StageDError("Sample count is outside the board's advertised capabilities")
        try:
            reply = self._simple(CONFIG, encode_config(config))
            if reply.get("STATE") != "READY":
                raise StageDError("CONFIG did not confirm READY")
            echo = {"DATA_SID": config.data_sid, "VERSION_SID": config.version_sid, "SAMPLES": config.samples,
                    "FS": config.sample_rate, "BW": config.bandwidth, "RF_HZ": config.rf_hz,
                    "RX_FILTER": config.rx_filter, "RX_DATA_SID": config.rx_data_sid,
                    "RX_VERSION_SID": config.rx_version_sid}
            if any(reply.get(key) != value for key, value in echo.items()):
                raise StageDError("CONFIG readback does not match the requested profile")
            self.config = config
            self.configured = True
            return self.status()
        except Exception as exc:
            return self._fail(exc)

    def _require_transfer(self, direction: str):
        if not self.connected or not self.last_status.get("UTC"):
            raise StageDError("Explicit UTC initialization is required before transfer")
        if self.protocol_version == 4:
            if self.capabilities.get(f"CUSTOM_{direction}") != 1:
                raise StageDError(f"Board capabilities do not support custom {direction}")
            if not self.configured:
                raise StageDError("Apply and confirm a configuration before transfer")
        if self.protocol_version == 3 and direction == "RX":
            if self.state != "WAITING_RX" or not self._pending_packets:
                raise StageDError("v0.3 RX requires this connection's cached actual TX packets; pending capture cannot be reconstructed")
        elif self.state != "READY":
            raise StageDError(f"Direction change rejected while state is {self.state}")

    def _result(self, direction, packets, reference, actual, round_id, transaction):
        comparison = compare_iq(reference, actual) if reference or actual else {
            "complete": True, "exact": True, "not_requested": True, "mismatches": 0,
            "expected_samples": 0, "actual_samples": 0}
        return {"round": round_id, "transaction": transaction, "direction": direction,
                "packets": packets, "reference_iq": reference, "actual_iq": actual,
                "reference_iq_hex": encode_iq(reference).hex(), "actual_iq_hex": encode_iq(actual).hex(),
                "provenance": "FPGA TX CAPTURE" if direction == "TX" else "FPGA RX S2MM",
                "comparison": comparison, "state": self.state, "source": "LIVE",
                "status": dict(self.last_status), "stopped": self.stop_event.is_set()}

    def _parse_tx(self, raw):
        # RX filters apply only to packets sent into FPGA RX, never to captures
        # produced by its independently configured TX path.
        parsed = parse_packet(raw)
        kind = parsed["packet_type"]
        expected_sid = self.config.version_sid if kind == "VERSION" else self.config.data_sid
        if parsed["stream_id"] != expected_sid:
            raise StageDError("FPGA TX capture Stream ID differs from its TX configuration")
        if kind == "DATA" and parsed["samples"] != self.config.samples:
            raise StageDError("FPGA TX capture sample count differs from TX configuration")
        if kind == "CONTEXT" and any(parsed["fields"][key] != getattr(self.config, key)
                                      for key in ("sample_rate", "bandwidth", "rf_hz")):
            raise StageDError("FPGA TX Context differs from the configured frequencies")
        return parsed

    def tx(self, iq=None, config=None) -> dict:
        if config is not None:
            self.configure(config)
        self._require_transfer("TX")
        if self.protocol_version == 3:
            reference = legacy_iq(int(self.last_status["TX"]))
            if iq is not None and list(map(tuple, iq)) != reference:
                raise StageDError("v0.3 TX generates the firmware's fixed IQ pattern; arbitrary PC IQ requires v4")
            return self._tx_legacy(reference)
        reference = list(map(tuple, iq or []))
        if len(reference) != self.config.samples:
            raise ValueError("IQ sample count must match the configured samples")
        return self._transfer_v4(TX, encode_iq(reference), "TX", reference)

    def rx(self, packet=None, config=None) -> dict:
        if config is not None:
            self.configure(config)
        self._require_transfer("RX")
        if self.protocol_version == 3:
            data = next(item["raw"] for item in self._pending_packets if item["parsed"]["packet_type"] == "DATA")
            if packet is not None and bytes(packet) != data:
                raise StageDError("v0.3 must replay the cached actual TX packet in firmware order")
            return self._rx_legacy()
        if packet is None:
            raise ValueError("v4 RX requires a DIFI packet")
        parsed = parse_packet(bytes(packet), self.config)
        expected_key = {"DATA": "RX_DATA_NEXT", "CONTEXT": "RX_CONTEXT_NEXT", "VERSION": "RX_VERSION_NEXT"}[parsed["packet_type"]]
        if expected_key in self.last_status and parsed["sequence"] != (int(self.last_status[expected_key]) & 15):
            raise StageDError("RX packet sequence disagrees with the board's independent RX counter")
        return self._transfer_v4(RX, bytes(packet), "RX", parsed.get("iq", []), parsed)

    def _transfer_v4(self, opcode, payload, direction, reference, input_parsed=None):
        self.state = f"{direction}_ACTIVE"
        try:
            txid = self._request(opcode, payload)
            deadline, seen, packets, iq_payload = self._deadline(), {}, [], None
            done, done_raw = None, None
            def payload_complete():
                if done is None:
                    return False
                if direction == "TX":
                    return len(packets) >= int(done.get("PACKETS", 0))
                return input_parsed["packet_type"] != "DATA" or iq_payload is not None
            while True:
                reply, body = self._frame(txid, deadline)
                if reply == PACKET:
                    if direction != "TX":
                        raise StageDError("RX transaction unexpectedly returned a TX packet capture")
                    parsed = self._parse_tx(body)
                    key = (PACKET, parsed["packet_type"], parsed["sequence"])
                elif reply == IQ:
                    if direction != "RX":
                        raise StageDError("TX transaction unexpectedly returned an RX IQ payload")
                    key, parsed = (IQ,), None
                elif reply == DONE:
                    if done_raw is not None and done_raw != body:
                        raise StageDError("Conflicting duplicate DONE response")
                    done, done_raw = fields(body), body
                    if payload_complete():
                        break
                    continue
                else:
                    raise StageDError("Unexpected streaming response opcode")
                if key in seen:
                    if seen[key] != body:
                        raise StageDError("Conflicting duplicate datagram in one transaction")
                    continue
                seen[key] = body
                if reply == PACKET:
                    packets.append({"raw": body, "parsed": parsed})
                else:
                    iq_payload = body
                if payload_complete():
                    break
            if done.get("STATE") != "READY":
                raise StageDError("DONE did not report READY")
            if direction == "TX":
                data = [item for item in packets if item["parsed"]["packet_type"] == "DATA"]
                if len(data) != 1 or done.get("PACKETS") != len(packets):
                    raise StageDError("TX DONE packet count disagrees with received FPGA capture")
                actual = data[0]["parsed"].get("iq", [])
                parsed = data[0]["parsed"]
            else:
                parsed = input_parsed
                packets = [{"raw": payload, "parsed": parsed}]
                actual = decode_iq(iq_payload) if iq_payload is not None else []
                if parsed["packet_type"] == "DATA" and len(actual) != len(reference):
                    raise StageDError("RX DONE without a complete actual S2MM IQ response")
                if parsed["packet_type"] != "DATA" and iq_payload is not None:
                    raise StageDError("Metadata RX unexpectedly returned IQ")
                if parsed["packet_type"] != "DATA" and (done.get("META") != 1 or done.get("PACKETS") != 1):
                    raise StageDError("Metadata RX DONE did not confirm META=1 PACKETS=1")
            if done.get("SEQ") != parsed["sequence"] or done.get("SAMPLES") != len(actual):
                raise StageDError("DONE sequence/sample count does not match actual response")
            if direction == "RX" and done.get("TYPE") != parsed["packet_type"]:
                raise StageDError("RX DONE packet type does not match input")
            self.state = "DRAINING"
            seen[(DONE,)] = done_raw
            self._completed_frames[txid] = seen
            if len(self._completed_frames) > 32:
                self._completed_frames.pop(next(iter(self._completed_frames)))
            self.status()  # A separate transaction confirms the direction is idle.
            result = self._result(direction, packets, reference, actual, self._tx_round, txid)
            result["verification"] = done
            if iq_payload is not None:
                result["actual_iq_raw"] = iq_payload
            self._tx_round += 1
            return result
        except Exception as exc:
            return self._fail(exc)

    def _tx_legacy(self, reference):
        round_id = int(self.last_status["TX"])
        if round_id >= 16:
            raise StageDError("v0.3 supports at most 16 TX rounds; reload the board")
        self.state = "TX_ACTIVE"
        try:
            self._send(b"TX")
            expected = ["VERSION", "CONTEXT", "DATA"] if round_id == 0 else ["DATA"]
            packets, seen, done = [], {}, None
            deadline = self._deadline()
            while done is None:
                raw = self._recv(deadline)
                if raw.startswith((b"FAIL", b"ACK FAIL")):
                    raise StageDError(raw.decode("ascii", "replace"))
                if raw.startswith(b"TXDONE "):
                    done = fields(raw)
                    continue
                parsed = self._parse_tx(raw)
                kind = parsed["packet_type"]
                if kind in seen:
                    if seen[kind] != raw:
                        raise StageDError("Conflicting duplicate legacy TX packet")
                    continue
                if kind != expected[len(packets)] or parsed["sequence"] != (round_id & 15 if kind == "DATA" else 0):
                    raise StageDError("Legacy TX packet order or sequence mismatch")
                seen[kind] = raw
                packets.append({"raw": raw, "parsed": parsed})
            if len(packets) != len(expected) or done.get("SEQ") != (round_id & 15) or done.get("IQ") != 256 or done.get("PACKETS") != len(expected):
                raise StageDError("Incomplete or inconsistent TXDONE")
            self._pending_packets = packets
            self.state = "DRAINING"
            self.status()
            if self.last_status.get("TX") != round_id + 1 or self.last_status.get("PENDING") != 1 or self.last_status.get("MODE") != 0:
                raise StageDError("TX STATUS did not confirm the pending RX capture")
            actual = packets[-1]["parsed"]["iq"]
            return self._result("TX", packets, reference, actual, round_id, self._new_id())
        except Exception as exc:
            return self._fail(exc)

    def _rx_legacy(self):
        packets = list(self._pending_packets)
        round_id = int(self.last_status["TX"]) - 1
        reference = packets[-1]["parsed"]["iq"]
        self.state = "RX_ACTIVE"
        try:
            ready = self._ascii(b"RX", b"READY RX ")
            start = "VERSION" if ready == b"READY RX VERSION" else "DATA" if ready == b"READY RX DATA" else None
            if start is None or start != packets[0]["parsed"]["packet_type"]:
                raise StageDError("RX expected order disagrees with the available actual TX capture")
            actual = None
            for item in packets:
                kind = item["parsed"]["packet_type"]
                self._send(item["raw"])
                deadline, iq_raw, ack, seen = self._deadline(), None, None, set()
                while ack is None or (kind == "DATA" and iq_raw is None):
                    raw = self._recv(deadline)
                    if raw in seen:
                        continue
                    seen.add(raw)
                    if raw.startswith((b"FAIL", b"ACK FAIL")):
                        raise StageDError(raw.decode("ascii", "replace"))
                    if raw.startswith(b"IQD3"):
                        if kind != "DATA" or len(raw) != 1028:
                            raise StageDError("Malformed actual IQD3 S2MM payload")
                        if iq_raw is not None and iq_raw != raw[4:]:
                            raise StageDError("Conflicting duplicate IQD3 payload")
                        iq_raw = raw[4:]
                    elif raw.startswith(b"ACK PASS"):
                        expected = (f"ACK PASS TYPE=DATA SEQ={round_id & 15} IQ=256" if kind == "DATA"
                                    else f"ACK PASS TYPE={kind} META=1").encode()
                        if raw != expected:
                            raise StageDError("ACK content disagrees with the transmitted packet")
                        ack = raw
                    else:
                        raise StageDError("Unrelated payload while waiting for RX validation")
                if kind == "DATA":
                    actual = decode_iq(iq_raw)
            self._pending_packets = []
            self.state = "DRAINING"
            self.status()
            if self.state != "READY" or self.last_status.get("PENDING") != 0:
                raise StageDError("RX did not confirm MODE=0 PENDING=0")
            result = self._result("RX", packets, reference, actual, round_id, self._new_id())
            result["actual_iq_raw"] = iq_raw
            return result
        except Exception as exc:
            return self._fail(exc)

    def disconnect(self):
        try:
            if self.connected and self.protocol_version == 4 and self.state == "READY":
                self._simple(CLOSE)
        finally:
            if self.sock:
                self.sock.close()
            self.sock = None
            self.connected = False
            self.state = "DISCONNECTED"
            self._pending_packets = []
