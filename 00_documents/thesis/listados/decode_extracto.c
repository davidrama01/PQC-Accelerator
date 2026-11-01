/* Extracto documental de decode.c.
   Decodificacion privada y de firma; se omiten DecodePublic y DecompressGR.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

int DecodePrivate(uint8_t *kgseed,
                  uint8_t *F_mod2,
                  uint8_t *G_mod2,
                  uint8_t *hpub,
                  const uint8_t *priv,
                  size_t priv_len)
{
    size_t offset = 0;
    if (kgseed == NULL || F_mod2 == NULL || G_mod2 == NULL ||
        hpub == NULL || priv == NULL) {
        return -1;
    }
    if (priv_len != HAWK_PRIV_BYTES) {
        return -2;
    }
    memcpy(kgseed, priv + offset, HAWK_KGSEED_BYTES);
    offset += HAWK_KGSEED_BYTES;
    memcpy(F_mod2, priv + offset, HAWK_N_BYTES);
    offset += HAWK_N_BYTES;
    memcpy(G_mod2, priv + offset, HAWK_N_BYTES);
    offset += HAWK_N_BYTES;
    memcpy(hpub, priv + offset, HAWK_HPUB_BYTES);
    offset += HAWK_HPUB_BYTES;
    if (offset != HAWK_PRIV_BYTES) {
        return -3;
    }
    return 0;
}

int DecodeSignature(uint8_t *salt,
                    int32_t *s1,
                    const uint8_t *sig,
                    size_t sig_len)
{
    uint8_t bits[(HAWK_SIG_BYTES - HAWK_SALTLEN_BYTES) * 8U];
    const size_t bits_len = sizeof bits;
    size_t used;
    if (salt == NULL || s1 == NULL || sig == NULL) {
        return -1;
    }
    if (sig_len != HAWK_SIG_BYTES) {
        return -2;
    }
    for (size_t i = 0U; i < bits_len; i++) {
        bits[i] = (uint8_t)((sig[HAWK_SALTLEN_BYTES + i / 8U] >>
                              (i % 8U)) & 1U);
    }
    if (DecompressGR(s1, bits, bits_len, HAWK_N, &used,
                      HAWK_S1_LOW_BITS, HAWK_S1_HIGH_BITS) != 0) {
        return -3;
    }
    while (used < bits_len) {
        if (bits[used++] != 0U) {
            return -3;
        }
    }
    memcpy(salt, sig, HAWK_SALTLEN_BYTES);
    return 0;
}
