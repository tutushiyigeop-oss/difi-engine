#!/usr/bin/env python3
"""Read-only DIFI/AMD submission preflight. Python stdlib only.

Usage:
    python scripts/audit/check_submission.py --repo-root . --output report/competition/local_audit_result.md
    python scripts/audit/check_submission.py --repo-root . --strict

This tool never touches RTL or modifies Git, and does not replace Vivado/Vitis/board tests.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
from urllib.parse import unquote

ALLOWED_STANDARD = {"README.md", "SKILL.md", "LICENSE", "LICENSE.md", "NOTICE", "NOTICE.md"}
LINK_RE = re.compile(r"\]\((<?[^\s)]+>?)(?:\s+[^)]*)?\)")


def tracked_files(root: Path) -> list[str]:
    try:
        p = subprocess.run(["git", "-C", str(root), "ls-files", "-z"],
                           capture_output=True, timeout=15, check=True)
        if p.stdout:
            return sorted(x.replace("\\", "/") for x in p.stdout.decode("utf-8", "replace").split("\0") if x)
    except (OSError, subprocess.SubprocessError):
        pass
    omit = {".git", ".venv", "__pycache__", ".Xil", "vivado", "build", "node_modules"}
    paths = []
    for where, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in omit]
        for name in names:
            p = Path(where) / name
            paths.append(p.relative_to(root).as_posix())
    return sorted(paths)


def strip_fenced_code(text: str) -> str:
    """Remove fenced code blocks so example README snippets are not counted as live links."""
    result = []
    fenced = False
    for line in text.splitlines():
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            fenced = not fenced
            continue
        if not fenced:
            result.append(line)
    return "\n".join(result)


def dead_links(root: Path, path: str) -> list[tuple[str, str]]:
    text = strip_fenced_code((root / path).read_text(encoding="utf-8-sig", errors="replace"))
    failures = []
    for match in LINK_RE.finditer(text):
        raw = match.group(1).strip("<>")
        if raw.startswith(("#", "http://", "https://", "mailto:", "data:")):
            continue
        href = unquote(raw.split("#", 1)[0].split("?", 1)[0])
        if not href:
            continue
        target = (root / path).parent / href
        if not target.exists():
            failures.append((raw, target.resolve().as_posix()))
    return failures


def audit(root: Path) -> dict:
    paths = tracked_files(root)
    issues = []

    def add(priority: str, key: str, msg: str):
        issues.append({"priority": priority, "id": key, "detail": msg})

    needed_dirs = ["rtl", "sim", "ip_repo", "scripts/vivado", "vitis", "report/results", "report/competition", "skill"]
    for path in needed_dirs:
        if not (root / path).is_dir():
            add("P0", "required-dir", f"Missing required project directory: {path}")

    if not any((root / p).exists() for p in ("LICENSE", "LICENSE.md", "LICENSE.txt")):
        add("P0", "license", "No project license found at repo root. Confirm owner rights and third-party attribution before adding one.")

    snapshots = ["scripts/vivado/generated/packaged_ip/bd.tcl", "scripts/vivado/generated/packaged_ip/manifest.tcl",
                 "scripts/vivado/generated/b5_raw_export/bd.tcl", "scripts/vivado/generated/b5_raw_export/manifest.tcl"]
    for p in snapshots:
        if not (root / p).is_file():
            add("P0", "vivado-snapshot", f"Required recorded BD snapshot missing: {p}")

    skills = ["vivado-rebuild", "zynq-dma-debug", "axis-rtl-verification", "udp-packet-validation"]
    for name in skills:
        p = f"skill/{name}/SKILL.md"
        if not (root / p).is_file():
            add("P0", "skill-missing", f"Skill definition absent: {p}")

    readme = (root / "README.md")
    if not readme.is_file():
        add("P0", "readme", "Missing root README.md")
    else:
        text = readme.read_text(encoding="utf-8-sig", errors="replace")
        if "未提交可自动重建这两套完整" in text:
            add("P1", "stale-root-readme", "Root README still claims the rebuilt BD Tcl snapshots are not committed.")

    sr = root / "skill/README.md"
    if sr.is_file() and "后续规划（尚未制作" in sr.read_text(encoding="utf-8-sig", errors="replace"):
        add("P1", "stale-skill-index", "Skill README marks three existing Skills as uncreated.")
    vr = root / "scripts/vivado/README.md"
    if vr.is_file() and "Re-implementation and Vitis regression are still required" in vr.read_text(encoding="utf-8-sig", errors="replace"):
        add("P1", "stale-vivado-status", "Vivado README contains obsolete pre-rebuild status wording.")
    ps = root / "report/results/perf/performance_summary.md"
    if ps.is_file() and "待 CPU 时钟频率校准" in ps.read_text(encoding="utf-8-sig", errors="replace"):
        add("P1", "perf-clock-consistency", "Performance summary still contains CPU clock calibration pending wording; reconcile with evidence.")

    raw = root / "report/ai_collaboration/raw"
    if raw.is_dir() and not any(x.is_file() and x.name.lower() != "readme.md" for x in raw.iterdir()):
        add("P1", "ai-original", "No original AI-conversation evidence files found in report/ai_collaboration/raw/.")

    odd_names = [p for p in paths if any(not re.fullmatch(r"[A-Za-z0-9_.-]+", seg) for seg in p.split("/"))]
    upper_names = [p for p in paths if any(re.search(r"[A-Z]", seg) and seg not in ALLOWED_STANDARD for seg in p.split("/"))]
    if odd_names:
        add("P1", "naming-invalid", f"Paths with non-ASCII/space or unsupported punctuation: {len(odd_names)}; example: {odd_names[:4]}")
    if upper_names:
        add("P2", "naming-uppercase", f"Uppercase legacy paths (beyond conventional README/SKILL): {len(upper_names)}; review before renaming.")

    link_count, broken = 0, []
    for p in paths:
        if not p.lower().endswith(".md") or not (root / p).is_file():
            continue
        # Skip large generated / markdown export artifacts to keep the preflight bounded.
        if (root / p).stat().st_size > 1000000:
            continue
        content = strip_fenced_code((root / p).read_text(encoding="utf-8-sig", errors="replace"))
        link_count += len(list(LINK_RE.finditer(content)))
        broken.extend((p, raw, target) for raw, target in dead_links(root, p))
    for p, raw, target in broken[:40]:
        add("P1", "broken-link", f"{p}: `{raw}` -> missing `{target}`")
    if len(broken) > 40:
        add("P1", "broken-link", f"And {len(broken)-40} more missing Markdown link targets.")

    return {"repo_root": str(root), "tracked_file_count": len(paths),
            "markdown_links_checked": link_count, "broken_markdown_links": len(broken),
            "nonstandard_path_count": len(odd_names), "uppercase_path_count": len(upper_names),
            "issues": issues,
            "disclaimer": "Local source-only static review; no GitHub visibility/default-branch verification, no Vivado, Vitis, FPGA or Skill live tests."}


def report_md(data: dict) -> str:
    lines = ["# DIFI 仓库本地交付审查结果", "", f"根目录：`{data['repo_root']}`  ",
             f"检查文件：{data['tracked_file_count']}；Markdown 链接：{data['markdown_links_checked']}；失效链接：{data['broken_markdown_links']}  ",
             f"异常字符路径：{data['nonstandard_path_count']}；历史大写路径：{data['uppercase_path_count']}", "",
             "| 优先级 | 检查项 | 结果 |", "|---|---|---|"]
    for i in data["issues"]:
        lines.append(f"| {i['priority']} | `{i['id']}` | {i['detail'].replace('|','/')} |")
    if not data["issues"]:
        lines.append("| - | 静态检查 | 未发现规则命中（不代表工程已真实验收） |")
    lines.extend(["", "**限制：**" + data["disclaimer"], ""])
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--output", help="Optional Markdown output file")
    ap.add_argument("--strict", action="store_true", help="Nonzero exit on any P0/P1 issue")
    args = ap.parse_args()
    root = Path(args.repo_root).resolve()
    if not root.is_dir():
        ap.error(f"not a directory: {root}")
    d = audit(root)
    output = report_md(d)
    print(output)
    if args.output:
        dest = Path(args.output)
        if not dest.is_absolute():
            dest = root / dest
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(output, encoding="utf-8")
        print("\n[WROTE]", dest)
    if args.strict and any(x["priority"] in ("P0", "P1") for x in d["issues"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
