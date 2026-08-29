#ifndef ENCODE_H
#define ENCODE_H

#include <stdint.h>
#include <stddef.h>

int EncodeInt(int8_t *buf,
              uint32_t x,
              uint32_t k_bits);

void PackBits(uint8_t *out,
              const int8_t *bits,
              uint32_t number_bits);

int EncodePrivate(uint8_t *priv,
                  size_t priv_len,
                  const uint8_t *kgseed,
                  const uint8_t *F_mod2,
                  const uint8_t *G_mod2,
                  const uint8_t *hpub);

int CompressGR(int8_t *y,
               const int32_t *x,
               uint32_t k,
               uint32_t *y_len_bits,
               uint8_t low,
               uint8_t high);

int EncodePublic(uint8_t *pub,
                 int32_t *q00,
                 int32_t *q01,
                 uint32_t n);

int EncodeSignature(uint8_t *sig,
                    uint32_t sig_len_bits,
                    const uint8_t *salt,
                    const int32_t *s1);
                    
#endif
