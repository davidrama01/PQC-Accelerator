#include "towersolver.h"
#include "basic.h"
#include "fft_transform.h"
#include <stdint.h>
#include <string.h>

/* Calcula gcd(a,b) y u,v tales que u*a - v*b = gcd(a,b). */
void extended_gcd(int32_t a, int32_t b,
                  int32_t *gcd,
                  int32_t *x,
                  int32_t *y)
{
    int32_t old_r = a, r = b;
    int32_t old_s = 1, s = 0;
    int32_t old_t = 0, t = 1;

    while (r != 0) {
        int64_t q = old_r / r;

        int64_t tmp;

        tmp = old_r;
        old_r = r;
        r = tmp - q * r;

        tmp = old_s;
        old_s = s;
        s = tmp - q * s;

        tmp = old_t;
        old_t = t;
        t = tmp - q * t;
    }

    *gcd = old_r;
    *x = old_s;
    *y = -old_t;
}

/* Aplica la reduccion de Babai sin cambiar la ecuacion fG - gF = 1. */
void reduce(int32_t *f, int32_t *g, int32_t *f_solve, int32_t *g_solve, int32_t n, int32_t *f_reduce, int32_t *g_reduce)
{
    int32_t f_fft[n], g_fft[n], f_solve_fft[n], g_solve_fft[n];
    int32_t f_adj[n], g_adj[n], f_adj_fft[n], g_adj_fft[n];
    int32_t fft_mul_1[n], fft_mul_2[n], fft_mul_3[n], fft_mul_4[n];
    int32_t fft_sum_1[n], fft_sum_2[n];
    int32_t fft_division[n];
    int32_t kg_fft[n], kf_fft[n];
    int32_t f_reduce_fft[n], g_reduce_fft[n];

    do {

        reciprocal(f, f_adj, n);
        reciprocal(g, g_adj, n);

        fft(f_adj, f_adj_fft, n);
        fft(g_adj, g_adj_fft, n);
        fft(f, f_fft, n);
        fft(g, g_fft, n);
        fft(f_solve, f_solve_fft, n);
        fft(g_solve, g_solve_fft, n);

        fft_mul(f_solve_fft, f_adj_fft, fft_mul_1, n);
        fft_mul(g_solve_fft, g_adj_fft, fft_mul_2, n);
        fft_mul(f_fft, f_adj_fft, fft_mul_3, n);
        fft_mul(g_fft, g_adj_fft, fft_mul_4, n);

        for (uint32_t i = 0U; i < n; i++) {
            fft_sum_1[i] = fft_mul_1[i] + fft_mul_2[i];
            fft_sum_2[i] = fft_mul_3[i] + fft_mul_4[i];
        }

        fft_div(fft_sum_1, fft_sum_2, fft_division, n);

        fft_mul(fft_division, f_fft, kf_fft, n);
        fft_mul(fft_division, g_fft, kg_fft, n);

        for (uint32_t i = 0U; i < n; i++) {
            f_reduce_fft[i] = f_solve_fft[i] - kf_fft[i];
            g_reduce_fft[i] = g_solve_fft[i] - kg_fft[i];
        }

        ifft(f_reduce_fft, f_reduce, n);
        ifft(g_reduce_fft, g_reduce, n);

        memcpy(f_solve, f_reduce, n * sizeof(int32_t));
        memcpy(g_solve, g_reduce, n * sizeof(int32_t));
    } while (!poly_is_zero(fft_division, n));
    
}

/* Resuelve recursivamente fG - gF = 1 mediante normas, lifting y reduccion. */
int towersolver(int32_t *f, int32_t *g, int32_t *f_solve, int32_t *g_solve, int32_t n)
{
    int32_t u, v, gcd;
    if (n == 1)
    {
        extended_gcd(*f, *g, &gcd, &u, &v);
        if (gcd != 1 && gcd != -1) {
            return -1;
        }
        *f_solve = v / gcd;
        *g_solve = u / gcd;
    } else 
    {
        int32_t f_prim[n/2U];
        int32_t g_prim[n/2U];
        int32_t f_prim_solve[n/2U];
        int32_t g_prim_solve[n/2U];
        norm_ring(f, f_prim, n);
        norm_ring(g, g_prim, n);
        if (towersolver(f_prim, g_prim, f_prim_solve, g_prim_solve, n / 2U) != 0) {
            return -1;
        }
        int32_t f_adj[n];
        int32_t g_adj[n];
        poly_conj(f, f_adj, n);
        poly_conj(g, g_adj, n);
        int32_t f_solve_exp[n];
        int32_t g_solve_exp[n];
        expand_ring(f_prim_solve, f_solve_exp, n);
        expand_ring(g_prim_solve, g_solve_exp, n);
        int32_t f_prod[n];
        int32_t g_prod[n];
        poly_mul(g_adj, f_solve_exp, f_prod, n);
        poly_mul(f_adj, g_solve_exp, g_prod, n);
        reduce(f, g, f_prod, g_prod, n, f_solve, g_solve);
    }
    return 0;
}

