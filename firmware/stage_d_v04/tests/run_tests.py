"""Compile and run the portable C validator tests with a native host compiler."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--gcc', help='Use this GCC executable instead of installed MSVC.')
parser.add_argument('--vcvars', type=Path, default=Path('D:/software/visual_studo/VC/Auxiliary/Build/vcvars64.bat'))
args = parser.parse_args()
output = here.parent / 'build/host'
output.mkdir(parents=True, exist_ok=True)
exe = output / ('test_protocol.exe' if os.name == 'nt' else 'test_protocol')
environment = os.environ.copy()
if not args.gcc and os.name == 'nt' and args.vcvars.is_file():
    # cmd has its own /c quote convention; list2cmdline's backslash-escaped
    # quotes are not suitable for invoking a batch file with redirection.
    setup = subprocess.check_output(f'cmd.exe /d /s /c ""{args.vcvars}" >nul && set"', text=True)
    for line in setup.splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            environment[key] = value
    compiler = Path(environment['VCToolsInstallDir']) / 'bin/Hostx64/x64/cl.exe'
    command = [str(compiler), '/nologo', '/std:c11', '/W4', '/WX', '/O2', '/TC',
               '/I' + str(here.parent / 'src'), str(here / 'test_protocol.c'), str(here.parent / 'src/protocol.c'),
               '/Fe:' + str(exe), '/Fo:' + str(output) + '\\']
else:
    command = [args.gcc or shutil.which('gcc') or 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic', '-O2',
               '-I', str(here.parent / 'src'), str(here / 'test_protocol.c'), str(here.parent / 'src/protocol.c'), '-o', str(exe)]
subprocess.run(command, env=environment, check=True)
subprocess.run([str(exe)], env=environment, check=True)
