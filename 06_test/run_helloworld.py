"""Run the actual three-size helloworld with a mathematical FPGA backend."""
from pathlib import Path
import subprocess
import argparse

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default='C:/MINGW/bin/gcc.exe')
    args = parser.parse_args()
    work = ROOT / '06_test/.work/helloworld'
    work.mkdir(parents=True, exist_ok=True)
    (work / 'platform.h').write_text(
        'static inline void init_platform(void) {}\n'
        'static inline void cleanup_platform(void) {}\n')
    sources = [ROOT / '05_software/src' / (name + '.c') for name in
               ('hawk_params', 'helloworld', 'keygen', 'basic', 'decode', 'encode',
                'regenerate', 'fft_transform', 'ntt_transform', 'shake256',
                'towersolver', 'hawk_sign', 'hawk_verify', 'sampler_sign')]
    sources += list((ROOT / '05_software/third_party/ntrugen').glob('*.c'))
    flags = [args.cc, '-std=c99', '-O2', '-Wall', '-Wextra', '-DNTRUGEN_AVX2=0',
             '-I' + str(work), '-I' + str(ROOT / '05_software/headers'),
             '-I' + str(ROOT / '06_test/vitis_mock'),
             '-I' + str(ROOT / '05_software/third_party/ntrugen')]
    command = flags + ['-DHAWK_HELLOWORLD_TEST', *map(str, sources),
                      str(ROOT / '06_test/main_hawk_pipeline_test.c'),
                      '-lm', '-o', str(work / 'helloworld.exe')]
    result = subprocess.run(command, capture_output=True, text=True)
    (work / 'compile.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(result.stderr)
    # Compile the real driver too: it uses maximum-capacity static buffers but
    # must send/receive only the length selected at runtime.
    subprocess.run(flags + ['-c', str(ROOT / '05_software/src/hawk_fpga.c'),
                           '-o', str(work / 'hawk_fpga.o')], check=True)
    result = subprocess.run([str(work / 'helloworld.exe')], capture_output=True,
                            text=True, timeout=240)
    log = result.stdout + result.stderr
    (work / 'test.log').write_text(log)
    for n in (256, 512, 1024):
        assert f'HAWK-{n}: PASS' in log, log
        print(f'PASS actual helloworld n={n}')
    assert result.returncode == 0 and 'Completed: 3/3 cases passed' in log, log
    print(f'PASS: one executable, mathematical FPGA backend. Log: {work / "test.log"}')


if __name__ == '__main__':
    main()
