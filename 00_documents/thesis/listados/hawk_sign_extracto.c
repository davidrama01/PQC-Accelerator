/* Extracto documental no compilable de hawk_sign.c.
   Se omiten declaraciones y se resumen conversiones y concatenaciones.
   Los errores de preparacion devuelven -1; los rechazos reinician. */
int hawk_sign(uint8_t sig[HAWK_SIG_BYTES], const uint8_t *priv,
              const uint8_t *message, size_t message_len)
{
    /* Validacion de punteros y longitud; devuelve -1 si falla. */
    if (DecodePrivate(kgseed, Fmod2, Gmod2, hpub,
                      priv, HAWK_PRIV_BYTES) != 0)
        return -1;
    if (RegenerateFG(kgseed, f_regen, g_regen) != 0)
        return -1;
    /* ConcatBytes2: message_concat = message || hpub.
       Se comprueba el retorno antes de calcular el hash. */
    shake256(message_shake, HAWK_M_BYTES,
             message_concat, sizeof message_concat);
    uint32_t a = 0U;
restart:
    /* EncodeIntBytes(a), Rnd y ConcatBytes4 preparan
       salt_concat = M || kgseed || EncodeInt(a,32) || Rnd.
       Se comprueban los errores de Rnd y ConcatBytes4. */
    shake256(salt, sizeof salt, salt_concat, sizeof salt_concat);
    /* ConcatBytes2: h_concat = M || salt; comprobar retorno. */
    shake256(h_shake, sizeof h_shake, h_concat, sizeof h_concat);
    /* Separacion de h0 y h1, conversion a palabras y
       extension de f y g a coeficientes de 32 bits. */
    if (HawkFpgaCalculateT(h0_words, h1_words, F_words, G_words,
                           f_words, g_words, t0_words, t1_words) != 0)
        return -1;
    /* seed = M || kgseed || EncodeInt(a+1,32) || Rnd(320).
       Se comprueban Rnd y ConcatBytes4 y se serializan t0 y t1. */
    if (SamplerSign(seed, sizeof seed, t, x) != 0)
        return -1;
    /* Conversion de x a x0_words y x1_words. */
    a = a + 2U;
    uint64_t norm_squared = 0U;
    for (uint32_t i = 0U; i < 2U * HAWK_N; i++) {
        int32_t coefficient = x[i];
        norm_squared += (uint64_t)(coefficient * coefficient);
    }
    if (HawkFpgaSendX(x0_words, x1_words) != 0)
        return -1;
    if (HawkFpgaReceiveS1(s1) != 0)
        return -1;
    if (norm_squared > NORM_THR)
        goto restart;
    if (EncodeSignature(sig, HAWK_SIG_BYTES * 8U, salt, s1) != 0)
        goto restart;
    return 0;
}
