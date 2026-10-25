"""Check Gamma ordering against direct polynomial evaluation, not DUT output."""
import unittest

from generate_gamma_rom import PARAMETERS, gamma_table
from generate_gamma_inv_rom import gamma_inv_table


class GammaROMTests(unittest.TestCase):
    def test_ntt_matches_polynomial_evaluation(self):
        for n in (256, 512, 1024):
            for p, g in PARAMETERS.values():
                with self.subTest(n=n, p=p):
                    table = gamma_table(p, g, n)
                    self.assertEqual(table[0], 1)
                    self.assertEqual(len(set(table)), n)
                    self.assertTrue(all(0 <= x < p for x in table))
                    original = [(i * i * 19 - 37 * i + 11) % p for i in range(n)]
                    actual = original.copy()
                    m, t = 1, n
                    while m < n:
                        t //= 2
                        for i in range(m):
                            s = table[m + i]
                            for j in range(t):
                                k = 2 * t * i + j
                                a, b = actual[k], actual[k + t] * s % p
                                actual[k], actual[k + t] = (a + b) % p, (a - b) % p
                        m *= 2
                    gamma = pow(g, (p - 1) // (2*n), p)
                    bits = n.bit_length() - 1
                    for i, obtained in enumerate(actual):
                        # Independent bit-reversal expression for root ordering.
                        rev = int(f"{i:0{bits}b}"[::-1], 2)
                        root = pow(gamma, 2 * rev + 1, p)
                        expected = 0
                        for coefficient in reversed(original):
                            expected = (expected * root + coefficient) % p
                        self.assertEqual(obtained, expected, f"output {i}")

                    inverse = gamma_inv_table(p, g, n)
                    self.assertEqual(inverse[0], 1)
                    self.assertTrue(all(0 <= x < p for x in inverse))
                    for a, b in zip(table, inverse):
                        self.assertEqual(a * b % p, 1)
                    # Undo butterflies stage by stage, normalizing by 2
                    # in each stage (equivalent to division by n at the end).
                    m, t, half = n // 2, 1, (p + 1) // 2
                    while m:
                        for i in range(m):
                            s = inverse[m + i]
                            for j in range(t):
                                k = 2 * t * i + j
                                a, b = actual[k], actual[k + t]
                                actual[k] = (a + b) * half % p
                                actual[k + t] = (a - b) * s * half % p
                        m //= 2
                        t *= 2
                    self.assertEqual(actual, original)

    def test_rejects_invalid_parameters(self):
        for p, g, n in ((17, 3, 3), (17, 3, 16), (17, 1, 8)):
            with self.subTest(p=p, g=g, n=n), self.assertRaises(ValueError):
                gamma_table(p, g, n)


if __name__ == "__main__":
    unittest.main()
