#!/usr/bin/env python3
"""Offline Zynq AXI DMA UART-log triage. Stdlib only; never touches hardware.

Exit: 0 = no failure evidence and explicit success evidence, 1 = failure evidence,
      2 = inconclusive/insufficient evidence. Not a substitute for hardware testing.
"""
import argparse
import json
import re
import sys
from pathlib import Path

# AXI DMA PG021 v7.1, MM2S_DMASR / S2MM_DMASR common bits.
BITS = {
    0: "Halted", 1: "Idle", 3: "SGIncld", 4: "DMAIntErr",
    5: "DMASlvErr", 6: "DMADecErr", 8: "SGIntErr",
    9: "SGSlvErr", 10: "SGDecErr", 12: "IOC_Irq",
    13: "Dly_Irq", 14: "Err_Irq",
}
HARD_ERROR_BITS = {4, 5, 6, 8, 9, 10, 14}
REGEX = re.compile(r"(?i)\b(?:(?P<label>MM2S|S2MM|DMA)[^\n]{0,110}?)?\b(?:status|sr)\s*=\s*(?:0x)?(?P<hex>[0-9a-fA-F]{1,8})\b")
SAMPLE_RE = re.compile(r"\bverified_iq_samples\s*=\s*(\d+)\b", re.I)
PASS_PATTERNS = [
    re.compile(r"\[PASS\]", re.I),
    re.compile(r"\[ALL PACKAGED-IP LOOPBACK TESTS PASSED\]", re.I),
    re.compile(r"\[RESULT\].*?iq_mismatches\s*=\s*0\b", re.I),
]
FAIL_RE = re.compile(r"\[FAIL\]|\bDMA\s+timeout\b|\bDMA\s+error\b", re.I)


def analyze(contents: str, expected_samples=None):
    statuses, flags, successes, samples = [], [], [], []
    for idx, line in enumerate(contents.splitlines(), 1):
        if FAIL_RE.search(line):
            flags.append({"line": idx, "reason": "explicit failure/timeout", "text": line.strip()[:240]})
        if any(p.search(line) for p in PASS_PATTERNS):
            successes.append(idx)
        for found in SAMPLE_RE.finditer(line):
            samples.append(int(found.group(1)))
        for found in REGEX.finditer(line):
            value = int(found.group("hex"), 16)
            set_bits = [name for bit, name in BITS.items() if value & (1 << bit)]
            label = (found.group("label") or "unknown").upper()
            statuses.append({"line": idx, "channel": label, "hex": f"0x{value:08X}", "flags": set_bits})
            if any(value & (1 << bit) for bit in HARD_ERROR_BITS):
                flags.append({"line": idx, "reason": "AXI DMA status error/Err_Irq bit set", "text": line.strip()[:240]})
    if expected_samples is not None and samples and samples[-1] != expected_samples:
        flags.append({"line": None, "reason": f"expected {expected_samples} IQ samples; observed {samples[-1]}", "text": ""})
    if flags:
        verdict = "FAIL"
    elif successes and (expected_samples is None or samples and samples[-1] == expected_samples):
        verdict = "PASS_EVIDENCE_ONLY"
    else:
        verdict = "INCONCLUSIVE"
    return {
        "verdict": verdict,
        "note": "Offline log evidence only; not a test of TLAST wiring, cache coherence or hardware correctness.",
        "observed_status_registers": statuses,
        "failures": flags,
        "pass_evidence_lines": successes,
        "reported_verified_iq_samples": samples,
        "follow_up": (
            ["Inspect both MM2S_DMASR and S2MM_DMASR; check TLAST, byte counts and PS cache maintenance."]
            if verdict == "FAIL" else
            ["Inspect raw UART/test artifacts and independently compare payload data before claiming board PASS."]
        ),
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", type=Path, help="Decoded UART text log (UTF-8 preferred)")
    ap.add_argument("--expected-samples", type=int, help="Expected 'verified_iq_samples' count")
    ap.add_argument("--output", type=Path, help="Write JSON report to this path")
    ns = ap.parse_args(argv)
    if ns.expected_samples is not None and ns.expected_samples < 0:
        ap.error("--expected-samples must be non-negative")
    try:
        content = ns.log.read_text(encoding="utf-8-sig", errors="replace")
    except OSError as e:
        ap.error(str(e))
    r = analyze(content, ns.expected_samples)
    out = json.dumps(r, indent=2, ensure_ascii=False) + "\n"
    print(out, end="")
    if ns.output:
        ns.output.parent.mkdir(parents=True, exist_ok=True)
        ns.output.write_text(out, encoding="utf-8")
    return {"PASS_EVIDENCE_ONLY": 0, "FAIL": 1, "INCONCLUSIVE": 2}[r["verdict"]]


if __name__ == "__main__":
    sys.exit(main())
