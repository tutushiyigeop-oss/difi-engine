#!/usr/bin/env python3
"""Offline sanity checks on an AXI DMA Simple Mode transfer plan (NOT hardware probing).

Config is intentionally explicit; do not infer hardware widths, DRE or physical
addresses from an unrelated FPGA project. Exit 0 on no detected issues, 1 on
configuration errors, 2 on absent/incomplete inputs.
"""
import argparse
import json
import sys
from pathlib import Path

REQUIRED = (
    "mode", "mm2s", "s2mm", "cache_line_bytes", "sg_length_width",
    "rx_armed_first", "expected_s2mm_packet_bytes",
)


def to_int(value):
    if isinstance(value, bool):
        raise ValueError("bool is not an integer")
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 0)
    raise ValueError("not an integer")


def power2(n):
    return n > 0 and (n & (n - 1)) == 0


def check(c):
    errors, cautions = [], []
    missing = [k for k in REQUIRED if k not in c]
    if missing:
        return {"verdict": "INCOMPLETE", "errors": [f"missing field: {k}" for k in missing], "cautions": []}
    if c["mode"] != "simple":
        errors.append("template only supports Simple Mode; Scatter-Gather needs separate workflow")
    if c["rx_armed_first"] is not True:
        cautions.append("S2MM is not armed first: safe only if producer cannot emit before RX is ready")
    try:
        cache_line = to_int(c["cache_line_bytes"])
        width = to_int(c["sg_length_width"])
        pkt = to_int(c["expected_s2mm_packet_bytes"])
        if not power2(cache_line) or cache_line < 4:
            errors.append("cache_line_bytes must be power of 2 (e.g., 32 or 64)")
        if not 8 <= width <= 26:
            errors.append("sg_length_width outside expected AXI DMA configuration range 8..26; verify IP")
        if pkt <= 0:
            errors.append("expected_s2mm_packet_bytes must be > 0")
        max_btt = (1 << width) - 1 if 8 <= width <= 26 else None
        regions = []
        for channel in ("mm2s", "s2mm"):
            buf = c[channel]
            for k in ("address", "buffer_bytes", "transfer_bytes", "alignment_bytes", "dre_enabled"):
                if k not in buf:
                    errors.append(f"{channel}.{k} missing")
            if any(k not in buf for k in ("address", "buffer_bytes", "transfer_bytes", "alignment_bytes", "dre_enabled")):
                continue
            addr, capacity, length, align = [to_int(buf[k]) for k in ("address", "buffer_bytes", "transfer_bytes", "alignment_bytes")]
            if not isinstance(buf["dre_enabled"], bool):
                errors.append(f"{channel}.dre_enabled must be true/false")
            if addr < 0 or capacity <= 0 or length <= 0:
                errors.append(f"{channel} buffer address and byte lengths must be valid positive values")
            if length > capacity:
                errors.append(f"{channel} transfer exceeds allocated buffer")
            if max_btt is not None and length > max_btt:
                errors.append(f"{channel} transfer exceeds max BTT {max_btt} from sg_length_width")
            if not power2(align):
                errors.append(f"{channel} alignment_bytes must be a power of 2")
            elif not buf["dre_enabled"] and addr % align:
                errors.append(f"{channel} address not aligned to {align} bytes with DRE disabled")
            if cache_line > 0 and power2(cache_line) and (addr % cache_line or capacity % cache_line):
                cautions.append(f"{channel} cache-line boundaries not isolated; flush/invalidate may affect neighbor data")
            regions.append((channel, addr, addr + capacity))
            if channel == "s2mm" and pkt > length:
                errors.append("S2MM programmed length shorter than expected packet; check TLAST/BTT")
        if len(regions) == 2:
            a, b = regions
            if a[1] < b[2] and b[1] < a[2]:
                errors.append("MM2S/S2MM buffer regions overlap; rejected by conservative independent-buffer policy")
    except (TypeError, ValueError, KeyError) as e:
        errors.append(f"malformed numeric input: {e}")
    return {
        "verdict": "FAIL" if errors else "PASS_WITH_CAUTIONS" if cautions else "PASS_STATIC_ONLY",
        "errors": errors,
        "cautions": cautions,
        "note": "This file does NOT confirm DMA physical address access, clock/reset, AXIS handshake, TLAST or board behavior.",
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("config", type=Path)
    ap.add_argument("--output", type=Path)
    a = ap.parse_args(argv)
    try:
        c = json.loads(a.config.read_text(encoding="utf-8-sig"))
        if not isinstance(c, dict):
            raise ValueError("top-level JSON must be object")
    except (OSError, ValueError) as e:
        ap.error(str(e))
    r = check(c)
    out = json.dumps(r, indent=2, ensure_ascii=False) + "\n"
    print(out, end="")
    if a.output:
        a.output.parent.mkdir(parents=True, exist_ok=True)
        a.output.write_text(out, encoding="utf-8")
    return {"FAIL": 1, "INCOMPLETE": 2}.get(r["verdict"], 0)


if __name__ == "__main__":
    sys.exit(main())
