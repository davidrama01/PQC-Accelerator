#include <string.h>
#include "decode.h"
#include "hawk_params.h"

uint64_t DecodeInt(const uint8_t *buf,
                   size_t k_bits)
{
    uint64_t x = 0;

    if (buf == NULL || k_bits > 64) {
        return 0;
    }

    for (size_t i = 0; i < k_bits; i++) {
        size_t byte_pos = i / 8;
        size_t bit_pos  = i % 8;

        uint64_t bit = (buf[byte_pos] >> bit_pos) & 1ULL;
        x |= bit << i;
    }

    return x;
}

int DecodePrivate(Hawk512PrivateKey *out,
                  const uint8_t *priv,
                  size_t priv_len)
{
    size_t offset = 0;

    if (out == NULL || priv == NULL) {
        return -1;
    }

    if (priv_len != HAWK512_PRIV_BYTES) {
        return -2;
    }

    memcpy(out->kgseed, priv + offset, HAWK512_KGSEED_BYTES);
    offset += HAWK512_KGSEED_BYTES;

    memcpy(out->F_mod2, priv + offset, HAWK512_N_BYTES);
    offset += HAWK512_N_BYTES;

    memcpy(out->G_mod2, priv + offset, HAWK512_N_BYTES);
    offset += HAWK512_N_BYTES;

    memcpy(out->hpub, priv + offset, HAWK512_HPUB_BYTES);
    offset += HAWK512_HPUB_BYTES;

    if (offset != HAWK512_PRIV_BYTES) {
        return -3;
    }

    return 0;
}