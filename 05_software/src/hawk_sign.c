#include <string.h>
#include "hawk_Sign.h"
#include "hawk_params.h"
#include "decode.h"
#include "encode.h"
#include "regenerate.h"
#include "basic.h"
#include "shake256.h"
#include "Rnd.h"
#include "hawk_fpga.h"
#include "sampler_sign.h"

void hawk_sign (const uint8_t *priv, const uint8_t *message, size_t message_len)
{
    if (priv == NULL ||
        (message == NULL && message_len != 0U) ||
        message_len > SIZE_MAX - HAWK_HPUB_BYTES) {
        return;
    }

    uint8_t kgseed[HAWK_KGSEED_BYTES];
    uint8_t Fmod2[HAWK_N_BYTES];
    uint8_t Gmod2[HAWK_N_BYTES];
    uint8_t hpub[HAWK_HPUB_BYTES];
    int8_t f_regen[HAWK_N];
    int8_t g_regen[HAWK_N];
    uint8_t message_concat[message_len + HAWK_HPUB_BYTES];
    uint8_t message_shake[HAWK_M_BYTES];
    uint8_t salt[HAWK_SALTLEN_BYTES];
    uint8_t salt_concat[HAWK_M_BYTES + HAWK_KGSEED_BYTES + 4U +
                        HAWK_SALTLEN_BYTES];
    uint8_t a_encoded[4];
    uint8_t randomize_salt[HAWK_SALTLEN_BYTES];
    uint8_t randomize_320[320 / 8U];
    uint8_t seed[HAWK_M_BYTES + HAWK_KGSEED_BYTES + sizeof a_encoded + sizeof randomize_320];
    uint8_t h_concat[HAWK_M_BYTES + HAWK_SALTLEN_BYTES];
    uint8_t h_shake[2*HAWK_N_BYTES];
    uint8_t h0[HAWK_N_BYTES];
    uint8_t h1[HAWK_N_BYTES];
    uint32_t h0_words[HAWK_N_WORDS32];
    uint32_t h1_words[HAWK_N_WORDS32];
    int32_t f_words[HAWK_N];
    int32_t g_words[HAWK_N];
    uint32_t F_words[HAWK_N_WORDS32];
    uint32_t G_words[HAWK_N_WORDS32];
    uint32_t t0_words[HAWK_N_WORDS32];
    uint32_t t1_words[HAWK_N_WORDS32];
    uint8_t t[2U * HAWK_N_BYTES];
    int16_t x[2U * HAWK_N];


    if (DecodePrivate(kgseed, Fmod2, Gmod2, hpub,
                      priv, HAWK_PRIV_BYTES) != 0) {
        return;
    }
    if (RegenerateFG(kgseed, f_regen, g_regen) != 0) {
        return;
    }
    if (ConcatBytes2(message_concat, sizeof message_concat,
                     message, message_len,
                     hpub, HAWK_HPUB_BYTES) != 0) {
        return;
    }
    shake256(message_shake, HAWK_M_BYTES,
             message_concat, sizeof message_concat);
    uint32_t a = 0U;
    restart:
    /* Primer intento del bucle de firma; los reinicios se añadiran con
       las condiciones de rechazo de las lineas posteriores. */
    EncodeIntBytes(a_encoded, a, 32U);
    if (Rnd(randomize_salt, HAWK_SALTLEN_BITS) != 0) {
        return;
    }
    if (ConcatBytes4(salt_concat, sizeof salt_concat,
                     message_shake, sizeof message_shake,
                     kgseed, sizeof kgseed,
                     a_encoded, sizeof a_encoded,
                     randomize_salt, sizeof randomize_salt) != 0) {
        return;
    }
    shake256(salt, sizeof salt, salt_concat, sizeof salt_concat);
    if (ConcatBytes2(h_concat, sizeof h_concat,
                     message_shake, HAWK_M_BYTES,
                     salt, sizeof salt) != 0) {
        return;
    }
    shake256(h_shake, sizeof h_shake, h_concat, sizeof h_concat);
    memcpy(h0, h_shake, HAWK_N_BYTES);
    memcpy(h1, h_shake + HAWK_N_BYTES, HAWK_N_BYTES);

    if (BytesToWords32(h0_words, HAWK_N_WORDS32,
                       h0, sizeof h0) != 0 ||
        BytesToWords32(h1_words, HAWK_N_WORDS32,
                       h1, sizeof h1) != 0 ||
        BytesToWords32(F_words, HAWK_N_WORDS32,
                       Fmod2, sizeof Fmod2) != 0 ||
        BytesToWords32(G_words, HAWK_N_WORDS32,
                       Gmod2, sizeof Gmod2) != 0) {
        return;
    }

    for (uint32_t i = 0U; i < HAWK_N; i++) {
        f_words[i] = (int32_t)f_regen[i];
        g_words[i] = (int32_t)g_regen[i];
    }

    if (HawkFpgaCalculateT(h0_words, h1_words, F_words, G_words,
                           f_words, g_words, t0_words, t1_words) != 0) {
        return;
    }

    EncodeIntBytes(a_encoded, a + 1U, 32U);

    if (Rnd(randomize_320, 320U) != 0) {
        return;
    }

    if (ConcatBytes4(seed, sizeof seed,
                     message_shake, sizeof message_shake,
                     kgseed, sizeof kgseed,
                     a_encoded, sizeof a_encoded,
                     randomize_320, sizeof randomize_320) != 0) {
        return;
    }

    for (uint32_t i = 0U; i < HAWK_N_WORDS32; i++) {
        EncodeIntBytes(&t[4U * i], t0_words[i], 32U);
        EncodeIntBytes(&t[HAWK_N_BYTES + 4U * i], t1_words[i], 32U);
    }

    if (SamplerSign(seed, sizeof seed, t, x) != 0) {
        return;
    }

    int32_t x0_words[HAWK_N];
    int32_t x1_words[HAWK_N];

    for (uint32_t i = 0U; i < HAWK_N; i++) {
        x0_words[i] = (int32_t)x[i];
        x1_words[i] = (int32_t)x[HAWK_N + i];
    }

    a = a + 2U;

    uint64_t norm_squared = 0U;

    for (uint32_t i = 0U; i < 2U * HAWK_N; i++) {
        int32_t coefficient = x[i];
        norm_squared += (uint64_t)(coefficient * coefficient);
    }

    if (norm_squared > NORM_THR) {
        goto restart;
    }

}
