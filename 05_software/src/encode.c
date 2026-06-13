#include <string.h>
#include "encode.h"
#include "hawk_params.h"

void EncodeInt(uint8_t *buf,
               uint64_t x,
               size_t k_bits)
{
    size_t nbytes = (k_bits + 7) / 8;

    for (size_t i = 0; i < nbytes; i++) {
        buf[i] = 0;
    }

    for (size_t i = 0; i < k_bits; i++) {

        size_t byte_pos = i / 8;
        size_t bit_pos  = i % 8;

        buf[byte_pos] |=
            ((x >> i) & 1ULL) << bit_pos;
    }
}

int EncodePrivate(uint8_t *priv,
                  size_t priv_len,
                  const uint8_t *kgseed,
                  const uint8_t *F_mod2,
                  const uint8_t *G_mod2,
                  const uint8_t *hpub)
{
    size_t offset = 0;

    if (priv == NULL || kgseed == NULL || F_mod2 == NULL ||
        G_mod2 == NULL || hpub == NULL) {
        return -1;
    }

    if (priv_len != HAWK512_PRIV_BYTES) {
        return -2;
    }

    memcpy(priv + offset, kgseed, HAWK512_KGSEED_BYTES);
    offset += HAWK512_KGSEED_BYTES;

    memcpy(priv + offset, F_mod2, HAWK512_N_BYTES);
    offset += HAWK512_N_BYTES;

    memcpy(priv + offset, G_mod2, HAWK512_N_BYTES);
    offset += HAWK512_N_BYTES;

    memcpy(priv + offset, hpub, HAWK512_HPUB_BYTES);
    offset += HAWK512_HPUB_BYTES;

    return 0;
}