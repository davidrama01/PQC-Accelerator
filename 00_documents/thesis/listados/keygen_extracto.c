/* Extracto documental no compilable: se omiten declaraciones,
   conversiones y bloques aritmeticos indicados en los comentarios. */
void keygen(uint8_t *pub, uint8_t *priv)
{
restart:
    if (Rnd(kgseed, HAWK_KGSEED_BYTES * 8U) != 0)
        goto restart;
    RegenerateFG(kgseed, f_words, g_words);
    /* Conversion de f_words y g_words a f_32 y g_32. */
    if (!IsInvertible_mod2(f_32, HAWK_N) ||
        !IsInvertible_mod2(g_32, HAWK_N))
        goto restart;
    threshold = norm(f_32, g_32, HAWK_N);
    if ((int64_t)threshold * 1000000LL <=
        2LL * HAWK_N * HAWK_SIGMA_KREC * HAWK_SIGMA_KREC)
        goto restart;

    /* Calculo de adjuntos y de q00 = f*f_adj + g*g_adj
       mediante reciprocal, poly_mul y suma de coeficientes. */
    if (!IsInvertible(q00, G1, P1, HAWK_N) ||
        !IsInvertible(q00, G2, P2, HAWK_N))
        goto restart;
    if (hawk_check_q00_beta(q00, HAWK_N) != 1)
        goto restart;

    if (towersolver(f_32, g_32, f_solve, g_solve, HAWK_N) != 0)
        goto restart;
    if (infinite_norm(f_solve, g_solve, HAWK_N) > 127)
        goto restart;

    /* Calculo de q01 = F*f_adj + G*g_adj y
       q11 = F*F_adj + G*G_adj. Se reinicia si alguna
       suma no es representable en int32_t. */
    q11_limit = (int32_t)(1U << HAWK_Q11_BITS);
    for (uint32_t i = 1U; i < HAWK_N; i++) {
        if (q11[i] >= q11_limit || q11[i] <= -q11_limit)
            goto restart;
    }

    if (EncodePublic(pub, q00, q01, HAWK_N) != 0)
        goto restart;
    /* Reduccion modulo 2 y empaquetado de F y G
       en f_solve_packed y g_solve_packed mediante PackBits. */
    shake256(hpub, HAWK_HPUB_BYTES, pub, HAWK_PUB_BYTES);
    if (EncodePrivate(priv, HAWK_PRIV_BYTES, kgseed,
                      f_solve_packed, g_solve_packed, hpub) != 0)
        goto restart;
}
