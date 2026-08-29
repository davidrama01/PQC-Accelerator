#ifndef SHAKE256_H
#define SHAKE256_H

#include <stddef.h>
#include <stdint.h>

void shake256(uint8_t *out, size_t outlen,
              const uint8_t *in, size_t inlen);

uint64_t DecodeIntBytes(const uint8_t *buf, size_t k_bits);

void EncodeIntBytes(uint8_t *out, uint64_t x, size_t k_bits);

void shake256w(uint64_t *w, size_t nwords,
               const uint8_t *m, size_t mlen);

void shake256x4(uint64_t *out, size_t nwords,
                const uint8_t *m, size_t mlen);

#endif