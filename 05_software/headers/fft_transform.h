#ifndef FFT_TRANSFORM_H
#define FFT_TRANSFORM_H

void delta (uint32_t k, int64_t *real_delta, int64_t *imag_delta);

void fft (const int32_t *a, int32_t *a_fft, uint32_t n);

void ifft (const int32_t *a, int32_t *a_ifft, uint32_t n);

void fft_mul (int32_t *a_fft, int32_t *b_fft, int32_t *c_fft, uint32_t n);

void fft_div (int32_t *a_fft, int32_t *b_fft, int32_t *c_fft, uint32_t n);
#endif