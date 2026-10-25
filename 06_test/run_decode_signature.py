"""Compile and test DecodeSignature for each HAWK parameter set."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HEADERS = ROOT / '05_software/headers'
WORK = ROOT / '06_test/.work/decode_signature'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default='C:/MINGW/bin/gcc.exe')
    args = parser.parse_args()
    params = (HEADERS / 'hawk_params.h').read_text()
    for n in (256, 512, 1024):
        directory = WORK / str(n)
        directory.mkdir(parents=True, exist_ok=True)
        # Local header copies avoid changing the project's parameter selection.
        selected = re.sub(r'^#define HAWK_512$', f'#define HAWK_{n}', params,
                          count=1, flags=re.MULTILINE)
        (directory / 'hawk_params.h').write_text('#define HAWK_FIXED_PARAMS\n' + selected)
        for header in ('decode.h', 'encode.h'):
            shutil.copyfile(HEADERS / header, directory / header)
        executable = directory / 'test_decode_signature.exe'
        command = [args.cc, '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror',
                   '-I' + str(directory),
                   str(ROOT / '05_software/src/decode.c'),
                   str(ROOT / '05_software/src/encode.c'),
                   str(ROOT / '06_test/main_decode_signature_test.c'),
                   '-o', str(executable)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (directory / 'compile.log').write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        result = subprocess.run([str(executable)], capture_output=True, text=True)
        output = result.stdout + result.stderr
        (directory / 'test.log').write_text(output)
        print(output, end='', flush=True)
        if result.returncode or f'PASS: DecodeSignature HAWK-{n}' not in output:
            raise RuntimeError(f'HAWK-{n} failed: {result.returncode}')
    print('PASS: all DecodeSignature parameter sets')


if __name__ == '__main__':
    main()
