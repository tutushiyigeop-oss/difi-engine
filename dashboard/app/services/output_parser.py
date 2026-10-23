"""Strict adapters for the unchanged, verified B5/B6 command-line output.

Only complete per-packet PASS lines create packet evidence. In particular, an
expected ACK embedded in a FAIL line can never become a successful packet.
"""

import re

from dashboard.app.models.events import Event

TYPE_NAMES = {5: "VERSION", 4: "CONTEXT", 1: "DATA"}
BYTE_SIZES = {"VERSION": 44, "CONTEXT": 108, "DATA": 1052}
_B5_PACKET = re.compile(
    r"\[PASS\] #(?P<index>\d+) type=(?P<type>\d+) seq=\s*(?P<seq>\d+) "
    r"words=\s*(?P<words>\d+) bytes=\s*(?P<bytes>\d+)")
_B6_META = re.compile(
    r"\[PASS\] (?P<kind>VERSION|CONTEXT)\s+bytes=\s*(?P<bytes>\d+) "
    r"ACK PASS TYPE=(?P<ack_kind>VERSION|CONTEXT) SEQ=(?P<seq>\d+) META=1")
_B6_DATA = re.compile(
    r"\[PASS\] DATA\s+bytes=\s*(?P<bytes>\d+) "
    r"ACK PASS ROUND=(?P<round>\d+) SEQ=(?P<seq>\d+) IQ=256")
_B6_LEGACY_DATA = re.compile(
    r"\[PASS\] round=(?P<round>\d+) seq=(?P<seq>\d+) input=1052B output=1024B IQ=256")


