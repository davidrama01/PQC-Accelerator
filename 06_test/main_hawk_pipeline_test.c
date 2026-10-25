/* Host mathematical backend: does not replace a test of the actual FPGA. */
#include <assert.h>
#include <stdarg.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hawk_params.h"
#include "hawk_sign.h"
#include "hawk_verify.h"
#include "hawk_fpga.h"
#include "keygen.h"
#include "decode.h"
#include "basic.h"
#include "fft_transform.h"
#include "ntt_transform.h"

static uint32_t rng_state = UINT32_C(0x6A09E667), rng_calls, sign_attempts;
static int32_t saved_f[HAWK_MAX_N], saved_g[HAWK_MAX_N], saved_s1[HAWK_MAX_N];
static uint32_t saved_h1[HAWK_MAX_N / 32U];
static unsigned phase;
static int rtl_parameters, check_norm, scaling_overflow;
static uint64_t sampled_norm, verified_norm;

int Rnd(uint8_t *out, size_t num_bits)
{
    assert(out != NULL && num_bits % 8U == 0U);
    if (++rng_calls > 100000U) {
        fprintf(stderr, "FAIL: random retry limit\n");
        exit(EXIT_FAILURE);
    }
    for (size_t i = 0U; i < num_bits / 8U; i++) {
        if (i % 4U == 0U) {
            rng_state ^= rng_state << 13;
            rng_state ^= rng_state >> 17;
            rng_state ^= rng_state << 5;
        }
        out[i] = (uint8_t)(rng_state >> (8U * (i % 4U)));
    }
    return 0;
}

int xil_printf(const char *format, ...)
{
#ifdef HAWK_HELLOWORLD_TEST
    va_list args;
    va_start(args, format);
    int result = vprintf(format, args);
    va_end(args);
    return result;
#else
    (void)format;
    return 0;
#endif
}

static unsigned bit(const uint32_t *x, size_t i)
{
    return (x[i / 32U] >> (i % 32U)) & 1U;
}

static void binary_product(const uint32_t *a, const uint32_t *b, uint32_t *out)
{
    memset(out, 0, HAWK_N_WORDS32 * sizeof *out);
    for (size_t i = 0U; i < HAWK_N; i++) {
        unsigned value = 0U;
        for (size_t j = 0U; j < HAWK_N; j++) {
            value ^= bit(a, j) & bit(b, (i + HAWK_N - j) % HAWK_N);
        }
        out[i / 32U] |= value << (i % 32U);
    }
}

int HawkFpgaCalculateT(const uint32_t *h0, const uint32_t *h1,
                       const uint32_t *F, const uint32_t *G,
                       const int32_t *f, const int32_t *g,
                       uint32_t *t0, uint32_t *t1)
{
    uint32_t fp[HAWK_N_WORDS32], gp[HAWK_N_WORDS32];
    uint32_t product[HAWK_N_WORDS32];
    memset(fp, 0, sizeof fp);
    memset(gp, 0, sizeof gp);
    assert(phase == 0U);
    if (++sign_attempts > 1000U) {
        return -1;
    }
    memcpy(saved_f, f, (HAWK_N * sizeof(saved_f[0])));
    memcpy(saved_g, g, (HAWK_N * sizeof(saved_g[0])));
    memcpy(saved_h1, h1, (HAWK_N_WORDS32 * sizeof(saved_h1[0])));
    for (size_t i = 0U; i < HAWK_N; i++) {
        fp[i / 32U] |= ((uint32_t)f[i] & 1U) << (i % 32U);
        gp[i / 32U] |= ((uint32_t)g[i] & 1U) << (i % 32U);
    }
    binary_product(h0, fp, t0);
    binary_product(h1, F, product);
    for (size_t i = 0U; i < HAWK_N_WORDS32; i++) {
        t0[i] ^= product[i];
    }
    binary_product(h0, gp, t1);
    binary_product(h1, G, product);
    for (size_t i = 0U; i < HAWK_N_WORDS32; i++) {
        t1[i] ^= product[i];
    }
    phase = 1U;
    return 0;
}

