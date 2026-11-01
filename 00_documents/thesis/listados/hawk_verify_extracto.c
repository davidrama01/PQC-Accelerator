/* Extracto documental de hawk_verify.c.
   Se omiten includes y declaraciones de buffers; se conservan las comprobaciones.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

int hawk_verify(const uint8_t *sig,
                size_t sig_len,
                const uint8_t *pub,
                size_t pub_len,
                const uint8_t *message,
                size_t message_len)
{
    uint32_t error;
    uint8_t *message_hpub;
    if (sig == NULL || pub == NULL ||
        (message == NULL && message_len != 0U) ||
        message_len > SIZE_MAX - HAWK_HPUB_BYTES) {
        return -1;
    }
    if (DecodeSignature(salt, s1, sig, sig_len) != 0 ||
        DecodePublic(q00, q01, pub, pub_len) != 0) {
        return 0;
    }
    shake256(hpub, sizeof hpub, pub, pub_len);
    message_hpub = malloc(message_len + sizeof hpub);
    if (message_hpub == NULL) {
        return -2;
    }
    if (message_len != 0U) {
        memcpy(message_hpub, message, message_len);
    }
    memcpy(message_hpub + message_len, hpub, sizeof hpub);
    shake256(message_hash, sizeof message_hash,
              message_hpub, message_len + sizeof hpub);
    free(message_hpub);
    memcpy(hash_salt, message_hash, sizeof message_hash);
    memcpy(hash_salt + sizeof message_hash, salt, sizeof salt);
    shake256(h, sizeof h, hash_salt, sizeof hash_salt);
    for (size_t i = 0U; i < HAWK_N_WORDS32; i++) {
        h0[i] = (uint32_t)h[4U * i] |
                ((uint32_t)h[4U * i + 1U] << 8) |
                ((uint32_t)h[4U * i + 2U] << 16) |
                ((uint32_t)h[4U * i + 3U] << 24);
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        const int32_t h1_bit = (h[HAWK_N_BYTES + i / 8U] >> (i % 8U)) & 1U;
        w1[i] = h1_bit - 2 * s1[i];
    }
    if (HawkFpgaVerify(h0, q00, q01, w1, &error) != 0) {
        return -3;
    }
    return error == 0U ? 1 : 0;
}
