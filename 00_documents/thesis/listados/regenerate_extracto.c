/* Extracto documental de regenerate.c.
   Regeneracion de f y g; se omiten includes y comentarios extensos.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

static uint8_t get_bit_from_u64_array(const uint64_t *x,
                                      uint32_t bit_index)
{
    uint32_t word_index = bit_index / 64;
    uint32_t bit_pos    = bit_index % 64;
    return (uint8_t)((x[word_index] >> bit_pos) & 1ULL);
}

int RegenerateFG(const uint8_t *kgseed,
                 int8_t *f,
                 int8_t *g)
{
    if (kgseed == NULL || f == NULL || g == NULL) {
        return -1;
    }
    const uint32_t b = HAWK_N / 64;
    const uint32_t y_bits = 2 * b * HAWK_N;
    const uint32_t y_words = y_bits / 64;
    const uint32_t x4_words = y_words / 4;
    uint64_t y[y_words];
    shake256x4(y,
               x4_words,
               kgseed,
               HAWK_KGSEED_BYTES);
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
