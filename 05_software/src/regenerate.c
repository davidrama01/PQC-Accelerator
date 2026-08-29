#include "regenerate.h"
#include "shake256.h"
#include <stdio.h>

/* Extrae un bit LSB-first de un array de palabras de 64 bits. */
static uint8_t get_bit_from_u64_array(const uint64_t *x,
                                      uint32_t bit_index)
{
    uint32_t word_index = bit_index / 64;
    uint32_t bit_pos    = bit_index % 64;

    return (uint8_t)((x[word_index] >> bit_pos) & 1ULL);
}

/* Regenera deterministamente f y g binomiales a partir de kgseed. */
int RegenerateFG(const uint8_t *kgseed,
                 int8_t *f,
                 int8_t *g)
{
    if (kgseed == NULL || f == NULL || g == NULL) {
        return -1;
    }

    /*
     * Algorithm 12
     *
     * b <- n / 64
     */

    const uint32_t b = HAWK_N / 64;

    /*
     * y <- SHAKE256x4(kgseed)[0 : 2*b*n]
     *
     * Número total de bits necesarios:
     *
     * 2*b*n
     */

    const uint32_t y_bits = 2 * b * HAWK_N;

    /*
     * Número de palabras uint64_t necesarias
     */

    const uint32_t y_words = y_bits / 64;

    /*
     * SHAKE256x4 devuelve grupos de 4 palabras.
     */

    const uint32_t x4_words = y_words / 4;

    uint64_t y[y_words];

    shake256x4(y,
               x4_words,
               kgseed,
               HAWK_KGSEED_BYTES);

    /*
     * f[i]
     */

    for (uint32_t i = 0; i < HAWK_N; i++) {

        int8_t sum = 0;

        for (uint32_t j = 0; j < b; j++) {

            uint32_t bit_index =
                i * b + j;

            sum += get_bit_from_u64_array(y,
                                          bit_index);
        }

        f[i] = sum - (int8_t)(b / 2);
    }

    /*
     * g[i]
     */

    for (uint32_t i = 0; i < HAWK_N; i++) {

        int8_t sum = 0;

        for (uint32_t j = 0; j < b; j++) {

            uint32_t bit_index =
                (i + HAWK_N) * b + j;

            sum += get_bit_from_u64_array(y,
                                          bit_index);
        }

        g[i] = sum - (int8_t)(b / 2);
    }

    return 0;
}
