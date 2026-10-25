import math
from pathlib import Path

N = 1024
BITS = 10
SCALE = 1 << 31
PI = 3.14159265358979323846264338327950288
DELTA_ANGLE = 2.0 * PI / 2048.0
OUTPUT = Path(__file__).with_name("delta_rom.coe")


def bit_reverse(value: int, bits: int) -> int:
    result = 0
    for _ in range(bits):
        result = (result << 1) | (value & 1)
        value >>= 1
    return result


def llround(value: float) -> int:
    # Equivalente a llround() de C: redondeo alejándose de cero.
    return math.floor(value + 0.5) if value >= 0.0 else math.ceil(value - 0.5)


def uint32(value: int) -> int:
    return value & 0xFFFFFFFF


def main() -> None:
    words = []

    for k in range(N):
        k_rev = bit_reverse(k, BITS)
        real = llround(math.cos(DELTA_ANGLE * k_rev) * SCALE)
        imag = llround(math.sin(DELTA_ANGLE * k_rev) * SCALE)

        # Bits 63..32: imaginaria; bits 31..0: real.
        word = (uint32(imag) << 32) | uint32(real)
        words.append(f"{word:016X}")

    with OUTPUT.open("w", encoding="ascii", newline="\n") as file:
        file.write("memory_initialization_radix=16;\n")
        file.write("memory_initialization_vector=\n")
        file.write(",\n".join(words))
        file.write(";\n")

    print(f"Generadas {len(words)} entradas en {OUTPUT}")


if __name__ == "__main__":
    main()
