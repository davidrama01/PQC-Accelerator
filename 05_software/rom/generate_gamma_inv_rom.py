"""Generate Gamma_inv[i] = gamma**(-bit_reverse(i, log2(n))) mod p.

Ordinary unsigned residues for the inverse NTT, without Montgomery encoding
or inverse-NTT normalization (division by n belongs to the transform).
"""
import argparse
from pathlib import Path

from generate_gamma_rom import PARAMETERS, gamma_table


def gamma_inv_table(p: int, g: int, n: int) -> list[int]:
    # Modular inverse of each entry, retaining exactly the forward ROM order.
    return [pow(value, -1, p) for value in gamma_table(p, g, n)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n", type=int, choices=(256, 512, 1024), default=512)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, (p, g) in PARAMETERS.items():
        values = gamma_inv_table(p, g, args.n)
        output = args.output_dir / f"gamma_inv_{name}_n{args.n}.coe"
        text = "memory_initialization_radix=16;\nmemory_initialization_vector=\n"
        text += ",\n".join(f"{x:08X}" for x in values) + ";\n"
        output.write_text(text, encoding="ascii")
        gamma_inv = pow(pow(g, (p - 1) // (2 * args.n), p), -1, p)
        print(f"{output}: {args.n} x 32 bits, p={p}, g={g}, gamma_inv={gamma_inv}")


if __name__ == "__main__":
    main()
