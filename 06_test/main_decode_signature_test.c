#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "decode.h"
#include "encode.h"

/* Independent writer for salt || signs || low parts || unary quotients. */
typedef struct {
    uint8_t bytes[HAWK_SIG_BYTES];
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

static uint32_t magnitude(int32_t x)
{
    return x < 0 ? (uint32_t)(-(int64_t)x - 1) : (uint32_t)x;
}

static void reference_signature(writer_t *w, const uint8_t *salt,
                                const int32_t *s1)
{
    memset(w, 0, sizeof *w);
    memcpy(w->bytes, salt, HAWK_SALTLEN_BYTES);
    w->position = HAWK_SALTLEN_BYTES * 8U;
    for (size_t i = 0U; i < HAWK_N; i++) {
        assert(magnitude(s1[i]) < (UINT32_C(1) << HAWK_S1_HIGH_BITS));
        put_bit(w, s1[i] < 0);
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        for (unsigned bit = 0U; bit < HAWK_S1_LOW_BITS; bit++) {
            put_bit(w, (magnitude(s1[i]) >> bit) & 1U);
        }
    }
    for (size_t i = 0U; i < HAWK_N; i++) {
        const uint32_t quotient = magnitude(s1[i]) >> HAWK_S1_LOW_BITS;
        for (uint32_t j = 0U; j < quotient; j++) {
            put_bit(w, 0U);
        }
        put_bit(w, 1U);
    }
}

static void check_signature(const uint8_t *salt, const int32_t *s1)
{
    writer_t reference;
    uint8_t encoded[HAWK_SIG_BYTES], reencoded[HAWK_SIG_BYTES];
    struct {
        uint8_t before;
        uint8_t data[HAWK_SALTLEN_BYTES];
        uint8_t after;
    } decoded_salt;
    struct {
        uint32_t before;
        int32_t data[HAWK_N];
        uint32_t after;
    } decoded_s1;

    decoded_salt.before = 0x53U;
    decoded_salt.after = 0xA7U;
    decoded_s1.before = UINT32_C(0x12345678);
    decoded_s1.after = UINT32_C(0xABCDEF01);
    reference_signature(&reference, salt, s1);
    assert(DecodeSignature(decoded_salt.data, decoded_s1.data,
                            reference.bytes, sizeof reference.bytes) == 0);
    assert(memcmp(decoded_salt.data, salt, HAWK_SALTLEN_BYTES) == 0);
    assert(memcmp(decoded_s1.data, s1, sizeof decoded_s1.data) == 0);
    assert(decoded_salt.before == 0x53U && decoded_salt.after == 0xA7U);
    assert(decoded_s1.before == UINT32_C(0x12345678));
    assert(decoded_s1.after == UINT32_C(0xABCDEF01));

    assert(EncodeSignature(encoded, sizeof encoded * 8U, salt, s1) == 0);
    assert(memcmp(encoded, reference.bytes, sizeof encoded) == 0);
    assert(DecodeSignature(decoded_salt.data, decoded_s1.data,
                            encoded, sizeof encoded) == 0);
    assert(EncodeSignature(reencoded, sizeof reencoded * 8U,
                            decoded_salt.data, decoded_s1.data) == 0);
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

static void malformed_signatures(void)
{
    writer_t reference;
    uint8_t salt[HAWK_SALTLEN_BYTES] = {0};
    int32_t s1[HAWK_N] = {0};
    uint8_t bad[HAWK_SIG_BYTES], decoded_salt[HAWK_SALTLEN_BYTES];
    int32_t decoded_s1[HAWK_N];
    const size_t unary_start = HAWK_SALTLEN_BITS +
                              HAWK_N * (HAWK_S1_LOW_BITS + 1U);
    const size_t quotient_limit = (size_t)1U <<
                                  (HAWK_S1_HIGH_BITS - HAWK_S1_LOW_BITS);

    reference_signature(&reference, salt, s1);
    assert(reference.position < sizeof bad * 8U);
    for (size_t bit = reference.position; bit < sizeof bad * 8U; bit++) {
        memcpy(bad, reference.bytes, sizeof bad);
        set_bit(bad, bit, 1U);
        assert(DecodeSignature(decoded_salt, decoded_s1, bad, sizeof bad) == -3);
    }

    memcpy(bad, reference.bytes, sizeof bad);
    for (size_t i = 0U; i < quotient_limit; i++) {
        set_bit(bad, unary_start + i, 0U);
    }
    set_bit(bad, unary_start + quotient_limit, 1U);
    assert(DecodeSignature(decoded_salt, decoded_s1, bad, sizeof bad) == -3);

    memcpy(bad, reference.bytes, sizeof bad);
    set_bit(bad, reference.position - 1U, 0U); /* Missing last terminator. */
    assert(DecodeSignature(decoded_salt, decoded_s1, bad, sizeof bad) == -3);
    memset(bad, 0, sizeof bad);
    assert(DecodeSignature(decoded_salt, decoded_s1, bad, sizeof bad) == -3);
    memset(bad, 255, sizeof bad);
    assert(DecodeSignature(decoded_salt, decoded_s1, bad, sizeof bad) == -3);
    for (size_t length = 0U; length < sizeof bad; length++) {
        assert(DecodeSignature(decoded_salt, decoded_s1,
                                reference.bytes, length) == -2);
    }
    assert(DecodeSignature(decoded_salt, decoded_s1,
                            reference.bytes, sizeof bad + 1U) == -2);
    assert(DecodeSignature(NULL, decoded_s1, reference.bytes, sizeof bad) == -1);
    assert(DecodeSignature(decoded_salt, NULL, reference.bytes, sizeof bad) == -1);
    assert(DecodeSignature(decoded_salt, decoded_s1, NULL, sizeof bad) == -1);

    /* Any salt is syntactically valid; decoding must keep its exact bytes. */
    for (size_t i = 0U; i < HAWK_SALTLEN_BYTES; i++) {
        memcpy(bad, reference.bytes, sizeof bad);
        bad[i] ^= 0x80U;
        assert(DecodeSignature(decoded_salt, decoded_s1, bad, sizeof bad) == 0);
        assert(memcmp(decoded_salt, bad, HAWK_SALTLEN_BYTES) == 0);
        assert(memcmp(decoded_s1, s1, sizeof s1) == 0);
    }
}

int main(void)
{
    uint8_t salt[HAWK_SALTLEN_BYTES];
    int32_t s1[HAWK_N];

    for (unsigned trial = 0U; trial < 50U; trial++) {
        for (size_t i = 0U; i < sizeof salt; i++) {
            salt[i] = trial == 0U ? 0U : trial == 1U ? 255U :
                       (uint8_t)(i * 37U + trial * 19U);
        }
        for (size_t i = 0U; i < HAWK_N; i++) {
            s1[i] = trial == 0U ? 0 : trial == 1U ? -1 :
                    (int32_t)((i * 17U + trial * 7U) % 31U) - 15;
        }
        if (trial >= 2U) {
            s1[0] = (INT32_C(1) << HAWK_S1_HIGH_BITS) - 1;
            s1[HAWK_N - 1U] = -(INT32_C(1) << HAWK_S1_HIGH_BITS);
            s1[1] = (INT32_C(1) << HAWK_S1_LOW_BITS) - 1;
            s1[2] = -(INT32_C(1) << HAWK_S1_LOW_BITS);
            s1[3] = INT32_C(1) << HAWK_S1_LOW_BITS;
        }
        check_signature(salt, s1);
    }
    malformed_signatures();
    printf("PASS: DecodeSignature %s, 50 independent vectors and malformed signatures\n",
           HAWK_NAME);
    return 0;
}
