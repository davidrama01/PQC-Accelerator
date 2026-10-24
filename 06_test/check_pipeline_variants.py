"""Check keygen, signing and verification with a mathematical accelerator backend."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HEADERS = ROOT / '05_software/headers'
WORK = ROOT / '06_test/.work/pipeline_variants'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default='C:/MINGW/bin/gcc.exe')
    args = parser.parse_args()
    params = (HEADERS / 'hawk_params.h').read_text()
    for n in (256, 512, 1024):
        directory = WORK / str(n)
        directory.mkdir(parents=True, exist_ok=True)
        for header in HEADERS.glob('*.h'):
            shutil.copyfile(header, directory / header.name)
        selected = re.sub(r'^#define HAWK_512$', f'#define HAWK_{n}', params,
                          count=1, flags=re.MULTILINE)
        (directory / 'hawk_params.h').write_text(selected)
        executable = directory / 'pipeline_test.exe'
        sources = [ROOT / '05_software/src' / (name + '.c') for name in
                   ('keygen', 'basic', 'decode', 'encode', 'regenerate',
                    'fft_transform', 'ntt_transform', 'shake256', 'towersolver', 'hawk_sign', 'hawk_verify', 'sampler_sign')]
        sources += list((ROOT / '05_software/third_party/ntrugen').glob('*.c'))
        command = [args.cc, '-std=c99', '-O2', '-Wall', '-Wextra',
                   '-DNTRUGEN_AVX2=0', '-I' + str(directory),
                   '-I' + str(ROOT / '06_test/vitis_mock'),
                   '-I' + str(ROOT / '05_software/third_party/ntrugen'),
                   *map(str, sources), str(ROOT / '06_test/main_hawk_pipeline_test.c'),
                   '-lm', '-o', str(executable)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (directory / 'compile.log').write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        print(f'pipeline n={n}: compiled', flush=True)
        result = subprocess.run([str(executable)], capture_output=True, text=True,
                                timeout=180)
        log = result.stdout + result.stderr
        (directory / 'test.log').write_text(log)
        print(f'n={n}: {log}', end='', flush=True)
        if result.returncode or f'PASS pipeline HAWK-{n}' not in log:
            raise RuntimeError(f'pipeline n={n} failed: {result.returncode}')


if __name__ == '__main__':
    main()
