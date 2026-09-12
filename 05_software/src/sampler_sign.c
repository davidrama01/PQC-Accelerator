#include "sampler_sign.h"
#include "shake256.h"
#include "hawk_params.h"

static uint8_t get_bit(const uint8_t *v, uint32_t index)
{
    return (uint8_t)((v[index / 8] >> (index % 8)) & 1U);
}

static int u80_less(hawk_u80 left, hawk_u80 right)
{
    if (left.hi != right.hi) {
        return left.hi < right.hi;
    }
    return left.lo < right.lo;
}

int SamplerSign(const uint8_t *seed,
                size_t seed_len,
                const uint8_t *t,
                int16_t *x)
{
    if (seed == NULL || t == NULL || x == NULL) {
        return -1;
    }

    uint64_t y[HAWK_SAMPLER_Y_WORDS];

    shake256x4(y,
               HAWK_SAMPLER_X4_WORDS,
               seed,
               seed_len);

    for (uint32_t j = 0; j < 4; j++) {

        for (uint32_t i = 0; i < HAWK_N / 8; i++) {

            for (uint32_t k = 0; k < 4; k++) {

                uint32_t r = 16 * i + 4 * j + k;

                uint64_t a_word = y[j + 4 * (5 * i + k)];
                uint64_t b_word = y[j + 4 * (5 * i + 4)];

                uint64_t a = a_word;

                uint32_t b =
                    (uint32_t)((b_word >> (16 * k)) & 0x7FFFU);

                hawk_u80 c;
                c.hi = (uint16_t)(b >> 1);
                c.lo = (a & 0x7FFFFFFFFFFFFFFFULL)
                     | ((uint64_t)(b & 1U) << 63);

                uint32_t v0 = 0;
                uint32_t v1 = 0;
                for (uint32_t z = 0; z < HAWK_SAMPLER_TABLE_LEN; z++) {
                    if (u80_less(c, HAWK_T0[z])) {
                        v0++;
                    }

                    if (u80_less(c, HAWK_T1[z])) {
                        v1++;
                    }
                }

                int16_t v;

                if (get_bit(t, r) == 0) {
                    v = (int16_t)(2 * v0);
                } else {
                    v = (int16_t)(2 * v1 + 1);
                }

                if (a >= 0x8000000000000000ULL) {
                    v = (int16_t)(-v);
                }

                x[r] = v;
            }
        }
    }

    return 0;
}
