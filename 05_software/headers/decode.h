#ifndef DECODE_H
#define DECODE_H

#include <stdint.h>
#include <stddef.h>
#include "hawk_params.h"

uint64_t DecodeInt(const uint8_t *buf,
                   size_t k_bits);

int DecodePrivate(uint8_t *kgseed,
                  uint8_t *F_mod2,
                  uint8_t *G_mod2,
                  uint8_t *hpub,
                  const uint8_t *priv,
                  size_t priv_len);

#endif
