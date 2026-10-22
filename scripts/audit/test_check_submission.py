"""Self-contained unit tests of read-only preflight rules, no FPGA tools."""
import tempfile
from pathlib import Path
import unittest

from check_submission import strip_fenced_code, dead_links, audit


class PreflightTests(unittest.TestCase):
    def test_fenced_example_is_not_real_link(self):
        raw = """Real [ok](good.md)\n```markdown\n[example](not-here.md)\n```\n"""
        x = strip_fenced_code(raw)
        self.assertIn("(good.md)", x)
        self.assertNotIn("not-here.md", x)

    def test_actual_missing_link(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "readme.md").write_text("[bad](missing.md)\n```\n[fake](also-missing.md)\n```", encoding="utf-8")
            self.assertEqual(len(dead_links(p, "readme.md")), 1)

    def test_old_skill_index_and_license_detected(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "README.md").write_text("未提交可自动重建这两套完整", encoding="utf-8")
            (p / "skill").mkdir()
            (p / "skill/README.md").write_text("## 后续规划（尚未制作", encoding="utf-8")
            d = audit(p)
            ids = {i["id"] for i in d["issues"]}
            self.assertTrue({"license", "stale-root-readme", "stale-skill-index"} <= ids)

    def test_nominal_markdown_file(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "README.md").write_text("[working](A.md)", encoding="utf-8")
            (p / "A.md").write_text("OK", encoding="utf-8")
            self.assertEqual(dead_links(p, "README.md"), [])


if __name__ == "__main__":
    unittest.main()
