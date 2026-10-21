#!/usr/bin/env python3
"""Executable offline unittest suite for the two standard-library DMA tools."""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


log = load("dma_log_analyzer.py", "log_tool")
config = load("dma_config_check.py", "config_tool")
EXAMPLE = json.loads((ROOT / "templates/example_transfer_plan.json").read_text(encoding="utf-8"))


class LogAnalysis(unittest.TestCase):
    def test_realistic_difi_log(self):
        s = (ROOT / "tests/fixtures_pass.log").read_text()
        r = log.analyze(s, 25600)
        self.assertEqual(r["verdict"], "PASS_EVIDENCE_ONLY")
        self.assertEqual(r["reported_verified_iq_samples"], [25600])

    def test_injected_timeout_and_error_status(self):
        s = (ROOT / "tests/fixtures_fail.log").read_text()
        r = log.analyze(s)
        self.assertEqual(r["verdict"], "FAIL")
        self.assertTrue(any("DMAIntErr" in z["flags"] for z in r["observed_status_registers"]))
        self.assertTrue(any("Err_Irq" in z["flags"] for z in r["observed_status_registers"]))

    def test_no_result_inconclusive(self):
        s = (ROOT / "tests/fixtures_inconclusive.log").read_text()
        self.assertEqual(log.analyze(s)["verdict"], "INCONCLUSIVE")

    def test_sample_mismatch(self):
        s = "[PASS] dma transfer\n[RESULT] verified_iq_samples=128 iq_mismatches=0\n"
        self.assertEqual(log.analyze(s, 256)["verdict"], "FAIL")

    def test_zero_samples_unrecorded(self):
        self.assertEqual(log.analyze("[PASS] packet complete\n", 0)["verdict"], "INCONCLUSIVE")

    def test_status_error_without_explicit_fail(self):
        self.assertEqual(log.analyze("[INFO] S2MM SR=00000040\n")["verdict"], "FAIL")

    def test_known_good_sr(self):
        r = log.analyze("[INFO] MM2S SR=00001002\n[PASS] completed\n")
        self.assertEqual(r["verdict"], "PASS_EVIDENCE_ONLY")
        self.assertEqual(r["observed_status_registers"][0]["flags"], ["Idle", "IOC_Irq"])


class ConfigCheck(unittest.TestCase):
    def test_example_passes_static_check(self):
        self.assertEqual(config.check(EXAMPLE)["verdict"], "PASS_STATIC_ONLY")

    def test_short_rx_btt(self):
        c = copy.deepcopy(EXAMPLE)
        c["s2mm"]["transfer_bytes"] = 512
        self.assertIn("S2MM programmed length", " ".join(config.check(c)["errors"]))

    def test_btt_exceeds_hw_max(self):
        c = copy.deepcopy(EXAMPLE)
        c["sg_length_width"] = 8
        self.assertIn("exceeds max BTT", " ".join(config.check(c)["errors"]))

    def test_no_dre_bad_alignment(self):
        c = copy.deepcopy(EXAMPLE)
        c["mm2s"]["address"] = "0x11000001"
        self.assertIn("not aligned", " ".join(config.check(c)["errors"]))

    def test_buffer_overlap(self):
        c = copy.deepcopy(EXAMPLE)
        c["s2mm"]["address"] = "0x11000080"
        self.assertIn("overlap", " ".join(config.check(c)["errors"]))

    def test_missing_key_is_incomplete(self):
        c = copy.deepcopy(EXAMPLE)
        del c["mode"]
        self.assertEqual(config.check(c)["verdict"], "INCOMPLETE")

    def test_receive_not_armed_first_caution(self):
        c = copy.deepcopy(EXAMPLE)
        c["rx_armed_first"] = False
        r = config.check(c)
        self.assertEqual(r["verdict"], "PASS_WITH_CAUTIONS")

    def test_cacheline_isolation_caution(self):
        c = copy.deepcopy(EXAMPLE)
        c["mm2s"]["buffer_bytes"] = 1025
        r = config.check(c)
        self.assertIn("cache-line", " ".join(r["cautions"]))

    def test_dre_enabled_allows_unaligned_address(self):
        c = copy.deepcopy(EXAMPLE)
        c["mm2s"]["dre_enabled"] = True
        c["mm2s"]["address"] = "0x11000001"
        r = config.check(c)
        self.assertFalse(any("not aligned" in x for x in r["errors"]))
        self.assertEqual(r["verdict"], "PASS_WITH_CAUTIONS")


if __name__ == "__main__":
    unittest.main(verbosity=2)
