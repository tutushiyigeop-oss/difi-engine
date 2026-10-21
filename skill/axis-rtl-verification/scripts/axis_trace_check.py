#!/usr/bin/env python3
"""Check cycle-by-cycle AXI4-Stream CSV traces and optional golden transfers.

Pure stdlib; a trace is a sampled *one-channel* interface, not a full RTL proof.
Sample TDATA/TKEEP/TLAST only on TVALID && TREADY. Stall retention is
checked from each stalled cycle to the following active cycle.
"""
from __future__ import annotations
import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

REQUIRED = {"cycle", "aresetn", "tvalid", "tready", "tdata", "tkeep", "tlast"}
GOLDEN = {"data", "keep", "last"}

class TraceError(ValueError):
    pass


def parse_number(value: str, field: str, line: int) -> int:
    v = str(value).strip()
    if not v or any(x in v.lower() for x in ("x", "z", "?")) and not v.lower().startswith("0x"):
        raise TraceError(f"row {line}: {field} missing or contains X/Z: {value!r}")
    try:
        result = int(v, 0)
    except ValueError as ex:
        raise TraceError(f"row {line}: {field} must be 0x... hex or decimal: {value!r}") from ex
    if result < 0:
        raise TraceError(f"row {line}: {field} cannot be negative")
    return result


def load_csv(path: Path, required: set[str]):
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise TraceError(f"{path}: CSV has no header")
        missing = required - set(reader.fieldnames)
        if missing:
            raise TraceError(f"{path}: missing columns: {', '.join(sorted(missing))}")
        rows = []
        for rownum, raw in enumerate(reader, start=2):
            if not any(str(v).strip() for v in raw.values() if v is not None):
                continue
            rows.append({name: parse_number(raw[name], name, rownum) for name in required})
        return rows


def valid_keep(keep: int, keep_width: int) -> bool:
    # Contiguous valid bytes beginning with byte lane 0: 0b0001, 0b0011, ...
    return 0 < keep < (1 << keep_width) and (keep & (keep + 1)) == 0

@dataclass
class CheckResult:
    cycles: int
    transfers: int
    packets: int
    stalled_cycles: int


