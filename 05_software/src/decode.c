#include <string.h>
#include "decode.h"
#include "hawk_params.h"

/* Reconstruye un entero a partir de k bits almacenados en orden LSB-first. */
uint64_t DecodeInt(const uint8_t *bits,
                   size_t k_bits)
{
    uint64_t x = 0;

    if (k_bits > 64U) {
        return 0;
    }
    for (size_t i = 0; i < k_bits; i++) {
        x |= ((uint64_t)bits[i] & 1U) << i;
    }

    return x;
}

/* Separa y decodifica los campos de una clave privada HAWK-512. */
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
