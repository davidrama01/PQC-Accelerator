#include "basic.h"
#include "decode.h"
#include "encode.h"
#include "hawk_params.h"
#include "keygen.h"
#include "regenerate.h"
#include "shake256.h"
#include "towersolver.h"

#include <stdarg.h>
#include <complex.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t rng_state = 0x6A09E667U;
static uint32_t rng_calls;

static uint32_t xorshift32(void)
{
    uint32_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
}

int Rnd(uint8_t *out, size_t num_bits)
{
    if ((num_bits & 7U) != 0U) {
        return -1;
    }
    if (++rng_calls > 10000U) {
        fprintf(stderr, "FAIL keygen exceeded 10000 candidates\n");
        exit(EXIT_FAILURE);
    }
    for (size_t i = 0; i < num_bits / 8U; i++) {
        if ((i & 3U) == 0U) {
            (void)xorshift32();
        }
        out[i] = (uint8_t)(rng_state >> (8U * (i & 3U)));
    }
    return 0;
}

int xil_printf(const char *format, ...)
{
    (void)format;
    return 0;
}

int main(void)
{
    uint8_t pub[HAWK_PUB_BYTES];
    uint8_t priv[HAWK_PRIV_BYTES];
    Hawk512PrivateKey decoded;

    memset(pub, 0xA5, sizeof pub);
    memset(priv, 0xA5, sizeof priv);
    keygen(pub, priv);

    if (DecodePrivate(&decoded, priv, sizeof priv) != 0) {
        printf("FAIL private-key decoding\n");
        return EXIT_FAILURE;
    }

    uint8_t expected_hpub[HAWK_HPUB_BYTES];
    shake256(expected_hpub, sizeof expected_hpub, pub, sizeof pub);
    if (memcmp(decoded.hpub, expected_hpub, sizeof expected_hpub) != 0) {
        printf("FAIL hpub does not match public key\n");
        return EXIT_FAILURE;
    }

    int8_t f8[HAWK_N];
    int8_t g8[HAWK_N];
    int32_t f[HAWK_N];
    int32_t g[HAWK_N];
    int32_t F[HAWK_N];
    int32_t G[HAWK_N];
    uint8_t F_bits[HAWK_N];
    uint8_t G_bits[HAWK_N];
    uint8_t F_packed[HAWK_N_BYTES];
    uint8_t G_packed[HAWK_N_BYTES];

    if (RegenerateFG(decoded.kgseed, f8, g8) != 0) {
        printf("FAIL f,g regeneration\n");
        return EXIT_FAILURE;
    }
    for (uint32_t i = 0U; i < HAWK_N; i++) {
        f[i] = f8[i];
        g[i] = g8[i];
    }

    int32_t f_adj[HAWK_N];
    int32_t g_adj[HAWK_N];
    int32_t q00_f[HAWK_N];
    int32_t q00_g[HAWK_N];
    int32_t q00[HAWK_N];
    reciprocal(f, f_adj, HAWK_N);
    reciprocal(g, g_adj, HAWK_N);
    poly_mul(f, f_adj, q00_f, HAWK_N);
    poly_mul(g, g_adj, q00_g, HAWK_N);
    for (uint32_t i = 0U; i < HAWK_N; i++) {
        q00[i] = q00_f[i] + q00_g[i];
    }
    double complex inverse_sum = 0.0;
    for (uint32_t k = 0U; k < HAWK_N; k++) {
        double angle = PI * (double)(2U * k + 1U) / (double)HAWK_N;
        double complex root = cos(angle) + I * sin(angle);
        double complex value = 0.0;
        for (uint32_t i = HAWK_N; i-- > 0U;) {
            value = value * root + (double)q00[i];
        }
        inverse_sum += 1.0 / value;
    }
    double independent_inverse_0 = creal(inverse_sum) / (double)HAWK_N;
    int beta_status = hawk_check_q00_beta(q00, HAWK_N);
    int reference_accept = independent_inverse_0 < HAWK_BETA0;
    if (beta_status != reference_accept) {
        printf("FAIL beta0 decision: fixed-point=%d reference=%d "
               "inverse0=%.17g\n",
               beta_status, reference_accept, independent_inverse_0);
        return EXIT_FAILURE;
    }
    if (independent_inverse_0 >= HAWK_BETA0) {
        printf("FAIL accepted key violates beta0: %.17g\n",
               independent_inverse_0);
        return EXIT_FAILURE;
    }
    if (towersolver(f, g, F, G, HAWK_N) != 0) {
        printf("FAIL encoded seed does not reproduce a solvable key\n");
        return EXIT_FAILURE;
    }
    for (uint32_t i = 0U; i < HAWK_N; i++) {
        F_bits[i] = (uint8_t)((uint32_t)F[i] & 1U);
        G_bits[i] = (uint8_t)((uint32_t)G[i] & 1U);
    }
    PackBits(F_packed, (const int8_t *)F_bits, HAWK_N);
    PackBits(G_packed, (const int8_t *)G_bits, HAWK_N);
    if ((memcmp(decoded.F_mod2, F_packed, HAWK_N_BYTES) != 0) ||
        (memcmp(decoded.G_mod2, G_packed, HAWK_N_BYTES) != 0)) {
        printf("FAIL encoded F/G parity does not match regenerated solution\n");
        return EXIT_FAILURE;
    }

    printf("PASS keygen end-to-end after %lu candidates\n",
           (unsigned long)rng_calls);
    return EXIT_SUCCESS;
}
