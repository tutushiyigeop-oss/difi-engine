"""Decode B5 length-prefixed captures after the original checker accepts them."""

from functools import lru_cache
import importlib.util
from pathlib import Path
import struct
from typing import Callable


@lru_cache(maxsize=1)
def _original_checker() -> Callable:
    path = Path(__file__).resolve().parents[3] / "scripts/verify/tools/difi_udp_receiver.py"
    spec = importlib.util.spec_from_file_location("_dashboard_original_b5_checker", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load the original B5 checker: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.check_packet


def decode_iq(payload: bytes) -> tuple[list[int], list[int]]:
    """Return signed I16/Q16 pairs from a complete, network-order Data payload.

    This helper checks framing only. decode_capture additionally validates the
    complete packet and Golden pattern using the existing acceptance checker.
    """
    if len(payload) != 1052:
        raise ValueError("A DIFI Data payload must contain 7 header words and 256 IQ pairs")
    header = int.from_bytes(payload[:4], "big")
    if header >> 28 != 1 or header & 0xFFFF != 263:
        raise ValueError("Invalid Data packet header")
    pairs = list(struct.iter_unpack("!hh", payload[28:]))
    return [pair[0] for pair in pairs], [pair[1] for pair in pairs]


def decode_capture(path: str | Path, *, limit: int | None = None) -> list[dict]:
    """Read the receiver's .bin format (32-bit BE length + UDP payload).

    Complete partial captures are useful after a timeout and are accepted. The
    optional limit bounds an in-progress snapshot to already confirmed packets;
    callers can retry if the receiver has not flushed its capture buffer yet.
    A truncated frame, bad protocol field or incorrect IQ pattern raises rather
    than displaying unverified bytes as accepted FPGA output.
    """
    records = []
    if limit is not None and limit < 0:
        raise ValueError("Capture packet limit cannot be negative")
    checker = _original_checker()
    with Path(path).open("rb") as stream:
        while limit is None or len(records) < limit:
            prefix = stream.read(4)
            if not prefix:
                return records
            if len(prefix) != 4:
                raise ValueError("Truncated 32-bit network-order capture length prefix")
            length, = struct.unpack("!I", prefix)
            if length == 0 or length > 65507:
                raise ValueError(f"Invalid UDP payload length {length}")
            payload = stream.read(length)
            if len(payload) != length:
                raise ValueError(f"Truncated capture payload: expected {length}, got {len(payload)}")
            index = len(records)
            type_id, sequence, words, size = checker(payload, index)
            kind = {5: "VERSION", 4: "CONTEXT", 1: "DATA"}[type_id]
            i_values, q_values = decode_iq(payload) if type_id == 1 else ([], [])
            record = {"packet_id": f"b5:{index}", "index": index, "packet_type": kind,
                      "sequence": sequence, "payload_bytes": size, "words": words,
                      "i": i_values, "q": q_values, "verified": True,
                      "iq_samples": len(i_values)}
            if type_id == 1:
                record["round"] = index - 2
            records.append(record)
    return records
