#!/usr/bin/env python3
"""Optional real RTL regression; requires iverilog and vvp installed on PATH."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "templates" / "tb_axis_register_slice.v"
GOOD = ROOT / "templates" / "axis_register_slice.v"
BAD = ROOT / "tests" / "mutants" / "axis_register_slice_buggy.v"
TRACE_TOOL = ROOT / "scripts" / "axis_trace_check.py"
GOLDEN_TOOL = ROOT / "scripts" / "generate_golden.py"


def run(cmd):
    r = subprocess.run([str(c) for c in cmd], text=True, capture_output=True)
    return r.returncode, r.stdout + r.stderr


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--require-tools", action="store_true", help="Fail instead of skip if Icarus is missing")
    args = ap.parse_args()
    if not shutil.which("iverilog") or not shutil.which("vvp"):
        print("[SKIP] Icarus Verilog iverilog/vvp missing; REAL RTL tests NOT executed")
        return 1 if args.require_tools else 0
    with tempfile.TemporaryDirectory(prefix="axis-skill-") as td:
        out = Path(td)
        expected = out / "golden.csv"
        rc, log = run([sys.executable, GOLDEN_TOOL, "--packet-words", "4,4,8", "--out", expected])
        if rc:
            print(log); return 1
        # For the correct DUT, the generated golden uses full TKEEP while
        # the TB intentionally emits partial final two packets. Make a local
        # precisely matched golden with the two partial endings.
        lines = expected.read_text(encoding="utf8").splitlines()
        for i, keep in ((8, "0x3"), (16, "0x7")):
            parts = lines[i].split(",")
            parts[1] = keep
            lines[i] = ",".join(parts)
        expected.write_text("\n".join(lines) + "\n", encoding="utf8")
        for label, dut, expect_ok in [("correct", GOOD, True), ("mutant", BAD, False)]:
            sim = out / (label + ".vvp")
            trace = out / (label + ".csv")
            rc, log = run(["iverilog", "-g2012", "-s", "tb_axis_register_slice",
                           "-o", sim, dut, TB])
            if rc:
                print(f"[FAIL] compile {label}:\n{log}"); return 1
            rc, log = run(["vvp", sim, f"+trace={trace}"])
            if expect_ok:
                if rc or "[PASS] tb_axis_register_slice" not in log:
                    print(f"[FAIL] expected good DUT PASS:\n{log}"); return 1
                rc, check_log = run([sys.executable, TRACE_TOOL, trace,
                  "--golden", expected, "--allow-partial-last", "--min-words", "4",
                  "--max-words", "8", "--min-stalled-cycles", "3"])
                if rc:
                    print(f"[FAIL] offline checker rejected good DUT:\n{check_log}"); return 1
                print("[PASS] good RTL, TB scoreboard and independent CSV checker")
            else:
                if rc == 0 or ("AXIS output changed while stalled" not in log and "Scoreboard mismatch" not in log):
                    print(f"[FAIL] mutant unexpectedly survived:\n{log}"); return 1
                print("[PASS] faulty RTL detected by TB (expected failure)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
