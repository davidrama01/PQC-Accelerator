"""Generate Gamma[i] = gamma**bit_reverse(i, log2(n)) mod p.

Parameters match hawk_params.h / ntt_transform.c. Residues are ordinary
unsigned integers, not Montgomery values or fixed-point numbers.
"""
import argparse
from pathlib import Path

PARAMETERS = {"p1": (2147473409, 3), "p2": (2147389441, 11)}


def bit_reverse(value: int, bits: int) -> int:
    result = 0
    for _ in range(bits):
        result = (result << 1) | (value & 1)
        value >>= 1
    return result


def gamma_table(p: int, g: int, n: int) -> list[int]:
    if n < 2 or n & (n - 1):
        raise ValueError("n must be a power of two, at least 2")
    if (p - 1) % (2 * n):
        raise ValueError("2*n must divide p-1")
    gamma = pow(g, (p - 1) // (2 * n), p)
    # For power-of-two n these conditions establish exact order 2*n.
    if pow(gamma, n, p) != p - 1 or pow(gamma, 2 * n, p) != 1:
        raise ValueError("gamma is not a primitive root of order 2*n")
    bits = n.bit_length() - 1
    return [pow(gamma, bit_reverse(i, bits), p) for i in range(n)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n", type=int, choices=(256, 512, 1024), default=512)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, (p, g) in PARAMETERS.items():
        values = gamma_table(p, g, args.n)
        output = args.output_dir / f"gamma_{name}_n{args.n}.coe"
        text = "memory_initialization_radix=16;\nmemory_initialization_vector=\n"
        text += ",\n".join(f"{x:08X}" for x in values) + ";\n"
        output.write_text(text, encoding="ascii")
        gamma = pow(g, (p - 1) // (2 * args.n), p)
        print(f"{output}: {args.n} x 32 bits, p={p}, g={g}, gamma={gamma}")


if __name__ == "__main__":
    main()
