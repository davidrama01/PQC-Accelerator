#include "fft_transform.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define TEST_N 512U

static int check_component_products(void)
{
    int32_t a[TEST_N];
    int32_t b[TEST_N];
    int32_t c[TEST_N];

    for (uint32_t i = 0U; i < TEST_N / 2U; i++) {
        a[i] = (int32_t)(i % 31U) - 15;
        a[i + TEST_N / 2U] = (int32_t)(i % 23U) - 11;
        b[i] = (int32_t)(i % 19U) - 9;
        b[i + TEST_N / 2U] = (int32_t)(i % 17U) - 8;
    }

    if (fft_mul(a, b, c, TEST_N) != 0) {
        printf("FAIL unexpected overflow in component test\n");
        return 1;
    }

    for (uint32_t i = 0U; i < TEST_N / 2U; i++) {
        int64_t expected_real =
            (int64_t)a[i] * b[i] -
            (int64_t)a[i + TEST_N / 2U] * b[i + TEST_N / 2U];
        int64_t expected_imag =
            (int64_t)a[i] * b[i + TEST_N / 2U] +
            (int64_t)a[i + TEST_N / 2U] * b[i];

        if ((c[i] != expected_real) ||
            (c[i + TEST_N / 2U] != expected_imag)) {
            printf("FAIL component %lu\n", (unsigned long)i);
            return 1;
        }
    }

    printf("PASS component-wise complex products\n");
    return 0;
}

static int check_overflow_is_rejected(void)
{
    int32_t a[2] = {INT32_MAX, 0};
    int32_t b[2] = {2, 0};
    int32_t c[2];

    if (fft_mul(a, b, c, 2U) == 0) {
        printf("FAIL overflow was accepted\n");
        return 1;
    }

    printf("PASS overflow rejected\n");
    return 0;
}

static int characterize_fft_scale(void)
{
    int32_t a[TEST_N] = {0};
    int32_t b[TEST_N] = {0};
    int32_t a_fft[TEST_N];
    int32_t b_fft[TEST_N];
    int32_t product_fft[TEST_N];
    int32_t product[TEST_N];

    a[0] = 4096;
    b[0] = 4096;
    fft(a, a_fft, TEST_N);
    fft(b, b_fft, TEST_N);
    if (fft_mul(a_fft, b_fft, product_fft, TEST_N) != 0) {
        printf("FAIL unexpected overflow in scale test\n");
        return 1;
    }
    ifft(product_fft, product, TEST_N);

    /* FFT e InvFFT aportan cada una un factor 2/n. */
    if (product[0] != 256) {
        printf("FAIL scale: got %ld, expected 256\n", (long)product[0]);
        return 1;
    }
    for (uint32_t i = 1U; i < TEST_N; i++) {
        if (product[i] != 0) {
            printf("FAIL scale: nonzero coefficient %lu\n", (unsigned long)i);
            return 1;
        }
    }

    printf("PASS scale characterization: 4096*4096 maps to 256\n");
    return 0;
}

static int check_scaled_products(void)
{
    int32_t a[TEST_N] = {0};
    int32_t b[TEST_N] = {0};
    int32_t expected_product[TEST_N] = {0};
    int32_t a_fft[TEST_N];
    int32_t b_fft[TEST_N];
    int32_t expected_fft[TEST_N];
    int32_t scaled_fft[TEST_N];
    int32_t coefficient_fft[TEST_N];
    int32_t recovered[TEST_N];

    a[0] = 4096;
    b[0] = 4096;
    expected_product[0] = 4096 * 4096;

    fft(a, a_fft, TEST_N);
    fft(b, b_fft, TEST_N);
    fft(expected_product, expected_fft, TEST_N);

    if (fft_mul_scaled(a_fft, b_fft, scaled_fft, TEST_N,
                       TEST_N / 2U) != 0) {
        printf("FAIL representation-scaled product overflow\n");
        return 1;
    }
    for (uint32_t i = 0U; i < TEST_N; i++) {
        if (scaled_fft[i] != expected_fft[i]) {
            printf("FAIL representation scale at %lu: got %ld expected %ld\n",
                   (unsigned long)i, (long)scaled_fft[i],
                   (long)expected_fft[i]);
            return 1;
        }
    }

    if (fft_mul_scaled(a_fft, b_fft, coefficient_fft, TEST_N,
                       (TEST_N / 2U) * (TEST_N / 2U)) != 0) {
        printf("FAIL coefficient-scaled product overflow\n");
        return 1;
    }
    ifft(coefficient_fft, recovered, TEST_N);
    for (uint32_t i = 0U; i < TEST_N; i++) {
        if (recovered[i] != expected_product[i]) {
            printf("FAIL coefficient recovery at %lu: got %ld expected %ld\n",
                   (unsigned long)i, (long)recovered[i],
                   (long)expected_product[i]);
            return 1;
        }
    }

    printf("PASS explicit FFT product scales\n");
    return 0;
}

int main(void)
{
    int failures = 0;

    failures += check_component_products();
    failures += check_overflow_is_rejected();
    failures += characterize_fft_scale();
    failures += check_scaled_products();

    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
