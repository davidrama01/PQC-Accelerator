#include "fft_transform.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define TEST_N 512U

static int check_integer_quotient(void)
{
    int32_t k[TEST_N] = {0};
    int32_t k_fft[TEST_N];
    int32_t numerator[TEST_N];
    int32_t denominator[TEST_N] = {0};
    int32_t quotient_fft[TEST_N];

    k[0] = 256;
    fft(k, k_fft, TEST_N);

    /* fft_div recibe valores evaluados sin la escala 2/n en el cociente. */
    for (uint32_t i = 0U; i < TEST_N; i++) {
        numerator[i] = k_fft[i] * (int32_t)(TEST_N / 2U);
    }
    for (uint32_t i = 0U; i < TEST_N / 2U; i++) {
        denominator[i] = 1;
    }

    if (fft_div(numerator, denominator, quotient_fft, TEST_N) != 0) {
        printf("FAIL integer quotient was rejected\n");
        return 1;
    }
    for (uint32_t i = 0U; i < TEST_N; i++) {
        if (quotient_fft[i] != k_fft[i]) {
            printf("FAIL quotient at %lu: got %ld expected %ld\n",
                   (unsigned long)i, (long)quotient_fft[i],
                   (long)k_fft[i]);
            return 1;
        }
    }

    printf("PASS integer FFT quotient and scale\n");
    return 0;
}

static int check_zero_denominator(void)
{
    int32_t numerator[2] = {1, 0};
    int32_t denominator[2] = {0, 0};
    int32_t quotient[2];

    if (fft_div(numerator, denominator, quotient, 2U) == 0) {
        printf("FAIL zero denominator was accepted\n");
        return 1;
    }

    printf("PASS zero denominator rejected\n");
    return 0;
}

static int check_large_components(void)
{
    int32_t numerator[2] = {INT32_MAX, INT32_MAX};
    int32_t denominator[2] = {INT32_MAX, INT32_MAX};
    int32_t quotient[2];

    if (fft_div(numerator, denominator, quotient, 2U) != 0) {
        printf("FAIL representable quotient with large components rejected\n");
        return 1;
    }
    if ((quotient[0] != 1) || (quotient[1] != 0)) {
        printf("FAIL large-component quotient: got (%ld, %ld)\n",
               (long)quotient[0], (long)quotient[1]);
        return 1;
    }

    printf("PASS large components without integer overflow\n");
    return 0;
}

int main(void)
{
    int failures = 0;

    failures += check_integer_quotient();
    failures += check_zero_denominator();
    failures += check_large_components();

    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
