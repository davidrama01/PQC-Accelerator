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

void keygen(uint8_t *pub, uint32_t publen_bits) 
{
    uint8_t kgseed;
    int8_t f_words[HAWK_N];
    int8_t g_words[HAWK_N];
    int32_t f_32[HAWK_N];
    int32_t g_32[HAWK_N];
    int32_t f_rec_32[HAWK_N];
    int32_t g_rec_32[HAWK_N];
    int32_t q00_a[HAWK_N];
    int32_t q00_b[HAWK_N];
    int32_t q00[HAWK_N], q01[HAWK_N], q10[HAWK_N], q11[HAWK_N];
    int32_t f_solve[HAWK_N], g_solve[HAWK_N];
    double q00_inv_d[HAWK_N];
    int32_t threshold;
    int32_t max_value;
    int32_t f_fft[HAWK_N], g_fft[HAWK_N], f_adj_fft[HAWK_N], g_adj_fft[HAWK_N];
    int32_t f_solve_fft[HAWK_N], g_solve_fft[HAWK_N];
    int32_t f_solve_adj[HAWK_N], g_solve_adj[HAWK_N];
    int32_t f_solve_adj_fft[HAWK_N], g_solve_adj_fft[HAWK_N];
    int32_t q01_partial_mul_1[HAWK_N], q01_partial_mul_2[HAWK_N];
    int32_t q11_partial_mul_1[HAWK_N], q11_partial_mul_2[HAWK_N];
    int32_t q01_ifft[HAWK_N], q11_ifft[HAWK_N];

    restart:
    Rnd(&kgseed, HAWK_KGSEED_BYTES * 8);
    RegenerateFG(&kgseed, f_words, g_words);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        f_32[i] = (int32_t)f_words[i];
        g_32[i] = (int32_t)g_words[i];
    }
    int32_t f_inv= IsInvertible_mod2(f_32);
    int32_t g_inv= IsInvertible_mod2(g_32);
    if ((f_inv == 0U) || (g_inv == 0U)) 
    {
        goto restart;
    }
    threshold = norm(f_32, g_32, HAWK_N);
    if (threshold <= 2 * HAWK_N * HAWK_SIGMA_KREC * HAWK_SIGMA_KREC)
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

    uint32_t p1_inv = IsInvertible(q00, G1, P1, HAWK_N, LOG_BITS);
    uint32_t p2_inv = IsInvertible(q00, G2, P2, HAWK_N, LOG_BITS);
    if ((p1_inv == 0U) || (p2_inv == 0U))
    {
        goto restart;
    }

    poly_inverse(q00, q00_inv_d, HAWK_N);

    if (q00_inv_d[0] >= HAWK_BETA0) 
    {
        goto restart;
    }

    towersolver(f_32, g_32, f_solve, g_solve, HAWK_N);

    max_value = infinite_norm(f_solve, g_solve, HAWK_N);
    if (max_value > 127) {
        goto restart;
    }

    reciprocal(f_solve, f_solve_adj, HAWK_N);
    reciprocal(g_solve, g_solve_adj, HAWK_N);

    fft(f_rec_32, f_adj_fft, HAWK_N);
    fft(g_rec_32, g_adj_fft, HAWK_N);
    fft(f_solve, f_solve_fft, HAWK_N);
    fft(g_solve, g_solve_fft, HAWK_N);
    fft(f_solve_adj, f_solve_adj_fft, HAWK_N);
    fft(g_solve_adj, g_solve_adj_fft, HAWK_N);

    fft_mul(f_solve_fft, f_adj_fft, q01_partial_mul_1, HAWK_N);
    fft_mul(g_solve_fft, g_adj_fft, q01_partial_mul_2, HAWK_N);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        q01[i] = q01_partial_mul_1[i] + q01_partial_mul_2[i];
    }

    fft_mul(f_solve_fft, f_solve_adj_fft, q11_partial_mul_1, HAWK_N);
    fft_mul(g_solve_fft, g_solve_adj_fft, q11_partial_mul_2, HAWK_N);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        q11[i] = q11_partial_mul_1[i] + q11_partial_mul_2[i];
    }

    ifft(q01, q01_ifft, HAWK_N);
    ifft(q11, q11_ifft, HAWK_N);

    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        if (q11_ifft[i] >= (1 << HAWK_Q11_BITS) || q11_ifft[i] < -(1 << HAWK_Q11_BITS)) {
            goto restart;
        }
    }

    int result_pub = EncodePublic(pub, q00, q01_ifft, HAWK_N);
    if (result_pub != 0) {
        goto restart;
    }
    uint8_t hpub[HAWK_HPUB_BYTES];
    uint8_t priv[HAWK_PRIV_BYTES];
    shake256(hpub, HAWK_HPUB_BYTES, pub, publen_bits / 8U);
    EncodePrivate(priv, HAWK_PRIV_BYTES, &kgseed, f_solve, g_solve, hpub);
    return 0;
}