#!/usr/bin/env python3
"""Mocked Tcl control-flow smoke test. DOES NOT emulate Vivado IP semantics."""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]


def run_tcl(tcl: str) -> None:
    program = shutil.which('tclsh')
    if not program:
        print('[SKIP] tclsh not available')
        return
    with tempfile.NamedTemporaryFile(mode='w', suffix='.tcl', encoding='utf-8', delete=False) as f:
        f.write(tcl)
        filename = f.name
    try:
        result = subprocess.run([program, filename], capture_output=True,
                                text=True, encoding='utf-8')
    finally:
        Path(filename).unlink(missing_ok=True)
    if result.returncode or 'MOCK_PASS' not in result.stdout:
        raise RuntimeError('Mock Tcl failed: ' + result.stdout + '\n' + result.stderr)


def main() -> None:
    if not shutil.which('tclsh'):
        print('[SKIP] tclsh not available')
        return
    with tempfile.TemporaryDirectory(prefix='vrskill_mock_') as td:
        root = Path(td)
        for rel in ['rtl/top', 'rtl/include', 'ip_repo', 'cfg', 'original']:
            (root / rel).mkdir(parents=True)
        (root / 'rtl/top/top.v').write_text('module top; endmodule\n')
        (root / 'rtl/include/defs.vh').write_text('// header\n')
        (root / 'original/mock_bd.bd').write_text('original design\n')
        (root / 'original/board.xdc').write_text('create_clock -period 10 [get_ports clk]\n')
        (root / 'cfg/test.tcl').write_text('''set ::vrskill_config [dict create \\
    name mock_proj bd_name mock_bd part xc7z020clg400-2 \\
    top mock_bd_wrapper vivado_version 2024.2 \\
    snapshot_rel scripts/vivado/generated/mock_proj \\
    build_rel vivado/rebuilt/mock_proj \\
    report_rel report/results/vivado_rebuild/mock_proj \\
    rtl_globs {rtl/top/*.v rtl/include/*.vh} \\
    include_dirs {rtl/include} ip_repo_dirs {ip_repo}]
''')
        root_tcl = '{' + root.as_posix() + '}'
        source_tcl = '{' + (SKILL / 'scripts/export_bd_generic.tcl').as_posix() + '}'
        rebuild_tcl = '{' + (SKILL / 'scripts/rebuild_generic.tcl').as_posix() + '}'
        api = f'''
set ::mockroot {root_tcl}
proc version {{args}} {{return 2024.2}}
proc get_projects {{args}} {{return {{original_project}}}}
proc current_project {{}} {{return original_project}}
proc get_filesets {{args}} {{return [lindex $args end]}}
proc get_property {{prop obj}} {{
    switch -- $prop {{
        PART {{return xc7z020clg400-2}}
        TOP {{return mock_bd_wrapper}}
        NAME {{if {{$obj eq "original_project"}} {{return mock_project_original}} ; return [file join $::mockroot original board.xdc]}}
        VLNV {{return user.org:user:mock_ip:1.0}}
        ip_repo_paths {{return [file join $::mockroot ip_repo]}}
        default {{return ""}}
    }}
}}
proc get_files {{args}} {{
    if {{[lsearch $args "*.bd"] >= 0}} {{return [file join $::mockroot original mock_bd.bd]}}
    if {{[lsearch $args "-of_objects"] >= 0}} {{return board_xdc}}
    return {{}}
}}
proc open_bd_design {{args}} {{return}}
proc validate_bd_design {{}} {{return}}
proc save_bd_design {{}} {{return}}
proc get_bd_cells {{args}} {{return {{cell_0}}}}
proc write_bd_tcl {{flag out}} {{
    set fd [open $out w]
    puts $fd "# Mocked BD: this is a TEST STUB and contains no real hardware configuration."
    puts $fd "# Mocked BD must not be used to claim Vivado reproducibility or board testing."
    puts $fd "set ::mock_bd_sourced 1"
    close $fd
}}
'''
        export_script = (api + f'\nsource {source_tcl}\n'
                         f'vrskill::export_bd cfg/test.tcl {root_tcl}\n'
                         'puts MOCK_PASS\n')
        run_tcl(export_script)
        snap = root / 'scripts/vivado/generated/mock_proj'
        assert (snap / 'bd.tcl').is_file(), 'export missing BD'
        assert (snap / 'manifest.tcl').is_file(), 'export missing manifest'
        assert len(list((snap / 'constraints').glob('*.xdc'))) == 1, 'XDC not copied'
        print('[PASS] mocked export creates BD, manifest, and copied user XDC')

        reconstruct_api = f'''
set ::mockroot {root_tcl}
proc version {{args}} {{return 2024.2}}
proc get_projects {{args}} {{return {{}}}}
proc current_project {{}} {{return fresh_project}}
proc get_filesets {{args}} {{return sources_1}}
proc get_files {{args}} {{
    if {{[lsearch $args "*.bd"] >= 0}} {{return [file join $::mockroot mock_bd.bd]}}
    return {{mock_bd}}
}}
proc get_property {{prop obj}} {{return ""}}
proc set_property {{args}} {{return}}
proc create_project {{name dir flag part}} {{
    file mkdir $dir
    set fd [open [file join $dir "$name.xpr"] w]
    puts $fd "mock XPR"
    close $fd
}}
proc update_ip_catalog {{args}} {{return}}
proc add_files {{args}} {{return}}
proc update_compile_order {{args}} {{return}}
proc open_bd_design {{args}} {{return}}
proc validate_bd_design {{}} {{return}}
proc save_bd_design {{}} {{return}}
proc generate_target {{args}} {{return}}
proc make_wrapper {{args}} {{
    set wrapper [file join $::mockroot mock_bd_wrapper.v]
    set fd [open $wrapper w]
    puts $fd "module mock_bd_wrapper; endmodule"
    close $fd
    return [list $wrapper]
}}
proc close_project {{}} {{return}}
'''
        rebuild_script = (reconstruct_api + 'set ::vrskill_skip_autorun 1\n'
                          f'source {rebuild_tcl}\n'
                          f'vrskill::rebuild cfg/test.tcl {root_tcl}\n'
                          'puts MOCK_PASS\n')
        run_tcl(rebuild_script)
        assert (root / 'vivado/rebuilt/mock_proj/mock_proj.xpr').is_file()
        print('[PASS] mocked rebuild creates independent XPR; no original project overwritten')

        guard_script = (reconstruct_api + 'set ::vrskill_skip_autorun 1\n'
                        f'source {rebuild_tcl}\n'
                        f'if {{![catch {{vrskill::rebuild cfg/test.tcl {root_tcl}}}]}} '
                        '{error "existing rebuild not blocked"}\n'
                        'puts MOCK_PASS\n')
        run_tcl(guard_script)
        print('[PASS] overwrite prevention blocks pre-existing rebuild directory')
        print('[NOTE] Vivado IP graph, timing, Vitis, and hardware are NOT simulated')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'[FAIL] {e}', file=sys.stderr)
        raise SystemExit(1)
