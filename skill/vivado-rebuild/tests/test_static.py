#!/usr/bin/env python3
"""Tcl/config/package smoke checks, intentionally NOT a Vivado hardware test."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
REQUIRED = [
    'SKILL.md', 'README.md',
    'scripts/common.tcl', 'scripts/export_bd_generic.tcl',
    'scripts/rebuild_generic.tcl', 'scripts/verify_impl_generic.tcl',
    'templates/project_config.tcl', 'templates/ai_workflow.md',
    'templates/acceptance_report.md', 'examples/difi-case-study.md',
]


def tcl_run(script: str) -> str:
    program = shutil.which('tclsh')
    if not program:
        print('[SKIP] Tcl parser unavailable (install Tcl/tclsh or use Vivado Tcl Shell)')
        return ''
    result = subprocess.run([program], input=script, capture_output=True,
                            text=True, encoding='utf-8')
    if result.returncode:
        raise AssertionError(f'Tcl check failed (rc={result.returncode}):\n'
                             f'{result.stdout}\n{result.stderr}')
    if 'CHECK_PASS' not in result.stdout:
        raise AssertionError('Tcl check did not reach CHECK_PASS:\n' + result.stdout)
    return result.stdout


def quote_tcl(path: Path) -> str:
    # Files in project/skill convention are English names without braces.
    return '{' + path.as_posix() + '}'


def main() -> None:
    missing = [f for f in REQUIRED if not (SKILL / f).is_file()]
    if missing:
        raise AssertionError('Missing skill contents: ' + ', '.join(missing))
    header = (SKILL / 'SKILL.md').read_text(encoding='utf-8').splitlines()
    assert header[0] == '---' and 'name: vivado-rebuild' in header
    print(f'[PASS] all {len(REQUIRED)} required artifacts and SKILL frontmatter')

    common = SKILL / 'scripts/common.tcl'
    configs = SKILL / 'templates/project_config.tcl'
    scripts = [SKILL / f'scripts/{name}' for name in
               ('export_bd_generic.tcl', 'rebuild_generic.tcl', 'verify_impl_generic.tcl')]
    tests = ['set ::vrskill_skip_autorun 1', f'source {quote_tcl(common)}']
    tests += [f'source {quote_tcl(s)}' for s in scripts]
    tests += [f'source {quote_tcl(configs)}',
              'foreach key {name bd_name part top vivado_version snapshot_rel build_rel '
              'report_rel rtl_globs include_dirs ip_repo_dirs} {',
              '  if {![dict exists $::vrskill_config $key]} {error "missing config key: $key"}',
              '}',
              'set root [file normalize [pwd]]',
              'set p [::vrskill::absolute_from_root $root {rtl/top/foo.v}]',
              'if {[string first $root $p] != 0} {error "valid path incorrectly rejected"}',
              'if {![catch {::vrskill::absolute_from_root $root {../escape.v}}]} '
              '{error "traversal not rejected"}',
              'if {![catch {::vrskill::absolute_from_root $root {/etc/passwd}}]} '
              '{error "absolute path not rejected"}',
              'set snapshot [dict create bd_name design_1 part xc7z020clg400-2 '
              'top design_1_wrapper vivado_version 2024.2]',
              '::vrskill::check_identity $::vrskill_config $snapshot',
              'dict set snapshot top WRONG_TOP',
              'if {![catch {::vrskill::check_identity $::vrskill_config $snapshot}]} '
              '{error "mismatch not rejected"}',
              'puts CHECK_PASS']
    output = tcl_run('\n'.join(tests) + '\n')
    if output:
        print('[PASS] Tcl files load, config has required keys, path and identity guards work')
    print('[NOTE] Static checks only; Vivado/vitis/board run is not simulated')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'[FAIL] {exc}', file=sys.stderr)
        raise SystemExit(1)