def check_trace(rows, *, data_width=32, keep_width=4, allow_partial_last=False,
                require_closed=True, min_words=None, max_words=None,
                min_stalled_cycles=0, min_transfers=1, golden=None,
                keep_policy="packet") -> CheckResult:
    if keep_policy not in ("packet", "nonzero", "any"):
        raise TraceError("keep_policy must be packet/nonzero/any")
    if data_width <= 0 or keep_width <= 0 or data_width != keep_width * 8:
        raise TraceError("data_width must equal keep_width * 8 (byte lanes)")
    if min_words is not None and min_words < 1:
        raise TraceError("min_words must be at least 1")
    if max_words is not None and max_words < 1:
        raise TraceError("max_words must be at least 1")
    if min_words is not None and max_words is not None and min_words > max_words:
        raise TraceError("min_words cannot exceed max_words")
    if min_stalled_cycles < 0 or min_transfers < 0:
        raise TraceError("minimum coverage values must be nonnegative")
    if not rows:
        raise TraceError("trace is empty")
    previous_cycle = -1
    stalled = None
    transfers = 0
    packets = 0
    stalled_cycles = 0
    packet_words = 0
    full_keep = (1 << keep_width) - 1
    for row in rows:
        cycle = row["cycle"]
        if cycle <= previous_cycle:
            raise TraceError(f"cycle {cycle}: cycle indices must increase")
        if previous_cycle >= 0 and cycle != previous_cycle + 1:
            raise TraceError(f"cycle {cycle}: missing sampled clock cycles; cannot prove stall stability")
        previous_cycle = cycle
        for key in ("aresetn", "tvalid", "tready", "tlast"):
            if row[key] not in (0, 1):
                raise TraceError(f"cycle {cycle}: {key} must be exactly 0 or 1")
        if row["tdata"] >= (1 << data_width) or row["tkeep"] >= (1 << keep_width):
            raise TraceError(f"cycle {cycle}: TDATA/TKEEP exceeds configured width")
        if row["aresetn"] == 0:
            stalled = None
            if packet_words:
                # Reset aborts an in-progress packet; do not count it as valid.
                packet_words = 0
            continue
        if stalled is not None:
            current = (row["tdata"], row["tkeep"], row["tlast"])
            if row["tvalid"] != 1 or current != stalled:
                raise TraceError(f"cycle {cycle}: stalled beat changed or TVALID dropped before handshake")
        if row["tvalid"]:
            keep = row["tkeep"]
            if keep_policy == "packet":
                if not valid_keep(keep, keep_width):
                    raise TraceError(f"cycle {cycle}: packet-profile TKEEP must be a nonzero contiguous mask from lane 0")
                if keep != full_keep and not (allow_partial_last and row["tlast"]):
                    raise TraceError(f"cycle {cycle}: packet-profile partial TKEEP not permitted here")
            elif keep_policy == "nonzero" and keep == 0:
                raise TraceError(f"cycle {cycle}: TKEEP must be nonzero under nonzero policy")
        stalled = None
        if row["tvalid"] and not row["tready"]:
            stalled = (row["tdata"], row["tkeep"], row["tlast"])
            stalled_cycles += 1
        if row["tvalid"] and row["tready"]:
            if golden is not None:
                if transfers >= len(golden):
                    raise TraceError(f"cycle {cycle}: unexpected extra transfer at index {transfers}")
                expected = golden[transfers]
                actual = (row["tdata"], row["tkeep"], row["tlast"])
                if actual != expected:
                    raise TraceError(f"cycle {cycle}: golden mismatch at transfer {transfers}: actual={actual} expected={expected}")
            transfers += 1
            packet_words += 1
            if row["tlast"]:
                if min_words is not None and packet_words < min_words:
                    raise TraceError(f"cycle {cycle}: packet has {packet_words} beats (< {min_words})")
                if max_words is not None and packet_words > max_words:
                    raise TraceError(f"cycle {cycle}: packet has {packet_words} beats (> {max_words})")
                packets += 1
                packet_words = 0
            elif max_words is not None and packet_words >= max_words:
                raise TraceError(f"cycle {cycle}: packet exceeded {max_words} beats without TLAST")
    if stalled is not None:
        raise TraceError("trace ended during output stall; cannot prove handshake completion")
    if require_closed and packet_words:
        raise TraceError(f"trace ended with {packet_words} transfer(s) lacking TLAST")
    if transfers < min_transfers:
        raise TraceError(f"insufficient transfers: {transfers} < {min_transfers}")
    if stalled_cycles < min_stalled_cycles:
        raise TraceError(f"insufficient stalled cycles: {stalled_cycles} < {min_stalled_cycles}")
    if golden is not None and transfers != len(golden):
        raise TraceError(f"missing golden transfers: {transfers} observed, {len(golden)} expected")
    return CheckResult(len(rows), transfers, packets, stalled_cycles)


def load_golden(path: Path):
    rows = load_csv(path, GOLDEN)
    for i, r in enumerate(rows):
        if r["last"] not in (0, 1):
            raise TraceError(f"golden beat {i}: last must be 0 or 1")
    return [(r["data"], r["keep"], r["last"]) for r in rows]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("trace", type=Path, help="Clock-sampled AXIS trace CSV")
    ap.add_argument("--golden", type=Path, help="Expected accepted beat sequence CSV")
    ap.add_argument("--data-width", type=int, default=32)
    ap.add_argument("--keep-width", type=int, default=4)
    ap.add_argument("--keep-policy", choices=["packet", "nonzero", "any"], default="packet",
                    help="packet is a project-specific stricter profile, not a universal AXIS rule")
    ap.add_argument("--allow-partial-last", action="store_true")
    ap.add_argument("--allow-open-final-packet", action="store_true")
    ap.add_argument("--min-words", type=int)
    ap.add_argument("--max-words", type=int)
    ap.add_argument("--min-stalled-cycles", type=int, default=0)
    ap.add_argument("--min-transfers", type=int, default=1)
    args = ap.parse_args(argv)
    try:
        result = check_trace(load_csv(args.trace, REQUIRED),
          golden=load_golden(args.golden) if args.golden else None,
          data_width=args.data_width, keep_width=args.keep_width,
          allow_partial_last=args.allow_partial_last,
          require_closed=not args.allow_open_final_packet,
          min_words=args.min_words, max_words=args.max_words,
          min_stalled_cycles=args.min_stalled_cycles,
          min_transfers=args.min_transfers, keep_policy=args.keep_policy)
    except (TraceError, OSError) as exc:
        print(f"[FAIL] {exc}")
        return 1
    print(f"[PASS] cycles={result.cycles} transfers={result.transfers} packets={result.packets} stalled_cycles={result.stalled_cycles}")
    print("[NOTE] Cycle-level protocol/scoreboard checks only; not an RTL formal proof or coverage closure.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
