#ifndef ENCODE_H
#define ENCODE_H

#define HAWK512_KGSEED_BYTES  24
#define HAWK512_N_BYTES       64
#define HAWK512_HPUB_BYTES    32
#define HAWK512_PRIV_BYTES    184

#include <stdint.h>
#include <stddef.h>

void EncodeInt(uint8_t *buf,
               uint64_t x,
               size_t k_bits);

int EncodePrivate(uint8_t *priv,
                  size_t priv_len,
                  const uint8_t *kgseed,
                  const uint8_t *F_mod2,
                  const uint8_t *G_mod2,
                  const uint8_t *hpub);

int CompressGR(uint8_t *y,
               size_t y_max_bytes,
               size_t *y_len_bytes,
               size_t *y_len_bits,
               const int16_t *x,
               size_t k,
               uint32_t low,
               uint32_t high);

int EncodeSignature(uint8_t *sig,
                    size_t sig_len,
                    const uint8_t *salt,
                    const int16_t *s1);
                    
#endif