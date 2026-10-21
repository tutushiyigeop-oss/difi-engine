#!/usr/bin/env python3
"""Pure-Python offline tests; no FPGA tools required."""
import csv
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]

def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

check = load_module(BASE / "scripts" / "axis_trace_check.py", "axis_trace_check")
gen = load_module(BASE / "scripts" / "generate_golden.py", "generate_golden")


def demo_rows():
    # Two packets (3, 2 words), including two consecutive stalls and one gap.
    return [
        dict(cycle=0, aresetn=0, tvalid=0, tready=0, tdata=0, tkeep=0, tlast=0),
        dict(cycle=1, aresetn=1, tvalid=1, tready=0, tdata=11, tkeep=15, tlast=0),
        dict(cycle=2, aresetn=1, tvalid=1, tready=0, tdata=11, tkeep=15, tlast=0),
        dict(cycle=3, aresetn=1, tvalid=1, tready=1, tdata=11, tkeep=15, tlast=0),
        dict(cycle=4, aresetn=1, tvalid=1, tready=1, tdata=12, tkeep=15, tlast=0),
        dict(cycle=5, aresetn=1, tvalid=1, tready=0, tdata=13, tkeep=15, tlast=1),
        dict(cycle=6, aresetn=1, tvalid=1, tready=1, tdata=13, tkeep=15, tlast=1),
        dict(cycle=7, aresetn=1, tvalid=0, tready=1, tdata=0, tkeep=0, tlast=0),
        dict(cycle=8, aresetn=1, tvalid=1, tready=1, tdata=14, tkeep=15, tlast=0),
        dict(cycle=9, aresetn=1, tvalid=1, tready=1, tdata=15, tkeep=3, tlast=1),
    ]

GOLDEN = [(11,15,0),(12,15,0),(13,15,1),(14,15,0),(15,3,1)]
OPTIONS = dict(allow_partial_last=True, min_words=2, max_words=3,
               min_stalled_cycles=2, golden=GOLDEN)

class TestTrace(unittest.TestCase):
    def good(self):
        return check.check_trace(demo_rows(), **OPTIONS)
    def should_fail(self, rows, **overrides):
        opts = {**OPTIONS, **overrides}
        with self.assertRaises(check.TraceError):
            check.check_trace(rows, **opts)
    def test_pass(self):
        r=self.good(); self.assertEqual((r.transfers,r.packets,r.stalled_cycles),(5,2,3))
    def test_drop_valid_while_stalled(self):
        r=demo_rows();r[2]['tvalid']=0;self.should_fail(r)
    def test_data_changes_during_stall(self):
        r=demo_rows();r[2]['tdata']=100;self.should_fail(r)
    def test_keep_changes_during_stall(self):
        r=demo_rows();r[2]['tkeep']=7;self.should_fail(r)
    def test_last_changes_during_stall(self):
        r=demo_rows();r[2]['tlast']=1;self.should_fail(r)
    def test_zero_keep_packet(self):
        r=demo_rows();r[4]['tkeep']=0;self.should_fail(r)
    def test_noncontiguous_keep_packet(self):
        r=demo_rows();r[4]['tkeep']=5;self.should_fail(r)
    def test_partial_not_last(self):
        r=demo_rows();r[4]['tkeep']=3;self.should_fail(r)
    def test_partial_last_rejected_by_default(self):
        self.should_fail(demo_rows(), allow_partial_last=False)
    def test_partial_last_allowed(self): self.good()
    def test_require_packet_min(self):
        self.should_fail(demo_rows(), min_words=4, max_words=5)
    def test_require_packet_max(self):
        self.should_fail(demo_rows(), max_words=2)
    def test_missing_last(self):
        r=demo_rows();r[9]['tlast']=0;self.should_fail(r)
    def test_gold_mismatch(self):
        g=GOLDEN[:];g[1]=(999,15,0);self.should_fail(demo_rows(),golden=g)
    def test_extra_transfer(self):
        g=GOLDEN[:-1];self.should_fail(demo_rows(),golden=g)
    def test_insufficient_golden(self):
        self.should_fail(demo_rows(),golden=GOLDEN + [(99,15,1)])
    def test_cycles_missing(self):
        r=demo_rows();r[4]['cycle']=5;self.should_fail(r)
    def test_invalid_boolean(self):
        r=demo_rows();r[3]['tvalid']=2;self.should_fail(r)
    def test_tkeep_policy_any_allows_holes(self):
        r=demo_rows();r[9]['tkeep']=5
        g=GOLDEN[:-1] + [(15,5,1)]
        x=check.check_trace(r, golden=g, keep_policy='any', min_stalled_cycles=2)
        self.assertEqual(x.transfers,5)
    def test_nonzero_policy_rejects_zero(self):
        r=demo_rows();r[9]['tkeep']=0;self.should_fail(r,keep_policy='nonzero')
    def test_open_final_allowed(self):
        r=demo_rows();r[9]['tlast']=0
        check.check_trace(r, golden=None, require_closed=False, allow_partial_last=True,
                          keep_policy='any')
    def test_stall_coverage(self): self.should_fail(demo_rows(),min_stalled_cycles=10)
    def test_empty(self): self.should_fail([])
    def test_generated_golden(self):
        g=gen.generate_packets([4,4,8]);self.assertEqual(len(g),16)
        self.assertEqual([i for i,x in enumerate(g) if x[2]],[3,7,15])
    def test_generate_validation(self):
        with self.assertRaises(ValueError): gen.generate_packets([4,0])
    def test_fixture_csv_pass(self):
        path=BASE/'tests/fixtures/trace_pass.csv'
        golden=BASE/'tests/fixtures/golden_pass.csv'
        x=check.check_trace(check.load_csv(path,check.REQUIRED),
              golden=check.load_golden(golden),allow_partial_last=True,min_words=2,max_words=3,
              min_stalled_cycles=2)
        self.assertEqual(x.transfers,5)
    def test_fixture_csv_fail(self):
        rows=check.load_csv(BASE/'tests/fixtures/trace_invalid_stall.csv',check.REQUIRED)
        self.should_fail(rows)
    def test_field_parsing_rejects_unknowns(self):
        with self.assertRaises(check.TraceError): check.parse_number('xxxx', 'tdata', 2)

if __name__ == '__main__':
    unittest.main(verbosity=2)
