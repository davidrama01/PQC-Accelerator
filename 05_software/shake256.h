#ifndef SHAKE256_H
#define SHAKE256_H

#include <stddef.h>
#include <stdint.h>

void shake256(uint8_t *out, size_t outlen,
              const uint8_t *in, size_t inlen);

#endif