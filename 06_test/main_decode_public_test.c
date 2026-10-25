#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

#include "decode.h"
#include "encode.h"

/* Independent bit writer for specification vectors, not CompressGR. */
typedef struct {
    uint8_t bytes[HAWK_PUB_BYTES];
    size_t position;
} writer_t;

static void put_bit(writer_t *w, unsigned bit)
{
    assert(w->position < sizeof w->bytes * 8U);
    if (bit != 0U) {
        w->bytes[w->position / 8U] |= (uint8_t)(1U << (w->position % 8U));
    }
    w->position++;
}

static void put_integer(writer_t *w, uint32_t value, unsigned width)
{
    for (unsigned b = 0U; b < width; b++) {
        put_bit(w, (value >> b) & 1U);
    }
}

static uint32_t magnitude(int32_t x)
{
    return x < 0 ? (uint32_t)(-(int64_t)x - 1) : (uint32_t)x;
}

static void put_gr(writer_t *w, const int32_t *x, size_t k,
                   unsigned low, unsigned high)
{
    for (size_t i = 0U; i < k; i++) {
        assert(magnitude(x[i]) < (UINT32_C(1) << high));
        put_bit(w, x[i] < 0);
    }
    for (size_t i = 0U; i < k; i++) {
        put_integer(w, magnitude(x[i]), low);
    }
    for (size_t i = 0U; i < k; i++) {
        uint32_t quotient = magnitude(x[i]) >> low;
        for (uint32_t j = 0U; j < quotient; j++) {
            put_bit(w, 0U);
        }
        put_bit(w, 1U);
    }
}

static void reference_public(writer_t *w, const int32_t *q00,
                              const int32_t *q01, size_t *padding_start,
                              size_t *q01_start, size_t *padding_end)
{
    const unsigned v = 16U - HAWK_Q00_HIGH_BITS;
    const int32_t divisor = INT32_C(1) << v;
    int32_t half[HAWK_N / 2U];
    int32_t remainder = q00[0] % divisor;

    memset(w, 0, sizeof *w);
    memcpy(half, q00, sizeof half);
    if (remainder < 0) {
        remainder += divisor;
    }
    half[0] = (q00[0] - remainder) / divisor;
    put_gr(w, half, HAWK_N / 2U, HAWK_Q00_LOW_BITS, HAWK_Q00_HIGH_BITS);
    put_integer(w, (uint32_t)remainder, v);
    *padding_start = w->position;
    while (w->position % 8U != 0U) {
        put_bit(w, 0U);
    }
    *q01_start = w->position;
    put_gr(w, q01, HAWK_N, HAWK_Q01_LOW_BITS, HAWK_Q01_HIGH_BITS);
    *padding_end = w->position;
}

static void complete_q00(int32_t *q00)
{
    q00[HAWK_N / 2U] = 0;
    for (size_t i = HAWK_N / 2U + 1U; i < HAWK_N; i++) {
        q00[i] = -q00[HAWK_N - i];
    }
}

static void check_key(int32_t *q00, int32_t *q01)
{
    writer_t reference;
    uint8_t encoded[HAWK_PUB_BYTES];
    uint8_t reencoded[HAWK_PUB_BYTES];
    int32_t decoded00[HAWK_N], decoded01[HAWK_N];
    size_t pad00, start01, pad01;

    complete_q00(q00);
    reference_public(&reference, q00, q01, &pad00, &start01, &pad01);
    assert(DecodePublic(decoded00, decoded01, reference.bytes,
                         sizeof reference.bytes) == 0);
    assert(memcmp(decoded00, q00, sizeof decoded00) == 0);
    assert(memcmp(decoded01, q01, sizeof decoded01) == 0);
    assert(EncodePublic(encoded, q00, q01, HAWK_N) == 0);
    assert(memcmp(encoded, reference.bytes, sizeof encoded) == 0);
    assert(DecodePublic(decoded00, decoded01, encoded, sizeof encoded) == 0);
    assert(EncodePublic(reencoded, decoded00, decoded01, HAWK_N) == 0);
    assert(memcmp(encoded, reencoded, sizeof encoded) == 0);
}

static void set_bit(uint8_t *bytes, size_t position, unsigned bit)
{
    const uint8_t mask = (uint8_t)(1U << (position % 8U));
    if (bit != 0U) {
        bytes[position / 8U] |= mask;
    } else {
        bytes[position / 8U] &= (uint8_t)~mask;
    }
}