int HawkFpgaSendX(const int32_t *x0, const int32_t *x1)
{
    int32_t w1[HAWK_N];
    int sign = 0;
    assert(phase == 1U);
    sampled_norm = 0U;
    for (size_t i = 0U; i < HAWK_N; i++) {
        int64_t acc = 0;
        sampled_norm += (uint64_t)((int64_t)x0[i] * x0[i] + (int64_t)x1[i] * x1[i]);
        for (size_t j = 0U; j < HAWK_N; j++) {
            size_t k = (i + HAWK_N - j) % HAWK_N;
            int64_t term = (int64_t)saved_f[j] * x1[k] - (int64_t)saved_g[j] * x0[k];
            acc += j > i ? -term : term;
        }
        assert(acc >= INT32_MIN && acc <= INT32_MAX);
        w1[i] = (int32_t)acc;
        if (sign == 0 && acc != 0) {
            sign = acc > 0 ? 1 : -1;
        }
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        int64_t difference = (int64_t)bit(saved_h1, i) - (sign < 0 ? -w1[i] : w1[i]);
        assert(difference % 2 == 0);
        saved_s1[i] = (int32_t)(difference / 2);
    }
    phase = 2U;
    return 0;
}

int HawkFpgaReceiveS1(int32_t *s1)
{
    assert(phase == 2U);
    memcpy(s1, saved_s1, (HAWK_N * sizeof(saved_s1[0])));
    phase = 0U;
    return 0;
}

static int32_t scaled(int32_t x, unsigned shift)
{
    int64_t value = (int64_t)x * (INT64_C(1) << shift);
    if (value < INT32_MIN || value > INT32_MAX) {
        scaling_overflow = 1;
        return 0;
    }
    return (int32_t)value;
}

static int rebuild_reference(const uint32_t *h0, const int32_t *q00,
                              const int32_t *q01, const int32_t *w1, int32_t *w0)
{
    const unsigned h00 = rtl_parameters ? 9U : HAWK_Q00_HIGH_BITS;
    const unsigned h01 = rtl_parameters ? 12U : HAWK_Q01_HIGH_BITS;
    const unsigned hs1 = rtl_parameters ? 9U : HAWK_S1_HIGH_BITS;
    const unsigned hs0 = rtl_parameters ? 13U : HAWK_S0_HIGH_BITS;
    const unsigned s00 = 29U - h00, s01 = 29U - h01, sw = 28U - hs1;
    const unsigned logn = log2_uint(HAWK_N);
    const unsigned sh0 = 1U + sw + s01 - logn - s00;
    int32_t a[HAWK_N], b[HAWK_N], c[HAWK_N], tmp[HAWK_N], quotient[HAWK_N];
    int64_t alpha = (int64_t)q00[0] * (INT64_C(1) << (s00 + 1U - logn));

    scaling_overflow = 0;
    if (q00[0] < 0) {
        return -1;
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        tmp[i] = i == 0U ? 0 : scaled(q00[i], s00);
    }
    if (scaling_overflow) { return -1; }
    fft(tmp, a, HAWK_N);
    for (size_t i = 0U; i < HAWK_N; i++) {
        tmp[i] = scaled(q01[i], s01);
    }
    if (scaling_overflow) { return -1; }
    fft(tmp, b, HAWK_N);
    for (size_t i = 0U; i < HAWK_N; i++) {
        tmp[i] = scaled(w1[i], sw);
    }
    if (scaling_overflow) { return -1; }
    fft(tmp, c, HAWK_N);
    for (size_t i = 0U; i < HAWK_N / 2U; i++) {
        int64_t denominator = alpha + a[i];
        int64_t real = (int64_t)b[i] * c[i] - (int64_t)b[i + HAWK_N/2U] * c[i + HAWK_N/2U];
        int64_t imag = (int64_t)b[i] * c[i + HAWK_N/2U] + (int64_t)b[i + HAWK_N/2U] * c[i];
        if (denominator <= 0 || denominator >= (INT64_C(1) << 30) ||
            real / denominator < INT32_MIN || real / denominator > INT32_MAX ||
            imag / denominator < INT32_MIN || imag / denominator > INT32_MAX) {
            return -1;
        }
        quotient[i] = (int32_t)(real / denominator);
        quotient[i + HAWK_N/2U] = (int32_t)(imag / denominator);
    }
    ifft(quotient, tmp, HAWK_N);
    for (size_t i = 0U; i < HAWK_N; i++) {
        int64_t value = (int64_t)tmp[i] + ((int64_t)bit(h0, i) << sh0);
        /* Algorithm 18, line 28: round with c_s0, not c_q00. */
        if (rtl_parameters != 1) { value += INT64_C(1) << sh0; }
        int64_t divisor = INT64_C(1) << (1U + (rtl_parameters == 1 ? s00 : sh0));
        int64_t z = value / divisor;
        if (value < 0 && value % divisor != 0) {
            z--;
        }
        if (z < -(INT64_C(1) << hs0) || z >= (INT64_C(1) << hs0)) {
            return -1;
        }
        w0[i] = (int32_t)((int64_t)bit(h0, i) - 2*z);
    }
    return 0;
}

