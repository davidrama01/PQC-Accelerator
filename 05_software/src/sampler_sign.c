#include "sampler_sign.h"
#include "shake256.h"
#include "hawk_params.h"

typedef unsigned __int128 u128;

#define U80(hi, lo) ((((u128)(hi)) << 64) | ((u128)(lo)))

#if HAWK_N != 512
#error "Este sampler está preparado ahora mismo para HAWK-512"
#endif

static const u128 T0[] = {
    U80(0x2C05, 0x8C27920A04F8F267ULL),
    U80(0x0E9A, 0x1C4FF17C204AA058ULL),
    U80(0x02DB, 0xDE63263BE0098FFDULL),
    U80(0x0051, 0x56AEDFB0876A3BD8ULL),
    U80(0x0005, 0x061E21D588CC61CCULL),
    U80(0x0000, 0x2BA568D922EC18E7ULL),
    U80(0x0000, 0x00CF0F8687D3B009ULL),
    U80(0x0000, 0x000216A0C344EB45ULL),
    U80(0x0000, 0x00002EDF0B98A84ULL),
    U80(0x0000, 0x00000023AF3B2E7ULL),
    U80(0x0000, 0x00000000000EBC6AULL),
    U80(0x0000, 0x00000000000034CFULL),
    U80(0x0000, 0x0000000000000006ULL)
};

static const u128 T1[] = {
    U80(0x1AFC, 0xBC689D9213449DC9ULL),
    U80(0x06EB, 0xFB908C81FCE3524FULL),
    U80(0x0106, 0x4EBEFD8FF4F07378ULL),
    U80(0x0015, 0xC628BC6B23887196ULL),
    U80(0x0000, 0xFF769211F07B326FULL),
    U80(0x0000, 0x0668F461693DFF8FULL),
    U80(0x0000, 0x001670DB65964485ULL),
    U80(0x0000, 0x00002AB6E11C2552ULL),
    U80(0x0000, 0x0000002C253C7E81ULL),
    U80(0x0000, 0x00000000018C14ABFULL),
    U80(0x0000, 0x000000000007876EULL),
    U80(0x0000, 0x000000000000013DULL),
    U80(0x0000, 0x0000000000000000ULL)
};

static uint8_t get_bit(const uint8_t *v, uint32_t index)
{
    return (uint8_t)((v[index / 8] >> (index % 8)) & 1U);
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

                u128 c =
                    ((u128)(a & 0x7FFFFFFFFFFFFFFFULL)) |
                    (((u128)b) << 63);

                uint32_t v0 = 0;
                uint32_t v1 = 0;
                uint32_t z  = 0;

                while (T0[z] != 0 || T1[z] != 0) {

                    if (c < T0[z]) {
                        v0++;
                    }

                    if (c < T1[z]) {
                        v1++;
                    }

                    z++;
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