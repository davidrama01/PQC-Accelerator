#ifndef DECODE_H
#define DECODE_H

#include <stdint.h>
#include <stddef.h>
#include "hawk_params.h"

#define HAWK512_KGSEED_BYTES  24
#define HAWK512_N_BYTES       64
#define HAWK512_HPUB_BYTES    32
#define HAWK512_PRIV_BYTES    184

uint64_t DecodeInt(const uint8_t *buf,
                   size_t k_bits);

typedef struct {
    uint8_t kgseed[HAWK512_KGSEED_BYTES];
    uint8_t F_mod2[HAWK512_N_BYTES];
    uint8_t G_mod2[HAWK512_N_BYTES];
    uint8_t hpub[HAWK512_HPUB_BYTES];
} Hawk512PrivateKey;

int DecodePrivate(Hawk512PrivateKey *out,
                  const uint8_t *priv,
                  size_t priv_len);

#endif