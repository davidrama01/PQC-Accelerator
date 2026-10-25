#include <stdlib.h>
#include <string.h>

#include "hawk_verify.h"
#include "decode.h"
#include "hawk_fpga.h"
#include "shake256.h"

int hawk_verify(const uint8_t *sig,
                size_t sig_len,
                const uint8_t *pub,
                size_t pub_len,
                const uint8_t *message,
                size_t message_len)
{
    uint8_t salt[HAWK_SALTLEN_BYTES];
    int32_t s1[HAWK_N];
    int32_t q00[HAWK_N], q01[HAWK_N], w1[HAWK_N];
    uint8_t hpub[HAWK_HPUB_BYTES];
    uint8_t message_hash[HAWK_M_BYTES];
    uint8_t hash_salt[HAWK_M_BYTES + HAWK_SALTLEN_BYTES];
    uint8_t h[2U * HAWK_N_BYTES];
    uint32_t h0[HAWK_N_WORDS32];
    uint32_t error;
    uint8_t *message_hpub;

    if (sig == NULL || pub == NULL ||
        (message == NULL && message_len != 0U) ||
        message_len > SIZE_MAX - HAWK_HPUB_BYTES) {
        return -1;
    }

    /* Una codificacion incorrecta se rechaza sin acceder al acelerador. */
    if (DecodeSignature(salt, s1, sig, sig_len) != 0 ||
        DecodePublic(q00, q01, pub, pub_len) != 0) {
        return 0;
    }

    shake256(hpub, sizeof hpub, pub, pub_len);

    /* M = SHAKE256(m || hpub)[0:512]. Se evita una VLA de tamano mensaje
       en la pila de Vitis; la memoria temporal se libera antes del DMA. */
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

    /* (h0,h1) = SHAKE256(M || salt)[0:2*n], en orden LSB-first. */
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
        /* DecodeSignature limita s1; esta operacion cabe en int32_t. */
        w1[i] = h1_bit - 2 * s1[i];
    }

    /* La FPGA hace sym-break, RebuildS0, ambas normas y la comprobacion r.
       El resultado se lee por registro; no se utiliza DMA de recepcion. */
    if (HawkFpgaVerify(h0, q00, q01, w1, &error) != 0) {
        return -3;
    }
    return error == 0U ? 1 : 0;
}