static uint32_t mul(uint32_t a, uint32_t b, uint32_t p)
{
    return (uint32_t)((uint64_t)a * b % p);
}

static uint32_t power(uint32_t a, uint32_t exponent, uint32_t p)
{
    uint32_t result = 1U;
    while (exponent != 0U) {
        if (exponent & 1U) {
            result = mul(result, a, p);
        }
        a = mul(a, a, p);
        exponent >>= 1;
    }
    return result;
}

static int polyqnorm_reference(const int32_t *q00, const int32_t *q01,
                               const int32_t *w0, const int32_t *w1,
                               uint32_t p, uint32_t g, uint32_t *result)
{
    uint32_t values[4][HAWK_N], d[HAWK_N], e[HAWK_N], sum = 0U;
    const int32_t *inputs[] = {q00, q01, w0, w1};
    for (size_t k = 0U; k < 4U; k++) {
        for (size_t i = 0U; i < HAWK_N; i++) {
            int64_t x = inputs[k][i] % (int64_t)p;
            values[k][i] = (uint32_t)(x < 0 ? x + p : x);
        }
        NTT(values[k], g, p, HAWK_N);
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        if (values[0][i] == 0U) {
            return -1;
        }
        d[i] = mul(values[3][i], power(values[0][i], p-2U, p), p);
        e[i] = (uint32_t)(((uint64_t)values[2][i] + mul(d[i], values[1][i], p)) % p);
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        uint32_t term = mul(mul(values[0][i], e[i], p), e[HAWK_N-1U-i], p);
        sum = (uint32_t)(((uint64_t)sum + term + mul(d[i], values[3][HAWK_N-1U-i], p)) % p);
    }
    *result = sum;
    return 0;
}

