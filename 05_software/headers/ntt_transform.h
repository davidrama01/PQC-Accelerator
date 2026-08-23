#ifndef NTT_TRANSFORM_H
#define NTT_TRANSFORM_H

#include <stdint.h>

uint32_t find_generator(uint32_t p);

static uint32_t mod_mul(uint32_t a, uint32_t b, uint32_t p);

static uint32_t mod_pow(uint32_t base, uint32_t exp, uint32_t p);

uint32_t compute_gamma(uint32_t g, uint32_t p, uint32_t n);

uint32_t gamma_function(uint32_t g, uint32_t p, uint32_t n, uint32_t index);

uint32_t gamma_function(uint32_t g, uint32_t p, uint32_t n, uint32_t index);

void NTT(uint32_t *u, uint32_t g, uint32_t p, uint32_t n);

uint32_t IsInvertible (const int32_t *u, uint32_t g, uint32_t p, uint32_t n);

uint32_t IsInvertible_mod2 (const int32_t *u, uint32_t n);

#endif /* NTT_TRANSFORM_H */