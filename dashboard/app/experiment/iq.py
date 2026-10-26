"""Deterministic, explicitly PC-generated IQ and strict signed sample files."""

import csv
import math
from pathlib import Path
import random
from typing import Iterable

from .profile import decode_iq, encode_iq, strict_int, validate_iq

KINDS = ("complex_sine", "real_sine", "constant", "square", "chirp", "prbs")


def _finite(value, name: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be finite")
    try:
        result = float(value)
    except (ValueError, TypeError, OverflowError) as exc:
        raise ValueError(f"{name} must be finite") from exc
    if not math.isfinite(result):
        raise ValueError(f"{name} must be finite")
    return result


def _quantize(value: float) -> int:
    # Amplitude is validated before generation; rounding cannot silently wrap.
    return max(-32768, min(32767, int(round(value))))


def generate_iq(kind: str, count: int = 256, amplitude: float = 12000,
                frequency: float = 1_000_000, sample_rate: float = 20_000_000,
                phase: float = 0, seed: int = 1, constant_i: int = 0,
                constant_q: int = 0, chirp_end: float | None = None) -> list[tuple[int, int]]:
    """Create a PC reference dataset. Phase is radians; frequencies are Hz.

    A complex sine uses I=A*cos(theta), Q=A*sin(theta). A real sine has Q=0.
    The chirp spans the first through last sample instant. PRBS uses independent
    seeded binary signs for I and Q, each at the requested amplitude.
    """
    if kind not in KINDS:
        raise ValueError(f"Unknown IQ generator: {kind}")
    strict_int(count, "count", 1, 1_000_000)
    amplitude = _finite(amplitude, "amplitude")
    frequency = _finite(frequency, "frequency")
    sample_rate = _finite(sample_rate, "sample_rate")
    phase = _finite(phase, "phase")
    if not 0 <= amplitude <= 32767:
        raise ValueError("amplitude must be in 0..32767")
    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")
    if kind in {"complex_sine", "real_sine", "square", "chirp"} and abs(frequency) > sample_rate / 2:
        raise ValueError("frequency must be within the Nyquist interval ±sample_rate/2")
    strict_int(seed, "seed", 0, 0xFFFFFFFF)
    strict_int(constant_i, "constant_i", -32768, 32767)
    strict_int(constant_q, "constant_q", -32768, 32767)
    end_frequency = frequency if chirp_end is None else _finite(chirp_end, "chirp_end")
    if kind == "chirp" and abs(end_frequency) > sample_rate / 2:
        raise ValueError("chirp_end must be within the Nyquist interval ±sample_rate/2")
    if kind == "constant":
        return [(constant_i, constant_q)] * count
    generator = random.Random(seed)
    if kind == "prbs":
        level = _quantize(amplitude)
        return [(level if generator.getrandbits(1) else -level,
                 level if generator.getrandbits(1) else -level) for _ in range(count)]
    result = []
    cycles_per_sample = frequency / sample_rate
    chirp_delta = (end_frequency / sample_rate - cycles_per_sample) if count > 1 else 0
    for index in range(count):
        cycles = cycles_per_sample * index
        if kind == "chirp" and count > 1:
            cycles += 0.5 * chirp_delta * index * index / (count - 1)
        angle = math.remainder(phase, 2 * math.pi) + 2 * math.pi * cycles
        if kind == "real_sine":
            i, q = amplitude * math.sin(angle), 0
        elif kind == "square":
            i, q = (amplitude if math.cos(angle) >= 0 else -amplitude), 0
        else:
            i, q = amplitude * math.cos(angle), amplitude * math.sin(angle)
        result.append((_quantize(i), _quantize(q)))
    return result


def compare_iq(reference: Iterable[tuple[int, int]], actual: Iterable[tuple[int, int]]) -> dict:
    reference, actual = validate_iq(reference), validate_iq(actual)
    overlap = min(len(reference), len(actual))
    error_i = [actual[index][0] - reference[index][0] for index in range(overlap)]
    error_q = [actual[index][1] - reference[index][1] for index in range(overlap)]
    bad = [index for index in range(overlap) if error_i[index] or error_q[index]]
    missing = abs(len(reference) - len(actual))
    first = bad[0] if bad else overlap if missing else None
    return {"mismatches": len(bad) + missing, "first_mismatch": first,
            "max_abs_error": max([abs(value) for value in error_i + error_q], default=0),
            "error_i": error_i, "error_q": error_q,
            "expected_samples": len(reference), "actual_samples": len(actual),
            "complete": bool(reference) and len(reference) == len(actual),
            "exact": bool(reference) and not bad and not missing}


def _parse_signed(text: str, name: str) -> int:
    try:
        stripped = text.strip()
        if not stripped or any(char not in "+-0123456789" for char in stripped):
            raise ValueError
        number = int(stripped, 10)
    except (ValueError, AttributeError) as exc:
        raise ValueError(f"{name} must be a signed decimal integer") from exc
    return strict_int(number, name, -32768, 32767)


def import_iq_csv(path: str | Path) -> list[tuple[int, int]]:
    """Read I,Q or the original Stage D I_signed16,Q_signed16 CSV columns."""
    with Path(path).open("r", newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        names = reader.fieldnames
        if not names or len(set(names)) != len(names):
            raise ValueError("IQ CSV requires unique I,Q or I_signed16,Q_signed16 headers")
        columns = ("I", "Q") if {"I", "Q"} <= set(names) else ("I_signed16", "Q_signed16")
        if not set(columns) <= set(names):
            raise ValueError("IQ CSV requires I,Q or I_signed16,Q_signed16 headers")
        result = []
        for row_number, row in enumerate(reader, start=2):
            if None in row or any(row.get(key) is None for key in columns):
                raise ValueError(f"Malformed IQ CSV row {row_number}")
            result.append((_parse_signed(row[columns[0]], f"row {row_number} I"),
                           _parse_signed(row[columns[1]], f"row {row_number} Q")))
    if not result:
        raise ValueError("IQ CSV contains no samples")
    return result


def export_iq_csv(path: str | Path, samples: Iterable[tuple[int, int]]) -> None:
    pairs = validate_iq(samples)
    if not pairs:
        raise ValueError("Cannot export an empty IQ dataset")
    with Path(path).open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("I", "Q"))
        writer.writerows(pairs)


def import_iq_bin(path: str | Path, endian: str = "big") -> list[tuple[int, int]]:
    samples = decode_iq(Path(path).read_bytes(), endian)
    if not samples:
        raise ValueError("IQ binary contains no samples")
    return samples


def export_iq_bin(path: str | Path, samples: Iterable[tuple[int, int]], endian: str = "big") -> None:
    raw = encode_iq(samples, endian)
    if not raw:
        raise ValueError("Cannot export an empty IQ dataset")
    Path(path).write_bytes(raw)


load_iq_csv = import_iq_csv
save_iq_csv = export_iq_csv
load_iq_bin = import_iq_bin
save_iq_bin = export_iq_bin
