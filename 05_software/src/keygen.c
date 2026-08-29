#include "keygen.h"
#include "hawk_params.h"
#include "Rnd.h"
#include "regenerate.h"
#include "ntt_transform.h"
#include "basic.h"
#include "towersolver.h"
#include "fft_transform.h"
#include "shake256.h"
#include "encode.h"

/* Genera y codifica un par de claves HAWK, reintentando candidatos no validos. */
void keygen(uint8_t *pub, uint8_t *priv)
{
    uint8_t kgseed[HAWK_KGSEED_BYTES];
    int8_t f_words[HAWK_N];
    int8_t g_words[HAWK_N];
    int32_t f_32[HAWK_N];
    int32_t g_32[HAWK_N];
    int32_t f_rec_32[HAWK_N];
    int32_t g_rec_32[HAWK_N];
    int32_t q00_a[HAWK_N];
    int32_t q00_b[HAWK_N];
    int32_t q00[HAWK_N], q01[HAWK_N], q11[HAWK_N];
    int32_t f_solve[HAWK_N], g_solve[HAWK_N];
    int32_t threshold;
    int32_t max_value;
    int32_t f_solve_adj[HAWK_N], g_solve_adj[HAWK_N];
    int32_t q01_partial_1[HAWK_N], q01_partial_2[HAWK_N];
    int32_t q11_partial_1[HAWK_N], q11_partial_2[HAWK_N];

    restart:
    if (Rnd(kgseed, HAWK_KGSEED_BYTES * 8U) != 0) {
        goto restart;
    }
    RegenerateFG(kgseed, f_words, g_words);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        f_32[i] = (int32_t)f_words[i];
        g_32[i] = (int32_t)g_words[i];
    }
    int32_t f_inv= IsInvertible_mod2(f_32, HAWK_N);
    int32_t g_inv= IsInvertible_mod2(g_32, HAWK_N);
    if ((f_inv == 0U) || (g_inv == 0U)) 
    {
        goto restart;
    }
    threshold = norm(f_32, g_32, HAWK_N);
    if ((int64_t)threshold * 1000000LL <= 2LL * HAWK_N * HAWK_SIGMA_KREC * HAWK_SIGMA_KREC)
    {
        goto restart;
    }

    reciprocal(f_32, f_rec_32, HAWK_N);
    reciprocal(g_32, g_rec_32, HAWK_N);

    poly_mul(f_32, f_rec_32, q00_a, HAWK_N);
    poly_mul(g_32, g_rec_32, q00_b, HAWK_N);

    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        q00[i] = q00_a[i] + q00_b[i];
    }

    uint32_t p1_inv = IsInvertible(q00, G1, P1, HAWK_N);
    uint32_t p2_inv = IsInvertible(q00, G2, P2, HAWK_N);
    if ((p1_inv == 0U) || (p2_inv == 0U))
    {
        goto restart;
    }

    if (hawk_check_q00_beta(q00, HAWK_N) != 1)
    {
        goto restart;
    }

    if (towersolver(f_32, g_32, f_solve, g_solve, HAWK_N) != 0) {
        goto restart;
    }

    max_value = infinite_norm(f_solve, g_solve, HAWK_N);
    if (max_value > 127) {
        goto restart;
    }

    reciprocal(f_solve, f_solve_adj, HAWK_N);
    reciprocal(g_solve, g_solve_adj, HAWK_N);

    poly_mul(f_solve, f_rec_32, q01_partial_1, HAWK_N);
    poly_mul(g_solve, g_rec_32, q01_partial_2, HAWK_N);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        int64_t value = (int64_t)q01_partial_1[i] + q01_partial_2[i];
        if ((value > INT32_MAX) || (value < INT32_MIN)) {
            goto restart;
        }
        q01[i] = (int32_t)value;
    }

    poly_mul(f_solve, f_solve_adj, q11_partial_1, HAWK_N);
    poly_mul(g_solve, g_solve_adj, q11_partial_2, HAWK_N);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        int64_t value = (int64_t)q11_partial_1[i] + q11_partial_2[i];
        if ((value > INT32_MAX) || (value < INT32_MIN)) {
            goto restart;
        }
        q11[i] = (int32_t)value;
    }

    int32_t q11_limit = (int32_t)(1U << HAWK_Q11_BITS);

    for (uint32_t i = 1U; i < HAWK_N; i++)
    {
        if (q11[i] >= q11_limit || q11[i] <= -q11_limit) {
            goto restart;
        }
    }

    int result_pub = EncodePublic(pub, q00, q01, HAWK_N);
    if (result_pub != 0) {
        goto restart;
    }
    int8_t f_solve_mod2[HAWK_N];
    int8_t g_solve_mod2[HAWK_N];
    uint8_t f_solve_packed[HAWK_N_BYTES];
    uint8_t g_solve_packed[HAWK_N_BYTES];
    uint8_t hpub[HAWK_HPUB_BYTES];
    for (uint32_t i = 0U; i < HAWK_N; i++) {
        f_solve_mod2[i] = (int8_t)((uint32_t)f_solve[i] & 1U);
        g_solve_mod2[i] = (int8_t)((uint32_t)g_solve[i] & 1U);
    }
    PackBits(f_solve_packed, f_solve_mod2, HAWK_N);
    PackBits(g_solve_packed, g_solve_mod2, HAWK_N);

    shake256(hpub, HAWK_HPUB_BYTES, pub, HAWK_PUB_BYTES);
    if (EncodePrivate(priv, HAWK_PRIV_BYTES, kgseed,
                      f_solve_packed, g_solve_packed, hpub) != 0) {
        goto restart;
    }
}