class OutputParser:
    def __init__(self, mode: str, source: str = "LIVE") -> None:
        self.mode = mode.upper()
        if self.mode not in {"B5", "B6"}:
            raise ValueError("mode must be B5 or B6")
        self.source = source.upper()
        self.board_status: dict[str, int] = {}

    def _event(self, kind: str, **data) -> Event:
        return Event(kind=kind, source=self.source, data=data)

    def _error(self, message: str, line: str) -> list[Event]:
        return [self._event("SESSION_ERROR", message=message, raw=line)]

    def _packet(self, line: str, kind: str, identity: str, sequence: int,
                payload_bytes: int, **extra) -> list[Event]:
        if not 0 <= sequence <= 15 or payload_bytes != BYTE_SIZES[kind]:
            return self._error("Malformed PASS: unexpected packet size or sequence", line)
        packet = self._event("PACKET_PASS", packet_id=identity, packet_type=kind,
                             sequence=sequence, payload_bytes=payload_bytes,
                             iq_samples=256 if kind == "DATA" else 0,
                             verified=True, raw=line, **extra)
        if kind == "DATA":
            detail = self._event("IQ_VERIFIED", packet_id=identity, packet_type=kind,
                                 iq_samples=256, mismatches=0,
                                 basis="BOARD_ACK" if self.mode == "B6" else "PC_PAYLOAD")
        else:
            detail = self._event("METADATA_PASS", packet_id=identity, packet_type=kind,
                                 sequence=sequence, observable=True,
                                 basis="BOARD_ACK" if self.mode == "B6" else "PC_PAYLOAD")
        return [packet, detail]

    def _failure(self, line: str) -> list[Event]:
        data: dict = {"message": line.removeprefix("[FAIL]").strip(), "raw": line}
        actual_message = line.split(" (expected ", 1)[0]
        kind_match = re.match(r"\[FAIL\]\s+(version|context|data):", line, re.I)
        index_match = re.search(r"packet\s*#(\d+)", actual_message)
        round_match = re.search(r"(?:Data\s+)?round=(\d+)", actual_message, re.I)
        if kind_match:
            data["packet_type"] = kind_match[1].upper()
        elif index_match:
            index = int(index_match[1])
            data["packet_type"] = "VERSION" if index == 0 else "CONTEXT" if index == 1 else "DATA"
            data["packet_id"] = f"b5:{index}"
        elif round_match:
            data["packet_type"] = "DATA"
        if round_match:
            data["round"] = int(round_match[1])
        # An expected ACK is not evidence of any received sequence.
        seq = re.search(r"\bSEQ=(\d+)", actual_message)
        if seq:
            data["sequence"] = int(seq[1])
        if ("sample=" in actual_message and "!=" in actual_message) or re.search(
                r"\bACK FAIL REASON=IQ_MISMATCH\b", actual_message):
            data["mismatches"] = 1  # One observed mismatch; remaining samples were not checked.
            data["mismatches_are_minimum"] = True
        return [self._event("PACKET_FAIL" if "packet_type" in data else "SESSION_ERROR", **data)]

    def feed(self, line: str) -> list[Event]:
        line = line.strip()
        if not line:
            return []
        if line.startswith("[FAIL]"):
            return self._failure(line)
        if line.startswith("Traceback (most recent call last)"):
            return self._error("The command-line checker raised an exception", line)
        if self.mode == "B5":
            if line.startswith("[INFO] UDP listening on "):
                return [self._event("SESSION_START", phase="PC_LISTENING", raw=line)]
            match = _B5_PACKET.fullmatch(line)
            if match:
                index, type_id, seq, words, size = (int(match[key]) for key in ("index", "type", "seq", "words", "bytes"))
                kind = TYPE_NAMES.get(type_id)
                expected_kind = "VERSION" if index == 0 else "CONTEXT" if index == 1 else "DATA"
                expected_sequence = 0 if index < 2 else (index - 2) % 16
                if kind != expected_kind or words * 4 != size or not 0 <= index < 22 or seq != expected_sequence:
                    return self._error("Malformed B5 PASS: packet type, index, sequence or word count disagrees", line)
                extra = {"index": index}
                if kind == "DATA":
                    extra["round"] = index - 2
                return self._packet(line, kind, f"b5:{index}", seq, size, **extra)
            if line == "[PASS] DIFI UDP full chain: 1 Version + 1 Context + 20 Data, 5120 IQ correct":
                return [self._event("SESSION_COMPLETE", summary=True, raw=line)]
        else:
            if line.startswith("[BOARD]"):
                status = line.removeprefix("[BOARD]").strip()
                if not status.startswith("READY "):
                    return self._error("Board did not return READY; verify the B6 ELF", line)
                values: dict[str, int] = {}
                for part in status.split()[1:]:
                    match = re.fullmatch(r"([A-Z_]+)=(\d+)", part)
                    if match is None or match[1] in values:
                        return self._error("Malformed board STATUS", line)
                    values[match[1]] = int(match[2])
                if not {"NEXT_ROUND", "NEXT_VERSION", "NEXT_CONTEXT"} <= values.keys():
                    return self._error("Board STATUS lacks B6 three-type counters; verify the ELF", line)
                self.board_status = values
                return [self._event("BOARD_READY", **values, ready=True, raw=line)]
            match = _B6_META.fullmatch(line)
            if match:
                kind = match["kind"]
                if kind != match["ack_kind"]:
                    return self._error("B6 PASS packet type disagrees with ACK", line)
                seq = int(match["seq"])
                count = self.board_status.get(f"NEXT_{kind}", seq)
                return self._packet(line, kind, f"b6:{kind.lower()}:{count}", seq,
                                    int(match["bytes"]), board_count=count)
            match = _B6_DATA.fullmatch(line) or _B6_LEGACY_DATA.fullmatch(line)
            if match:
                round_id, seq = int(match["round"]), int(match["seq"])
                if seq != round_id % 16:
                    return self._error("B6 PASS sequence disagrees with acknowledged round", line)
                size = int(match["bytes"]) if "bytes" in match.groupdict() else 1052
                return self._packet(line, "DATA", f"b6:data:{round_id}", seq, size, round=round_id)
            if line == "[PASS] Selected B6 packet types validated by the board" or re.fullmatch(
                    r"\[PASS\] B6 PC -> UDP -> FPGA RX -> DDR: \d+ packets; \d+ IQ validated", line):
                return [self._event("SESSION_COMPLETE", summary=True, raw=line)]
        if line.startswith("[PASS]"):
            return self._error("Unrecognized or malformed PASS output from checker", line)
        return []