int HawkFpgaVerify(const uint32_t *h0, const int32_t *q00, const int32_t *q01,
                   const int32_t *w1, uint32_t *error)
{
    int32_t w0[HAWK_N];
    uint32_t r1, r2;
    int positive = 0;
    uint64_t threshold = rtl_parameters ?
        (8ULL * HAWK_N * 10469U * 10469U + (1ULL << 25)) >> 26 : NORM_THR;
    assert(phase == 0U);
    *error = 1U;
    for (size_t i = 0U; i < HAWK_N; i++) {
        if (w1[i] != 0) {
            positive = w1[i] > 0;
            break;
        }
    }
    if (!positive || rebuild_reference(h0, q00, q01, w1, w0) != 0 ||
        polyqnorm_reference(q00, q01, w0, w1, P1, G1, &r1) != 0 ||
        polyqnorm_reference(q00, q01, w0, w1, P2, G2, &r2) != 0) {
        return 0;
    }
    if (r1 == r2 && r1 % HAWK_N == 0U) {
        verified_norm = r1 / HAWK_N;
        if (check_norm) {
            assert(verified_norm == sampled_norm);
            const char *directory = getenv("HAWK_VECTOR_DIR");
            if (directory != NULL) {
                static unsigned vector_index;
                char path[1024];
                int length = snprintf(path, sizeof path, "%s/verify_%u_%u.txt",
                                      directory, (unsigned)HAWK_N, vector_index++);
                assert(length > 0 && (size_t)length < sizeof path);
                FILE *output = fopen(path, "w");
                assert(output != NULL);
                fprintf(output, "%u %u %u\n", (unsigned)HAWK_N, r1, r2);
                for (size_t i = 0; i < HAWK_N_WORDS32; i++) fprintf(output, "%u\n", h0[i]);
                const int32_t *vectors[] = {q00, q01, w1, w0};
                for (unsigned k = 0; k < 4; k++)
                    for (size_t i = 0; i < HAWK_N; i++) fprintf(output, "%d\n", vectors[k][i]);
                assert(fclose(output) == 0);
            }
        }
        *error = verified_norm > threshold;
    }
    return 0;
}

#ifndef HAWK_HELLOWORLD_TEST
int main(void)
{
    uint8_t pub[HAWK_PUB_BYTES], priv[HAWK_PRIV_BYTES], sig[HAWK_SIG_BYTES];
    uint8_t message[137];
    unsigned rtl_rejections = 0U;
    unsigned constants_rejections = 0U;

    keygen(pub, priv);
    printf("PASS pipeline keygen %s candidates=%lu\n", HAWK_NAME, (unsigned long)rng_calls);
    fflush(stdout);
    for (unsigned testcase = 0U; testcase < 3U; testcase++) {
        size_t length = testcase == 0U ? 0U : testcase == 1U ? 17U : sizeof message;
        for (size_t i = 0U; i < sizeof message; i++) {
            message[i] = (uint8_t)(i * 13U + testcase * 23U);
        }
        sign_attempts = 0U;
        assert(hawk_sign(sig, priv, message, length) == 0);
        rtl_parameters = 0;
        check_norm = 1;
        assert(hawk_verify(sig, sizeof sig, pub, sizeof pub, message, length) == 1);
        check_norm = 0;
        printf("PASS pipeline sign/verify %s message=%u attempts=%lu norm=%llu\n",
               HAWK_NAME, testcase, (unsigned long)sign_attempts,
               (unsigned long long)verified_norm);
        fflush(stdout);
        rtl_parameters = 1;
        if (hawk_verify(sig, sizeof sig, pub, sizeof pub, message, length) != 1) {
            rtl_rejections++;
        }
        /* Isolate the constants mismatch after fixing only line 28. */
        rtl_parameters = 2;
        if (hawk_verify(sig, sizeof sig, pub, sizeof pub, message, length) != 1) {
            constants_rejections++;
        }
        rtl_parameters = 0;
        /* A different message must not verify with the same signature. */
        message[0] ^= 1U;
        assert(hawk_verify(sig, sizeof sig, pub, sizeof pub, message,
                           length == 0U ? 1U : length) == 0);
        message[0] ^= 1U;
        sig[HAWK_SIG_BYTES-1U] |= 0x80U;
        assert(hawk_verify(sig, sizeof sig, pub, sizeof pub, message, length) == 0);
    }
    printf("HISTORICAL RTL AUDIT %s: %u/3 rejected by the OLD arithmetic/constants model\n",
           HAWK_NAME, rtl_rejections);
    printf("HISTORICAL CONSTANTS AUDIT %s: %u/3 rejected after correcting only OLD RebuildS0 rounding\n",
           HAWK_NAME, constants_rejections);
    printf("PASS pipeline %s (mathematical accelerator backend)\n", HAWK_NAME);
    return 0;
}

#endif
