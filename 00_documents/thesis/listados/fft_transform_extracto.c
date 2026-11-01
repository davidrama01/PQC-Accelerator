/* Extracto documental de fft_transform.c.
   Twiddles, FFT directa y envoltorio de producto; se omiten IFFT, producto escalado y division.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

void delta (uint32_t k, int64_t *real_delta, int64_t *imag_delta) {
    const double SCALE = (double)(1ULL << 31);
    uint32_t k_rev = bit_reverse(k, 10U);
    double real_part = cos(DELTA_ANGLE * (double)k_rev) * SCALE;
    double imag_part = sin(DELTA_ANGLE * (double)k_rev) * SCALE;
    *real_delta = (int64_t)llround(real_part);
    *imag_delta = (int64_t)llround(imag_part);
}

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

int fft_mul(const int32_t *a_fft, const int32_t *b_fft,
            int32_t *c_fft, uint32_t n)
{
    return fft_mul_scaled(a_fft, b_fft, c_fft, n, 1U);
}
