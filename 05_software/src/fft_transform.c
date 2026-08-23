#include "fft_transform.h"
#include "basic.h"
#include "hawk_params.h"
#include <stdint.h>
#include <math.h>

/* Obtiene en punto fijo las partes real e imaginaria del twiddle Delta[k]. */
void delta (uint32_t k, int64_t *real_delta, int64_t *imag_delta) {
    const double SCALE = (double)(1ULL << 31);
    uint32_t k_rev = bit_reverse(k, 10U);
    double real_part = cos(DELTA_ANGLE * (double)k_rev) * SCALE;
    double imag_part = sin(DELTA_ANGLE * (double)k_rev) * SCALE;
    *real_delta = (int64_t)llround(real_part);
    *imag_delta = (int64_t)llround(imag_part);
}

/* Convierte un polinomio a la representacion FFT negaciclica de HAWK. */
void fft (const int32_t *a, int32_t *a_fft, uint32_t n) {
    int64_t f[n];
    for (uint32_t i = 0; i < n; i++) {
        f[i] = (int64_t)a[i];
    }
    uint32_t t = n/2U;
    uint32_t m = 2U;
    uint32_t v0;
    int64_t eps_real, eps_imag;
    int64_t x1_real, x1_imag, x2_real, x2_imag;
    int64_t t_real, t_imag;
    while (m < n) {
        v0 = 0;
        for (uint32_t u = 0U; u < m/2U; u++) {
            delta (u + m, &eps_real, &eps_imag);
            for (uint32_t v = v0; v < v0 + t/2U; v++) {
                x1_real = f[v];
                x1_imag = f[v + n/2];
                x2_real = f[v + t/2];
                x2_imag = f[v + t/2 + n/2];
                t_real = x2_real * eps_real - x2_imag * eps_imag;
                t_imag = x2_real * eps_imag + x2_imag * eps_real;
                f[v] = ((1LL << 31) * x1_real + t_real) >> 32;
                f[v + n/2U] = ((1LL << 31) * x1_imag + t_imag) >> 32;
                f[v + t/2U] = ((1LL << 31) * x1_real - t_real) >> 32;
                f[v + t/2U + n/2U] = ((1LL << 31) * x1_imag - t_imag) >> 32;
            }
            v0 = v0 + t;
        }
        t = t/2;
        m = 2*m;
    }
    for (uint32_t i = 0U; i < n; i++) {
        a_fft[i] = (int32_t)f[i];
    }
}

/* Convierte una representacion FFT a coeficientes del polinomio. */
void ifft (const int32_t *a, int32_t *a_ifft, uint32_t n) {
    int64_t f[n];
    for (uint32_t i = 0; i < n; i++) {
        f[i] = (int64_t)a[i];
    }
    uint32_t t = 2U;
    uint32_t m = n/2U;
    uint32_t v0;
    int64_t eta_real, eta_imag;
    int64_t x1_real, x1_imag, x2_real, x2_imag;
    int64_t t1_real, t1_imag, t2_real, t2_imag;
    int64_t t_real, t_imag;
    while (m > 1) {
        v0 = 0;
        for (uint32_t u = 0U; u < m/2U; u++) {
            delta (u + m, &eta_real, &eta_imag);
            eta_imag = -eta_imag;
            for (uint32_t v = v0; v < v0 + t/2U; v++) {
                x1_real = f[v];
                x1_imag = f[v + n/2];
                x2_real = f[v + t/2];
                x2_imag = f[v + t/2 + n/2];
                t1_real = x1_real + x2_real;
                t1_imag = x1_imag + x2_imag;
                t2_real = x1_real - x2_real;
                t2_imag = x1_imag - x2_imag;
                f[v] = t1_real >> 1;
                f[v + n/2U] = t1_imag >> 1;
                f[v + t/2U] = (t2_real * eta_real - t2_imag * eta_imag) >> 32;
                f[v + t/2U + n/2U] = (t2_real * eta_imag + t2_imag * eta_real) >> 32;
            }
            v0 = v0 + t;
        }
        t = 2*t;
        m = m/2;
    }
    for (uint32_t i = 0U; i < n; i++) {
        a_ifft[i] = (int32_t)f[i];
    }
}

/* Multiplica componente a componente dos polinomios en representacion FFT. */
void fft_mul(const int32_t *a_fft, const int32_t *b_fft, int32_t *c_fft, uint32_t n)
{
    for (uint32_t i = 0; i < n / 2U; i++) {
        int32_t a_real = a_fft[i];
        int32_t a_imag = a_fft[i + n / 2U];
        int32_t b_real = b_fft[i];
        int32_t b_imag = b_fft[i + n / 2U];

        int64_t c_real = (int64_t)a_real * b_real - (int64_t)a_imag * b_imag;

        int64_t c_imag = (int64_t)a_real * b_imag + (int64_t)a_imag * b_real;

        c_fft[i] = (int32_t)c_real;
        c_fft[i + n / 2U] = (int32_t)c_imag;
    }
}

/* Divide en FFT, redondea el cociente en coeficientes y devuelve FFT(k). */
int fft_div(const int32_t *a_fft, const int32_t *b_fft, int32_t *c_fft, uint32_t n)
{
    int32_t quotient_fixed[n];
    int32_t k_fixed[n];
    int32_t k[n];

    for (uint32_t i = 0; i < n / 2U; i++) {
        int64_t a_real = a_fft[i];
        int64_t a_imag = a_fft[i + n / 2U];
        int64_t b_real = b_fft[i];
        int64_t b_imag = b_fft[i + n / 2U];

        int64_t denominator = b_real * b_real + b_imag * b_imag;

        if (denominator == 0) {
            return -1;
        }

        int64_t numerator_real = a_real * b_real + a_imag * b_imag;

        int64_t numerator_imag = a_imag * b_real - a_real * b_imag;

        double quotient_real = (double)numerator_real / (double)denominator;
        double quotient_imag = (double)numerator_imag / (double)denominator;
        double fixed_real = quotient_real * 65536.0;
        double fixed_imag = quotient_imag * 65536.0;

        if (fixed_real > (double)INT32_MAX || fixed_real < (double)INT32_MIN ||
            fixed_imag > (double)INT32_MAX || fixed_imag < (double)INT32_MIN) {
            return -1;
        }

        quotient_fixed[i] = (int32_t)llround(fixed_real);
        quotient_fixed[i + n / 2U] = (int32_t)llround(fixed_imag);
    }

    ifft(quotient_fixed, k_fixed, n);

    for (uint32_t i = 0U; i < n; i++) {
        int64_t value = k_fixed[i];

        if (value >= 0) {
            k[i] = (int32_t)((value + 32768) / 65536);
        } else {
            k[i] = (int32_t)(-((-value + 32768) / 65536));
        }
    }

    fft(k, c_fft, n);

    return 0;
}
