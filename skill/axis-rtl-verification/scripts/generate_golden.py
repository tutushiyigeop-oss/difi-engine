#!/usr/bin/env python3
"""Generate an example byte-aligned packet golden CSV (deterministic, not DIFI)."""
import argparse
import csv
from pathlib import Path


def generate_packets(lengths, last_keep=0xF):
    if not lengths or any(n < 1 for n in lengths):
        raise ValueError("packet lengths must be positive")
    if last_keep not in (1, 3, 7, 15):
        raise ValueError("last_keep must be 1, 3, 7, or 15 for this 32-bit packet profile")
    result = []
    idx = 0
    for length in lengths:
        for word_idx in range(length):
            final = word_idx == length - 1
            result.append((0x1BADC0DE ^ (idx * 0x00010003),
                           last_keep if final else 0xF,
                           int(final)))
            idx += 1
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet-words", required=True, help="Comma-separated positive packet lengths: 4,4,8")
    parser.add_argument("--last-keep", type=lambda s: int(s, 0), default=0xF)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        lengths = [int(x) for x in args.packet_words.split(",")]
        beats = generate_packets(lengths, args.last_keep)
    except ValueError as exc:
        parser.error(str(exc))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["data", "keep", "last"])
        for data, keep, last in beats:
            writer.writerow([f"0x{data:08X}", f"0x{keep:X}", last])
    print(f"[PASS] wrote {len(beats)} beats, {len(lengths)} packets: {args.out}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
