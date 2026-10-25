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

/* Algoritmo 7: signos, partes bajas y cocientes unarios Golomb-Rice. */
int DecompressGR(int32_t *x,
                 const uint8_t *bits,
                 size_t bits_len,
                 uint32_t k,
                 size_t *used_bits,
                 uint8_t low,
                 uint8_t high)
{
    size_t j;
    uint32_t quotient_limit;

    if (used_bits == NULL) {
        return -1;
    }
    *used_bits = 0U;

    if (x == NULL || bits == NULL || k == 0U || (k % 8U) != 0U ||
        low > high || high > 31U) {
        return -1;
    }

    /* Cada coeficiente necesita signo, low bits y al menos un terminador.
       La division evita desbordar al calcular k * (low + 2). */
    if ((size_t)k > bits_len / ((size_t)low + 2U)) {
        return -2;
    }

    j = k;
    for (uint32_t i = 0U; i < k; i++) {
        uint32_t value = 0U;

        if (bits[i] > 1U) {
            return -3;
        }
        for (uint8_t b = 0U; b < low; b++) {
            if (bits[j] > 1U) {
                return -3;
            }
            value |= (uint32_t)bits[j++] << b;
        }
        x[i] = (int32_t)value;
    }

    quotient_limit = UINT32_C(1) << (high - low);
    for (uint32_t i = 0U; i < k; i++) {
        uint32_t quotient = 0U;
        uint32_t value;

        /* q ceros seguidos de un uno codifican el cociente q.
           El limite tambien se comprueba antes de aceptar el terminador. */
        for (;;) {
            if (quotient >= quotient_limit) {
                return -3;
            }
            if (j >= bits_len) {
                return -2;
            }
            if (bits[j] > 1U) {
                return -3;
            }
            if (bits[j++] == 1U) {
                break;
            }
            quotient++;
        }

        value = (uint32_t)x[i] + (quotient << low);
        /* high <= 31 garantiza value <= INT32_MAX. El signo negativo
           representa -value-1, por lo que tambien se admite INT32_MIN. */
        x[i] = bits[i] != 0U ? -(int32_t)value - 1 : (int32_t)value;
    }

    *used_bits = j;
    return 0;
}

/* Separa y decodifica los campos de una clave privada HAWK. */
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

/* Algoritmo 9: recupera q00 completo y q01 de la clave publica serializada. */
int DecodePublic(int32_t *q00,
                 int32_t *q01,
                 const uint8_t *pub,
                 size_t pub_len)
{
    uint8_t bits[HAWK_PUB_BYTES * 8U];
    const size_t bits_len = sizeof bits;
    const uint8_t v = 16U - HAWK_Q00_HIGH_BITS;
    size_t j;
    size_t used;

    if (q00 == NULL || q01 == NULL || pub == NULL) {
        return -1;
    }
    if (pub_len != HAWK_PUB_BYTES) {
        return -2;
    }

    /* PackBits almacena el primer bit en el bit menos significativo. */
    for (size_t i = 0U; i < bits_len; i++) {
        bits[i] = (uint8_t)((pub[i / 8U] >> (i % 8U)) & 1U);
    }

    if (DecompressGR(q00, bits, bits_len, HAWK_N / 2U, &j,
                      HAWK_Q00_LOW_BITS, HAWK_Q00_HIGH_BITS) != 0) {
        return -3;
    }
    if ((size_t)v > bits_len - j) {
        return -3;
    }

    /* El primer coeficiente se guardo dividido por 2^v, seguido de sus
       v bits bajos. Multiplicar evita desplazar un entero negativo. */
    q00[0] = q00[0] * (INT32_C(1) << v) +
             (int32_t)DecodeInt(bits + j, v);
    j += v;

    /* q01 empieza en una frontera de byte; el relleno intermedio es cero. */
    while ((j % 8U) != 0U) {
        if (j >= bits_len || bits[j] != 0U) {
            return -3;
        }
        j++;
    }

    /* q00 es autoadjunto modulo X^n+1: basta su primera mitad. */
    q00[HAWK_N / 2U] = 0;
    for (size_t i = HAWK_N / 2U + 1U; i < HAWK_N; i++) {
        q00[i] = -q00[HAWK_N - i];
    }

    if (DecompressGR(q01, bits + j, bits_len - j, HAWK_N, &used,
                      HAWK_Q01_LOW_BITS, HAWK_Q01_HIGH_BITS) != 0) {
        return -3;
    }
    j += used;

    while (j < bits_len) {
        if (bits[j++] != 0U) {
            return -3;
        }
    }
    return 0;
}

/* Algoritmo 11: salt || CompressGR(s1) || relleno de ceros. */
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

    /* El salt ocupa bytes completos; solo se desempaqueta el campo s1. */
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
