#include "towersolver.h"
#include "ng_inner.h"
#include "xil_printf.h"

#include <stdint.h>

/* Perfiles oficiales del NTRU solver para HAWK. */
static const ntru_profile SOLVE_HAWK_256 = {
    1, 8, 8,
    { 1, 1, 1, 2, 3, 5, 9, 17, 34, 0, 0 },
    { 1, 1, 2, 4, 7, 13, 26, 50, 0, 0 },
    { 1, 1, 1, 2, 3, 3, 3, 4, 0, 0 },
    14,
    { 0, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127 },
    { 0, 0, 1, 2, 2, 2, 2, 2, 2, 3, 3 }
};

static const ntru_profile SOLVE_HAWK_512 = {
    1, 9, 9,
    { 1, 1, 1, 2, 3, 6, 11, 21, 41, 82, 0 },
    { 1, 2, 3, 5, 8, 16, 31, 61, 121, 0 },
    { 1, 1, 1, 2, 2, 3, 3, 4, 6, 0 },
    11,
    { 0, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127 },
    { 0, 0, 1, 2, 2, 2, 2, 2, 2, 2, 3 }
};

static const ntru_profile SOLVE_HAWK_1024 = {
    1, 10, 10,
    { 1, 1, 2, 2, 4, 7, 13, 25, 48, 96, 191 },
    { 1, 2, 3, 5, 10, 19, 37, 72, 143, 284 },
    { 1, 1, 2, 2, 3, 3, 3, 4, 4, 7 },
    9,
    { 0, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127 },
    { 0, 0, 1, 2, 2, 2, 2, 2, 2, 3, 3 }
};

static const ntru_profile *get_profile(uint32_t n, unsigned *logn)
{
    switch (n) {
    case 256U:
        *logn = 8U;
        return &SOLVE_HAWK_256;
    case 512U:
        *logn = 9U;
        return &SOLVE_HAWK_512;
    case 1024U:
        *logn = 10U;
        return &SOLVE_HAWK_1024;
    default:
        return NULL;
    }
}

int hawk_check_q00_beta(const int32_t *q00, uint32_t n)
{
    unsigned logn;
    fxr beta0;

    if (q00 == NULL || get_profile(n, &logn) == NULL) {
        return -1;
    }

    switch (n) {
    case 256U:
        beta0 = fxr_of_scaled32(17179869U); /* 1/250 */
        break;
    case 512U:
        beta0 = fxr_of_scaled32(4294967U);  /* 1/1000 */
        break;
    case 1024U:
        beta0 = fxr_of_scaled32(1431655U);  /* 1/3000 */
        break;
    default:
        return -1;
    }

    fxr values[n];
    for (uint32_t i = 0U; i < n; i++) {
        values[i] = fxr_of(q00[i]);
    }
    vect_FFT(logn, values);
    for (uint32_t i = 0U; i < (n >> 1); i++) {
        values[i] = fxr_inv(values[i]);
    }
    for (uint32_t i = n >> 1; i < n; i++) {
        values[i] = fxr_zero;
    }
    vect_iFFT(logn, values);

    return fxr_lt(beta0, values[0]) ? 0 : 1;
}

int towersolver(int32_t *f, int32_t *g, int32_t *f_solve,
                int32_t *g_solve, int32_t n)
{
    unsigned logn;
    const ntru_profile *profile = get_profile((uint32_t)n, &logn);
    if (profile == NULL) {
        xil_printf("towersolver: unsupported n=%ld\r\n", (long)n);
        return -1;
    }

    int8_t f_small[n];
    int8_t g_small[n];
    for (uint32_t i = 0U; i < (uint32_t)n; i++) {
        if ((f[i] < -127) || (f[i] > 127) ||
            (g[i] < -127) || (g[i] > 127)) {
            xil_printf("towersolver: input out of int8 range at %lu\r\n",
                       (unsigned long)i);
            return -1;
        }
        f_small[i] = (int8_t)f[i];
        g_small[i] = (int8_t)g[i];
    }

    /* El solver usa limbs de 31 bits y necesita exactamente 6*n palabras. */
    uint32_t tmp[6U * (uint32_t)n];
    int status = solve_NTRU(profile, logn, f_small, g_small, tmp);
    if (status != SOLVE_OK) {
        xil_printf("towersolver: solve_NTRU failed status=%d n=%ld\r\n",
                   status, (long)n);
        return -1;
    }

    const int8_t *F = (const int8_t *)(const void *)tmp;
    const int8_t *G = F + n;
    for (uint32_t i = 0U; i < (uint32_t)n; i++) {
        f_solve[i] = (int32_t)F[i];
        g_solve[i] = (int32_t)G[i];
    }

    xil_printf("towersolver: solved n=%ld\r\n", (long)n);
    return 0;
}
