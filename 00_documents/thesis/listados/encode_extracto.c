/* Extracto documental de encode.c.
   Codificacion privada y de firma; se omiten EncodePublic y CompressGR.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

int EncodePrivate(uint8_t *priv,
                  size_t priv_len,
                  const uint8_t *kgseed,
                  const uint8_t *F_mod2,
                  const uint8_t *G_mod2,
                  const uint8_t *hpub)
{
    if (priv == NULL || kgseed == NULL || F_mod2 == NULL || G_mod2 == NULL || hpub == NULL) {
        return -1;
    }
    if (priv_len != HAWK_PRIV_BYTES) {
        return -1;
    }
    size_t offset = 0;
    memcpy(priv + offset, kgseed, HAWK_KGSEED_BYTES);
    offset += HAWK_KGSEED_BYTES;
    memcpy(priv + offset, F_mod2, HAWK_N_BYTES);
    offset += HAWK_N_BYTES;
    memcpy(priv + offset, G_mod2, HAWK_N_BYTES);
    offset += HAWK_N_BYTES;
    memcpy(priv + offset, hpub, HAWK_HPUB_BYTES);
    offset += HAWK_HPUB_BYTES;
    return 0;
}

int EncodeSignature(uint8_t *sig,
                    uint32_t sig_len_bits,
                    const uint8_t *salt,
                    const int32_t *s1)
{
    uint32_t y_len_bits = 0;
    int8_t y[YS1_MAX_BITS];
    if (sig_len_bits != HAWK_SIG_BYTES * 8U) {
        return -1;
    }
    int result_GR = CompressGR(y, s1, HAWK_N, &y_len_bits, HAWK_S1_LOW_BITS, HAWK_S1_HIGH_BITS);
    if (result_GR != 0 || y_len_bits > sig_len_bits - HAWK_SALTLEN_BITS) {
        return -1;
    }
    while (y_len_bits < (sig_len_bits - HAWK_SALTLEN_BITS)) {
        y[y_len_bits++] = 0;
    }
    uint32_t y_len_bytes = y_len_bits / 8;
    uint8_t y_bytes[y_len_bytes];
    PackBits(y_bytes, y, y_len_bits);
    memcpy(sig, salt, HAWK_SALTLEN_BYTES);
    memcpy(sig + HAWK_SALTLEN_BYTES, y_bytes, y_len_bytes);
    return 0;
}
