#ifndef SAMPLER_H
#define SAMPLER_H

#include <stdint.h>
#include <stddef.h>

int SamplerSign(const uint8_t *seed,
                size_t seed_len,
                const uint8_t *t,
                int16_t *x);

#endif