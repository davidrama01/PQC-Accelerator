"""Host-test the Vitis verification path with independent hashlib vectors."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HEADERS = ROOT / '05_software/headers'
WORK = ROOT / '06_test/.work/hawk_verify'
PARAMETERS = {
    256: (450, 249, 14, 16, 5, 9, 8, 11, 5, 9),
    512: (1024, 555, 24, 32, 5, 9, 9, 12, 5, 9),
    1024: (2440, 1221, 40, 64, 6, 10, 10, 14, 6, 10),
}


def gr(values, low, high):
    magnitudes = [x if x >= 0 else -x - 1 for x in values]
    assert all(0 <= x < 1 << high for x in magnitudes)
    bits = [int(x < 0) for x in values]
    bits += [(x >> b) & 1 for x in magnitudes for b in range(low)]
    for x in magnitudes:
        bits += [0] * (x >> low) + [1]
    return bits


def pack(bits, length):
    assert len(bits) <= length * 8
    out = bytearray(length)
    for i, bit in enumerate(bits):
        out[i // 8] |= bit << (i % 8)
    return bytes(out)


def c_array(values, digits=2):
    return '{' + ','.join(f'0x{x:0{digits}X}U' for x in values) + '}'


def vectors(directory, n):
    pub_len, sig_len, salt_len, hpub_len, l00, h00, l01, h01, ls1, hs1 = PARAMETERS[n]
    q00 = [0] * n
    q00[0], q00[1], q00[3] = 129, 3, -2
    for i in range(n // 2 + 1, n):
        q00[i] = -q00[n-i]
    q01 = [(i * 7) % 17 - 8 for i in range(n)]
    s1 = [(i * 3) % 7 - 3 for i in range(n)]
    salt = bytes((i * 23 + 9) & 255 for i in range(salt_len))
    v = 16 - h00
    first_half = q00[:n//2]
    first_half[0] >>= v
    pub_bits = gr(first_half, l00, h00)
    pub_bits += [(q00[0] >> i) & 1 for i in range(v)]
    pub_bits += [0] * (-len(pub_bits) % 8)
    pub = pack(pub_bits + gr(q01, l01, h01), pub_len)
    sig = salt + pack(gr(s1, ls1, hs1), sig_len - salt_len)
    assert not pub[-1] and not sig[-1]  # Mutation tests change final padding.
    messages = [b'', bytes(range(256)) + b'HAWK\0test',
                bytes((i * 29 + 5) & 255 for i in range(1024))]
    hpub = hashlib.shake_256(pub).digest(hpub_len)
    packets = []
    for message in messages:
        m = hashlib.shake_256(message + hpub).digest(64)
        h = hashlib.shake_256(m + salt).digest(n // 4)
        h0 = list(struct.unpack('<' + 'I' * (n//32), h[:n//8]))
        w1 = [((h[n//8+i//8] >> (i % 8)) & 1) - 2*s1[i] for i in range(n)]
        packets.append([x & 0xFFFFFFFF for x in h0 + q00 + q01 + w1])
    lines = ['#define VERIFY_CASES 3U',
             f'static const uint8_t public_key[{pub_len}] = ' + c_array(pub) + ';',
             f'static const uint8_t signature[{sig_len}] = ' + c_array(sig) + ';',
             'static const size_t message_lengths[VERIFY_CASES] = {' +
             ','.join(str(len(x))+'U' for x in messages) + '};',
             'static const uint8_t messages[VERIFY_CASES][1024] = {' +
             ','.join(c_array(x) if x else '{0}' for x in messages) + '};',
             'static const uint32_t expected_packets[VERIFY_CASES]' +
             f'[{n//32 + 3*n}] = ' + '{' +
             ','.join(c_array(x, 8) for x in packets) + '};']
    (directory / 'verify_vectors.h').write_text('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default='C:/MINGW/bin/gcc.exe')
    parser.add_argument('--runtime', action='store_true',
                        help='Test the runtime parameter selection and real DMA driver')
    args = parser.parse_args()
    params = (HEADERS / 'hawk_params.h').read_text()
    for n in PARAMETERS:
        directory = WORK / str(n)
        directory.mkdir(parents=True, exist_ok=True)
        for header in ('decode.h', 'encode.h', 'hawk_fpga.h', 'hawk_verify.h', 'shake256.h'):
            shutil.copyfile(HEADERS / header, directory / header)
        selected = re.sub(r'^#define HAWK_512$', f'#define HAWK_{n}', params,
                          count=1, flags=re.MULTILINE)
        (directory / 'hawk_params.h').write_text(
            params if args.runtime else '#define HAWK_FIXED_PARAMS\n' + selected)
        vectors(directory, n)
        executable = directory / 'test_hawk_verify.exe'
        command = [args.cc, '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror',
                   '-DHAWK_FPGA_DMA_TIMEOUT=16U', '-DHAWK_FPGA_VERIFY_TIMEOUT=16U',
                   '-I' + str(directory), '-I' + str(ROOT / '06_test/vitis_mock'),
                   *[str(ROOT / '05_software/src' / (name + '.c')) for name in
                     ('hawk_verify', 'hawk_fpga', 'decode', 'encode', 'shake256')],
                   str(ROOT / '06_test/main_hawk_verify_test.c'), '-o', str(executable)]
        if args.runtime:
            command[1:1] = [f'-DHAWK_TEST_N={n}', str(ROOT / '05_software/src/hawk_params.c')]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (directory / 'compile.log').write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        result = subprocess.run([str(executable)], capture_output=True, text=True)
        log = result.stdout + result.stderr
        (directory / 'test.log').write_text(log)
        print(log, end='', flush=True)
        if result.returncode or f'PASS: hawk_verify HAWK-{n}' not in log:
            raise RuntimeError(f'HAWK-{n} failed: {result.returncode}')
    print('PASS: all Vitis verification integration tests (mock hardware)')


if __name__ == '__main__':
    main()
