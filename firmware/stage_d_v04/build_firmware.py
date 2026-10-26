"""Build an independent SDU4 ELF using a read-only existing Stage D BSP.

Does not invoke Vivado, XSCT, a debug server, download, or hardware programming.
The Vitis 2024.2 GCC and BSP libraries are the ones used by the v0.3 component.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> int:
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bsp', type=Path, default=root / 'vitis/vitis_ws_rebuilt/difi_half_duplex_platform/export/difi_half_duplex_platform/sw/standalone_ps7_cortexa9_0')
    parser.add_argument('--gcc', type=Path, default=Path('D:/software/xilinx_2024.2/Vitis/2024.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe'))
    parser.add_argument('--linker-script', type=Path, default=root / 'vitis/vitis_ws_rebuilt/difi_stage_d_udp_half_duplex/src/lscript.ld')
    parser.add_argument('--output', type=Path, default=here / 'build')
    args = parser.parse_args()
    bsp = args.bsp.resolve()
    for path in (args.gcc, args.linker_script, bsp / 'include/xparameters.h', bsp / 'Xilinx.spec', bsp / 'lib/libxil.a', bsp / 'lib/liblwip220.a'):
        if not path.is_file():
            parser.error(f'Required existing tool/BSP file is missing: {path}; pass --gcc/--bsp/--linker-script. No existing workspace is rebuilt or edited.')
    output = args.output.resolve()
    if output == root or output in (args.linker_script.parent.resolve(), bsp):
        parser.error('Output must be a separate build directory.')
    output.mkdir(parents=True, exist_ok=True)
    linker = output / 'lscript.ld'
    shutil.copyfile(args.linker_script, linker)
    environment = os.environ.copy()
    environment['PATH'] = str(args.gcc.parent) + os.pathsep + environment.get('PATH', '')
    common = ['-DSDT', '-mcpu=cortex-a9', '-mfpu=vfpv3', '-mfloat-abi=hard', '-O2', '-g3', '-Wall', '-Wextra', '-std=c99',
              f'-specs={bsp / "Xilinx.spec"}', '-I', str(bsp / 'include'), '-I', str(here / 'src')]
    commands = []
    objects = []
    for name in ('protocol', 'main'):
        obj = output / f'{name}.o'
        command = [str(args.gcc), *common, '-c', str(here / 'src' / f'{name}.c'), '-o', str(obj)]
        commands.append(command)
        subprocess.run(command, env=environment, check=True)
        objects.append(str(obj))
    elf = output / 'difi_stage_d_v04.elf'
    command = [str(args.gcc), *common, *objects, '-o', str(elf), '-Wl,-T,' + str(linker), '-Wl,-Map,' + str(output / 'difi_stage_d_v04.map'),
               '-L', str(bsp / 'lib'), '-Wl,--start-group', '-lxilstandalone', '-lxiltimer', '-llwip220', '-lxil', '-lgcc', '-lc', '-Wl,--end-group']
    commands.append(command)
    subprocess.run(command, env=environment, check=True)
    size = args.gcc.with_name('arm-none-eabi-size.exe')
    sizes = subprocess.check_output([str(size), '--format=berkeley', str(elf)], env=environment, text=True)
    print(sizes, end='')
    record = {'result': 'BUILD PASS / HARDWARE UNTESTED', 'elf': str(elf), 'sha256': hashlib.sha256(elf.read_bytes()).hexdigest(),
              'bsp_read_only': str(bsp), 'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (here / 'src').glob('*.[ch]')},
              'commands': commands, 'size': sizes, 'programmed_hardware': False}
    (output / 'build_manifest.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(f'BUILD PASS: {elf}\nSHA256: {record["sha256"]}\nHardware was not programmed or tested.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        print(f'Build failed with exit code {exc.returncode}', file=sys.stderr)
        raise SystemExit(exc.returncode)
