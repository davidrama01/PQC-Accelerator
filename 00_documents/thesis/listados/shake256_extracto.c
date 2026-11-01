/* Extracto documental de shake256.c.
   Absorcion, extraccion y cuatro dominios; se omiten Keccak-f y auxiliares de serializacion.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

void shake256(uint8_t *out, size_t outlen,
              const uint8_t *in, size_t inlen)
{
    uint64_t st[25];
    uint8_t *s = (uint8_t *)st;
    size_t i;
    memset(st, 0, sizeof(st));
    while (inlen >= SHAKE256_RATE) {
        xor_bytes_into_state(st, in, SHAKE256_RATE);
        keccakf(st);
        in += SHAKE256_RATE;
        inlen -= SHAKE256_RATE;
    }
    xor_bytes_into_state(st, in, inlen);
    s[inlen] ^= 0x1F;
    s[SHAKE256_RATE - 1] ^= 0x80;
    keccakf(st);
    while (outlen > 0) {
        size_t block_size = outlen < SHAKE256_RATE ? outlen : SHAKE256_RATE;
        for (i = 0; i < block_size; i++)
            out[i] = s[i];
        out += block_size;
        outlen -= block_size;
        if (outlen > 0)
            keccakf(st);
    }
}

void shake256x4(uint64_t *out, size_t nwords,
                const uint8_t *m, size_t mlen)
{
    for (size_t j = 0; j < 4; j++) {
        uint8_t msg_ext[mlen + 1];
        for (size_t t = 0; t < mlen; t++) {
            msg_ext[t] = m[t];
        }
        EncodeIntBytes(&msg_ext[mlen], j, 8);
        uint64_t tmp[nwords];
        shake256w(tmp, nwords, msg_ext, mlen + 1);
        for (size_t i = 0; i < nwords; i++) {
            out[4 * i + j] = tmp[i];
        }
    }
}
