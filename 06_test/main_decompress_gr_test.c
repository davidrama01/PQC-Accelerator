#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "decode.h"
#include "encode.h"

static void known_vector(void)
{
    /* Signs | low parts (LSB-first) | unary quotients, written by hand. */
    const char encoded[] = "01010101" "0000111100001111" "1111010100010001";
    const int32_t expected[8] = {0, -1, 3, -4, 4, -5, 15, -16};
    uint8_t bits[41];
    int32_t decoded[8];
    size_t used = 99U;

    assert(sizeof(encoded) - 1U == 40U);
    for (size_t i = 0U; i < 40U; i++) {
        bits[i] = (uint8_t)(encoded[i] - '0');
    }
    bits[40] = 255U; /* A following field is not part of this encoding. */
    assert(DecompressGR(decoded, bits, sizeof bits, 8U, &used, 2U, 4U) == 0);
    assert(used == 40U);
    assert(memcmp(decoded, expected, sizeof expected) == 0);

    for (size_t length = 0U; length < 40U; length++) {
        used = 99U;
        assert(DecompressGR(decoded, bits, length, 8U, &used, 2U, 4U) < 0);
        assert(used == 0U);
    }
    for (size_t index = 0U; index < 40U; index++) {
        uint8_t saved = bits[index];
        bits[index] = 2U;
        assert(DecompressGR(decoded, bits, 40U, 8U, &used, 2U, 4U) == -3);
        assert(used == 0U);
        bits[index] = saved;
    }

    /* high-low=2: quotient 4 is invalid even if followed by a terminator. */
    memset(bits + 24U, 0, 4U);
    bits[28] = 1U;
    assert(DecompressGR(decoded, bits, 40U, 8U, &used, 2U, 4U) == -3);
}

static void integer_limits(void)
{
    uint8_t bits[264];
    int32_t decoded[8];
    size_t used;

    /* low=high=31: no unary zeros; positive and negative extrema. */
    memset(bits, 1, sizeof bits);
    for (size_t i = 0U; i < 8U; i++) {
        bits[i] = (uint8_t)(i & 1U);
    }
    assert(DecompressGR(decoded, bits, sizeof bits, 8U, &used, 31U, 31U) == 0);
    assert(used == sizeof bits);
    for (size_t i = 0U; i < 8U; i++) {
        assert(decoded[i] == ((i & 1U) ? INT32_MIN : INT32_MAX));
    }

    memset(bits + 8U, 1, 8U);
    assert(DecompressGR(decoded, bits, 16U, 8U, &used, 0U, 0U) == 0);
    assert(used == 16U);
    for (size_t i = 0U; i < 8U; i++) {
        assert(decoded[i] == ((i & 1U) ? -1 : 0));
    }

    assert(DecompressGR(NULL, bits, sizeof bits, 8U, &used, 2U, 4U) == -1);
    assert(DecompressGR(decoded, NULL, 0U, 8U, &used, 2U, 4U) == -1);
    assert(DecompressGR(decoded, bits, sizeof bits, 8U, NULL, 2U, 4U) == -1);
    assert(DecompressGR(decoded, bits, sizeof bits, 0U, &used, 2U, 4U) == -1);
    assert(DecompressGR(decoded, bits, sizeof bits, 7U, &used, 2U, 4U) == -1);
    assert(DecompressGR(decoded, bits, sizeof bits, 8U, &used, 5U, 4U) == -1);
    assert(DecompressGR(decoded, bits, sizeof bits, 8U, &used, 0U, 32U) == -1);
    assert(DecompressGR(decoded, bits, 0U, UINT32_MAX - 7U, &used, 0U, 31U) == -2);
}

static void round_trip(uint32_t k, uint8_t low, uint8_t high)
{
    const uint32_t limit = UINT32_C(1) << high;
    const size_t capacity = (size_t)k * ((size_t)low + 1U +
                              (UINT32_C(1) << (high - low)));
    int8_t *bits = malloc(capacity);
    int32_t *input = malloc((size_t)k * sizeof *input);
    int32_t *decoded = malloc((size_t)k * sizeof *decoded);
    uint32_t length;
    size_t used;

    assert(bits != NULL && input != NULL && decoded != NULL);
    for (uint32_t i = 0U; i < k; i++) {
        uint32_t value = (i * UINT32_C(2654435761) + k) % limit;
        input[i] = (i & 1U) ? -(int32_t)value - 1 : (int32_t)value;
    }
    input[0] = 0;
    input[1] = -1;
    input[2] = (int32_t)limit - 1;
    input[3] = -(int32_t)limit;
    assert(CompressGR(bits, input, k, &length, low, high) == 0);
    assert((size_t)length <= capacity);
    assert(DecompressGR(decoded, (const uint8_t *)bits, length,
                        k, &used, low, high) == 0);
    assert(used == length);
    assert(memcmp(input, decoded, (size_t)k * sizeof *input) == 0);
    free(decoded);
    free(input);
    free(bits);
}

int main(void)
{
    const uint32_t lengths[] = {128U, 256U, 512U, 1024U};
    const uint8_t parameters[][2] = {{5U, 9U}, {8U, 11U}, {9U, 12U},
                                     {10U, 14U}, {6U, 10U}, {0U, 4U}};

    known_vector();
    integer_limits();
    for (size_t i = 0U; i < sizeof lengths / sizeof lengths[0]; i++) {
        for (size_t j = 0U; j < sizeof parameters / sizeof parameters[0]; j++) {
            round_trip(lengths[i], parameters[j][0], parameters[j][1]);
        }
    }
    puts("PASS: DecompressGR, known vector, malformed inputs, integer limits and 24 round trips");
    return 0;
}