static void invalid_keys(void)
{
    writer_t reference;
    uint8_t bad[HAWK_PUB_BYTES];
    int32_t q00[HAWK_N] = {0}, q01[HAWK_N] = {0};
    int32_t decoded00[HAWK_N], decoded01[HAWK_N];
    size_t pad00, start01, pad01;
    const size_t half = HAWK_N / 2U;

    reference_public(&reference, q00, q01, &pad00, &start01, &pad01);
    assert(pad00 < start01 && pad01 < sizeof bad * 8U);
    for (size_t bit = pad00; bit < start01; bit++) {
        memcpy(bad, reference.bytes, sizeof bad);
        set_bit(bad, bit, 1U);
        assert(DecodePublic(decoded00, decoded01, bad, sizeof bad) == -3);
    }
    for (size_t bit = pad01; bit < sizeof bad * 8U; bit++) {
        memcpy(bad, reference.bytes, sizeof bad);
        set_bit(bad, bit, 1U);
        assert(DecodePublic(decoded00, decoded01, bad, sizeof bad) == -3);
    }

    /* First q00 and q01 quotient exceeds the corresponding high limit. */
    for (unsigned field = 0U; field < 2U; field++) {
        const unsigned low = field ? HAWK_Q01_LOW_BITS : HAWK_Q00_LOW_BITS;
        const unsigned high = field ? HAWK_Q01_HIGH_BITS : HAWK_Q00_HIGH_BITS;
        const size_t offset = field ? start01 : 0U;
        const size_t k = field ? HAWK_N : half;
        const size_t unary_start = offset + k * (low + 1U);
        const size_t limit = (size_t)1U << (high - low);

        memcpy(bad, reference.bytes, sizeof bad);
        for (size_t i = 0U; i < limit; i++) {
            set_bit(bad, unary_start + i, 0U);
        }
        set_bit(bad, unary_start + limit, 1U);
        assert(DecodePublic(decoded00, decoded01, bad, sizeof bad) == -3);
    }

    memset(bad, 0, sizeof bad);
    assert(DecodePublic(decoded00, decoded01, bad, sizeof bad) == -3);
    memset(bad, 255, sizeof bad);
    assert(DecodePublic(decoded00, decoded01, bad, sizeof bad) == -3);
    for (size_t length = 0U; length < sizeof bad; length++) {
        assert(DecodePublic(decoded00, decoded01, reference.bytes, length) == -2);
    }
    assert(DecodePublic(decoded00, decoded01, reference.bytes, sizeof bad + 1U) == -2);
    assert(DecodePublic(NULL, decoded01, reference.bytes, sizeof bad) == -1);
    assert(DecodePublic(decoded00, NULL, reference.bytes, sizeof bad) == -1);
    assert(DecodePublic(decoded00, decoded01, NULL, sizeof bad) == -1);
}

int main(void)
{
    const int32_t first[] = {0, 1, -1, 127, 128, 129, -128, -129,
                              INT16_MIN, INT16_MAX};
    int32_t q00[HAWK_N], q01[HAWK_N];

    for (size_t trial = 0U; trial < 50U; trial++) {
        memset(q00, 0, sizeof q00);
        memset(q01, 0, sizeof q01);
        q00[0] = first[trial % (sizeof first / sizeof first[0])];
        if (trial >= 10U) {
            for (size_t i = 1U; i < HAWK_N / 2U; i++) {
                q00[i] = (int32_t)((i * 17U + trial * 7U) % 31U) - 15;
            }
            for (size_t i = 0U; i < HAWK_N; i++) {
                q01[i] = (int32_t)((i * 37U + trial * 11U) % 63U) - 31;
            }
            q00[1] = (INT32_C(1) << HAWK_Q00_HIGH_BITS) - 1;
            q00[2] = -(INT32_C(1) << HAWK_Q00_HIGH_BITS);
            q01[0] = (INT32_C(1) << HAWK_Q01_HIGH_BITS) - 1;
            q01[HAWK_N - 1U] = -(INT32_C(1) << HAWK_Q01_HIGH_BITS);
        }
        check_key(q00, q01);
    }
    invalid_keys();
    printf("PASS: DecodePublic %s, 50 independent vectors and malformed keys\n", HAWK_NAME);
    return 0;
}
