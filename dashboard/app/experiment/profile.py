"""The frozen RTL's restricted DIFI profile and network-order packet codec.

Validation follows rtl/include/difi_v1_1_defs.vh and the three frozen parsers.
This codec validates arbitrary signed IQ; it does not assume a Golden pattern.
"""

from dataclasses import asdict, dataclass, fields as dataclass_fields
import struct
from typing import Any, Iterable

UINT32_MAX = 0xFFFFFFFF
MAX_RF_HZ = 100_000_000_000
PS_PER_SECOND = 1_000_000_000_000
OUI_WORD = 0x006A621E
CONFIG_STRUCT = struct.Struct("!IIIIIQIII")
_KINDS = {"DATA": 1, "CONTEXT": 4, "VERSION": 5}
_CLASS = {"DATA": 0, "CONTEXT": 1, "VERSION": 0x00010004}


def strict_int(value: Any, name: str, low: int, high: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError(f"{name} must be an integer in {low}..{high}")
    return value


@dataclass
class ProfileConfig:
    data_sid: int = 1
    version_sid: int = 2
    samples: int = 256
    sample_rate: int = 20_000_000
    bandwidth: int = 10_000_000
    rf_hz: int = 100_000_000
    rx_filter: int = 3
    rx_data_sid: int = 1
    rx_version_sid: int = 2

    def validate(self) -> "ProfileConfig":
        for name in ("data_sid", "version_sid", "rx_data_sid", "rx_version_sid"):
            strict_int(getattr(self, name), name, 0, UINT32_MAX)
        strict_int(self.samples, "samples", 1, 256)
        strict_int(self.sample_rate, "sample_rate", 1, UINT32_MAX)
        strict_int(self.bandwidth, "bandwidth", 1, self.sample_rate)
        strict_int(self.rf_hz, "rf_hz", 0, MAX_RF_HZ)
        strict_int(self.rx_filter, "rx_filter", 0, 3)
        return self

    def to_dict(self) -> dict[str, int]:
        return asdict(self)

    @classmethod
    def from_dict(cls, values: dict[str, Any]) -> "ProfileConfig":
        if not isinstance(values, dict):
            raise ValueError("Profile configuration must be a JSON object")
        unknown = set(values) - {field.name for field in dataclass_fields(cls)}
        if unknown:
            raise ValueError(f"Unknown profile fields: {', '.join(sorted(unknown))}")
        return cls(**values).validate()


def encode_config(config: ProfileConfig) -> bytes:
    config.validate()
    return CONFIG_STRUCT.pack(*(getattr(config, field.name) for field in dataclass_fields(config)))


def decode_config(raw: bytes) -> ProfileConfig:
    if len(raw) != CONFIG_STRUCT.size:
        raise ValueError("Profile configuration must contain exactly 40 network-order bytes")
    return ProfileConfig(*CONFIG_STRUCT.unpack(raw)).validate()


def _byte_order(endian: str) -> str:
    if endian not in {"big", "little"}:
        raise ValueError("IQ byte order must be 'big' or 'little'")
    return "!" if endian == "big" else "<"


def validate_iq(samples: Iterable[tuple[int, int]]) -> list[tuple[int, int]]:
    result = []
    for index, pair in enumerate(samples):
        if not isinstance(pair, (tuple, list)) or len(pair) != 2:
            raise ValueError(f"IQ sample {index} must be an (I, Q) pair")
        i, q = pair
        strict_int(i, f"I[{index}]", -32768, 32767)
        strict_int(q, f"Q[{index}]", -32768, 32767)
        result.append((i, q))
    return result


def encode_iq(samples: Iterable[tuple[int, int]], endian: str = "big") -> bytes:
    order = _byte_order(endian)
    pairs = validate_iq(samples)
    return b"".join(struct.pack(order + "hh", i, q) for i, q in pairs)


def decode_iq(raw: bytes, endian: str = "big") -> list[tuple[int, int]]:
    order = _byte_order(endian)
    if len(raw) % 4:
        raise ValueError("IQ binary must contain complete signed I16/Q16 pairs (4 bytes per sample)")
    return list(struct.iter_unpack(order + "hh", raw))


def _pack(words: list[int]) -> bytes:
    return struct.pack(f"!{len(words)}I", *words)


def build_packet(kind: str, config: ProfileConfig, iq: list[tuple[int, int]] | None = None,
                 sequence: int = 0, seconds: int = 1_700_000_000,
                 picoseconds: int = 0, changed: bool = True) -> bytes:
    config.validate()
    kind = str(kind).upper()
    if kind not in _KINDS:
        raise ValueError("Packet kind must be VERSION, CONTEXT or DATA")
    strict_int(sequence, "sequence", 0, 15)
    strict_int(seconds, "seconds", 0, UINT32_MAX)
    strict_int(picoseconds, "picoseconds", 0, PS_PER_SECOND - 1)
    if not isinstance(changed, bool):
        raise ValueError("changed must be boolean")
    count = config.samples + 7 if kind == "DATA" else 27 if kind == "CONTEXT" else 11
    header = (_KINDS[kind] << 28) | 0x08600000 | (sequence << 16) | count
    if kind != "DATA":
        header |= 0x01000000
    sid = config.version_sid if kind == "VERSION" else config.data_sid
    words = [header, sid, OUI_WORD, _CLASS[kind], seconds, picoseconds >> 32, picoseconds & UINT32_MAX]
    if kind == "DATA":
        if iq is None:
            raise ValueError("DATA requires explicit IQ samples with a known source")
        pairs = validate_iq(iq)
        if len(pairs) != config.samples:
            raise ValueError(f"Expected {config.samples} IQ samples, got {len(pairs)}")
        return _pack(words) + encode_iq(pairs)
    if iq is not None:
        raise ValueError("Metadata packets cannot contain IQ payloads")
    if kind == "VERSION":
        # Default module parameters: year offset 26, day 252; revision 1/type 0/ICD 0.
        words.extend([0x80000002 if changed else 2, 12, 4, (26 << 25) | (252 << 16) | (1 << 10)])
    else:
        words.extend([0] * 20)
        words[7], words[8] = 0xFBB98000 if changed else 0x7BB98000, 100
        for index, value in ((9, config.bandwidth), (13, config.rf_hz), (19, config.sample_rate)):
            fixed = value << 20
            words[index], words[index + 1] = fixed >> 32, fixed & UINT32_MAX
        words[25], words[26] = 0xA00003CF, 0
    return _pack(words)


def parse_packet(raw: bytes, config: ProfileConfig | None = None) -> dict[str, Any]:
    """Validate a complete packet and return fields for inspectors and exports.

    With config supplied, RX SID filters are enforced. Valid RX Context values
    are independent of configured TX frequencies, just as in the frozen RTL.
    A valid DATA size can differ from configured TX samples; the RTL
    accepts any 1..256 samples, and a separate readable flag records that fact.
    Sequence continuity is a session property and is not inferred from a packet.
    """
    if config is not None:
        config.validate()
    if len(raw) < 28 or len(raw) % 4:
        raise ValueError("DIFI payload must be a complete array of network-order 32-bit words")
    words = list(struct.unpack(f"!{len(raw) // 4}I", raw))
    header, sid, oui, class_word, seconds, ps_high, ps_low = words[:7]
    kind = {value: key for key, value in _KINDS.items()}.get(header >> 28)
    if kind is None:
        raise ValueError("Unsupported DIFI packet type")
    sequence = (header >> 16) & 15
    expected_count = len(words) if kind == "DATA" else 27 if kind == "CONTEXT" else 11
    if len(words) != expected_count or (kind == "DATA" and not 8 <= len(words) <= 263):
        raise ValueError("Packet length is outside the frozen profile")
    expected_header = (_KINDS[kind] << 28) | 0x08600000 | (sequence << 16) | expected_count
    if kind != "DATA":
        expected_header |= 0x01000000
    if header != expected_header:
        raise ValueError("Word 0 flags, reserved bits or declared packet length differ from the frozen profile")
    if oui != OUI_WORD or class_word != _CLASS[kind]:
        raise ValueError("DIFI OUI or Class ID mismatch")
    ps = (ps_high << 32) | ps_low
    if ps >= PS_PER_SECOND:
        raise ValueError("Fractional timestamp must be less than one second (10^12 picoseconds)")
    if config is not None:
        mask = 2 if kind == "VERSION" else 1
        expected_sid = config.rx_version_sid if kind == "VERSION" else config.rx_data_sid
        if config.rx_filter & mask and sid != expected_sid:
            raise ValueError(f"{kind} Stream ID {sid} rejected by enabled RX filter ({expected_sid})")
    readable: dict[str, Any] = {
        "oui": f"0x{oui:08X}", "class_id": f"0x{class_word:08X}",
        "timestamp_format": "UTC seconds + realtime picoseconds", "word_count": len(words),
    }
    descriptions = ["DIFI header: type / class-present / UTC+picoseconds / sequence / word count",
                    "Stream ID", "Class ID OUI (0x006A621E)", "Information Class / Packet Class",
                    "UTC integer seconds", "Fractional timestamp picoseconds [63:32]",
                    "Fractional timestamp picoseconds [31:0]"]
    pairs: list[tuple[int, int]] = []
    if kind == "DATA":
        pairs = decode_iq(raw[28:])
        readable["sample_count"] = len(pairs)
        if config is not None:
            readable["sample_count_matches_profile"] = len(pairs) == config.samples
        descriptions.extend(f"IQ sample {index}: signed I16 in bits 31:16, Q16 in bits 15:0" for index in range(len(pairs)))
    elif kind == "VERSION":
        if words[7] not in {0x80000002, 2} or words[8] != 12 or words[9] != 4:
            raise ValueError("Version CIF0/CIF1/V49 specification word mismatch")
        info = words[10]
        day, revision, version_type, icd = (info >> 16) & 511, (info >> 10) & 63, (info >> 6) & 15, info & 63
        if not 1 <= day <= 366 or revision != 1 or version_type != 0 or icd != 0:
            raise ValueError("Version information violates build-day/revision/type/ICD constraints")
        readable.update(changed=bool(words[7] >> 31), build_year=2000 + (info >> 25),
                        build_day=day, revision=revision, version_type=version_type, icd_version=icd,
                        v49_specification=words[9])
        descriptions.extend(["Version CIF0 / changed flag", "Version CIF1", "V49 specification version",
                             "Build year offset / day / revision / type / ICD version"])
    else:
        if words[7] not in {0xFBB98000, 0x7BB98000} or words[8] != 100:
            raise ValueError("Context CIF0 or Reference Point mismatch")
        if words[25:27] != [0xA00003CF, 0]:
            raise ValueError("Context Data Packet Payload Format must be frozen complex I16/Q16")
        for index in (11, 12, 15, 16, 17, 18, 21, 22, 23, 24):
            if words[index] != 0:
                raise ValueError(f"Context reserved word {index} must be zero")
        frequencies = {}
        for name, index in (("bandwidth", 9), ("rf_hz", 13), ("sample_rate", 19)):
            fixed = (words[index] << 32) | words[index + 1]
            if fixed & ((1 << 20) - 1):
                raise ValueError(f"Context {name} fractional-Hz bits must be zero")
            frequencies[name] = fixed >> 20
        fs, bandwidth, rf = frequencies["sample_rate"], frequencies["bandwidth"], frequencies["rf_hz"]
        if not 0 < bandwidth <= fs <= UINT32_MAX or not 0 <= rf <= MAX_RF_HZ:
            raise ValueError("Context frequency values are outside the frozen parser constraints")
        readable.update(frequencies, changed=bool(words[7] >> 31), reference_point=100,
                        payload_format="Complex Cartesian I16/Q16, 32 bits per IQ pair")
        descriptions.extend(["Context CIF0 / changed flag", "Reference point", "Bandwidth Q44.20 [63:32]",
                             "Bandwidth Q44.20 [31:0]", "Reserved (zero)", "Reserved (zero)",
                             "RF frequency Q44.20 [63:32]", "RF frequency Q44.20 [31:0]",
                             "Reserved (zero)", "Reserved (zero)", "Reserved (zero)", "Reserved (zero)",
                             "Sample rate Q44.20 [63:32]", "Sample rate Q44.20 [31:0]",
                             "Reserved (zero)", "Reserved (zero)", "Reserved (zero)", "Reserved (zero)",
                             "Data Packet Payload Format word 0", "Data Packet Payload Format word 1"])
    return {"packet_type": kind, "sequence": sequence, "payload_bytes": len(raw),
            "samples": len(pairs), "stream_id": sid, "seconds": seconds, "picoseconds": ps,
            "words": words, "iq": pairs, "fields": readable, "word_descriptions": descriptions,
            "raw_hex": raw.hex()}
