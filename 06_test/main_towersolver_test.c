#include "towersolver.h"
#include "regenerate.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define TEST_N 512

int xil_printf(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    int result = vprintf(format, args);
    va_end(args);
    return result;
}

int main(void)
{
    int32_t f[TEST_N] = {0};
    int32_t g[TEST_N] = {0};
    int32_t F[TEST_N];
    int32_t G[TEST_N];

    f[0] = 1;
    g[0] = 1;
    if (towersolver(f, g, F, G, TEST_N) != 0) {
        printf("FAIL solver rejected f=1, g=0\n");
        return EXIT_FAILURE;
    }

    for (uint32_t i = 0U; i < TEST_N; i++) {
        int32_t expected = i == 0U ? 1 : 0;
        if ((G[i] - F[i]) != expected) {
            printf("FAIL solution coefficient %lu: F=%ld G=%ld\n",
                   (unsigned long)i, (long)F[i], (long)G[i]);
            return EXIT_FAILURE;
        }
    }

    printf("PASS exact NTRU solver smoke test\n");

    uint8_t seed[HAWK_KGSEED_BYTES] = {0};
    int8_t f8[TEST_N];
    int8_t g8[TEST_N];
    int solved = 0;
    for (uint32_t attempt = 0U; attempt < 64U; attempt++) {
        seed[0] = (uint8_t)attempt;
        if (RegenerateFG(seed, f8, g8) != 0) {
            return EXIT_FAILURE;
        }
        for (uint32_t i = 0U; i < TEST_N; i++) {
            f[i] = f8[i];
            g[i] = g8[i];
        }
        if (towersolver(f, g, F, G, TEST_N) == 0) {
            solved = 1;
            break;
        }
    }
    if (!solved) {
        printf("FAIL no regenerated candidate was solved\n");
        return EXIT_FAILURE;
    }

    int64_t equation[TEST_N] = {0};
    for (uint32_t i = 0U; i < TEST_N; i++) {
        for (uint32_t j = 0U; j < TEST_N; j++) {
            uint32_t k = i + j;
            int64_t value = (int64_t)f[i] * G[j] -
                            (int64_t)g[i] * F[j];
            if (k >= TEST_N) {
                k -= TEST_N;
                value = -value;
            }
            equation[k] += value;
        }
    }
    for (uint32_t i = 0U; i < TEST_N; i++) {
        int64_t expected = i == 0U ? 1 : 0;
        if (equation[i] != expected) {
            printf("FAIL regenerated equation at %lu: got %lld\n",
                   (unsigned long)i, (long long)equation[i]);
            return EXIT_FAILURE;
        }
    }

    printf("PASS regenerated f*G-g*F=1 verification\n");
    return EXIT_SUCCESS;
}
