#include "fft_transform.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_TEST_N 1024U

static uint32_t fnv1a_int32(const int32_t *values, uint32_t n)
{
    uint32_t hash = 2166136261U;

    for (uint32_t i = 0U; i < n; i++) {
        uint32_t value = (uint32_t)values[i];
        for (uint32_t shift = 0U; shift < 32U; shift += 8U) {
            hash ^= (value >> shift) & 0xFFU;
            hash *= 16777619U;
        }
    }
    return hash;
}

static int check_delta(uint32_t k, int64_t expected_real,
                       int64_t expected_imag)
{
    int64_t real;
    int64_t imag;

    delta(k, &real, &imag);
    if ((real != expected_real) || (imag != expected_imag)) {
        printf("FAIL delta[%lu]: got (%lld, %lld), expected (%lld, %lld)\n",
               (unsigned long)k,
               (long long)real, (long long)imag,
               (long long)expected_real, (long long)expected_imag);
        return 1;
    }
    return 0;
}

static int check_fft(uint32_t n, uint32_t expected_hash)
{
    int32_t input[MAX_TEST_N];
    int32_t output[MAX_TEST_N];

    for (uint32_t i = 0U; i < n; i++) {
        input[i] = (int32_t)((i * 37U) % 257U) - 128;
    }

    fft(input, output, n);
    uint32_t hash = fnv1a_int32(output, n);
    if (hash != expected_hash) {
        printf("FAIL FFT-%lu: hash=%08lx, expected=%08lx\n",
               (unsigned long)n,
               (unsigned long)hash,
               (unsigned long)expected_hash);
        return 1;
    }

    printf("PASS FFT-%lu: hash=%08lx\n",
           (unsigned long)n, (unsigned long)hash);
    return 0;
}

int main(void)
{
    int failures = 0;

    /* Entradas exactas de la tabla Delta definida en la especificacion. */
    failures += check_delta(2U, 1518500250LL, 1518500250LL);
    failures += check_delta(3U, -1518500250LL, 1518500250LL);
    failures += check_delta(4U, 1984016189LL, 821806413LL);

    /* Hashes obtenidos con una implementacion independiente del algoritmo 16. */
    failures += check_fft(256U, 0x03257A80U);
    failures += check_fft(512U, 0x3D7DA2E3U);
    failures += check_fft(1024U, 0x794A89B8U);

    if (failures != 0) {
        printf("FFT tests failed: %d\n", failures);
        return EXIT_FAILURE;
    }

    printf("All FFT specification tests passed.\n");
    return EXIT_SUCCESS;
}
