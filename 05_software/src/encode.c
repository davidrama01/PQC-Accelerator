#include <string.h>
#include "encode.h"
#include "hawk_params.h"

int EncodeInt(int8_t *buf, uint32_t x, uint32_t k_bits)
{
    if (x > (1 << k_bits) - 1) {
        return -1; // Error: k_bits exceeds the size of uint32_t
    }
    for (uint32_t i = 0; i < k_bits; i++) {
        buf[i] = (x >> i) & 1U;
    }
    return 0;
}

void PackBits(uint8_t *out, const int8_t *bits, uint32_t number_bits)
{
    uint32_t number_bytes = (number_bits + 7U) / 8U;

    for (uint32_t i = 0; i < number_bytes; i++) {
        out[i] = 0;

        for (uint32_t j = 0; j < 8U; j++) {
            uint32_t bit_index = 8U * i + j;

            if (bit_index < number_bits) {
                out[i] |= (uint8_t)((bits[bit_index] & 1U) << j);
            }
        }
    }
}

int EncodePrivate(uint8_t *priv,
                  size_t priv_len,
                  const uint8_t *kgseed,
                  const uint8_t *F_mod2,
                  const uint8_t *G_mod2,
                  const uint8_t *hpub)
{
    if (priv == NULL || kgseed == NULL || F_mod2 == NULL || G_mod2 == NULL || hpub == NULL) {
        return -1;
    }

    if (priv_len != HAWK_PRIV_BYTES) {
        return -1;
    }
    size_t offset = 0;

    memcpy(priv + offset, kgseed, HAWK_KGSEED_BYTES);
    offset += HAWK_KGSEED_BYTES;

    memcpy(priv + offset, F_mod2, HAWK_N_BYTES);
    offset += HAWK_N_BYTES;

    memcpy(priv + offset, G_mod2, HAWK_N_BYTES);
    offset += HAWK_N_BYTES;

    memcpy(priv + offset, hpub, HAWK_HPUB_BYTES);
    offset += HAWK_HPUB_BYTES;
    return 0;
}

int CompressGR(int8_t *y,
               const int32_t *x,
               uint32_t k,
               uint32_t *y_len_bits,
               uint8_t low,
               uint8_t high)
{
    int8_t s;
    int32_t v[k];
    int32_t offset = 0;
    int8_t v_encode[k];
    for (uint32_t i = 0; i < k; i++) {
        if (x[i] < 0) {
            s = 1;
        } else {
            s = 0;
        }
        y[offset++] = s;
        v[i] = x[i] - s*(2*x[i] + 1);

        if (v[i] >= (1LL << high)) {
            return -1;
        }
    }
    for (uint32_t i = 0; i < k; i++) {
        EncodeInt(v_encode, v[i] % (1LL << low), low);
        for (uint32_t j = 0; j < low; j++) {
            y[offset++] = v_encode[j];
        }
    }

    for (uint32_t i = 0; i < k; i++) {
        EncodeInt(v_encode, 0, v[i] >> low);
        for (uint32_t j = 0; j < v[i] >> low; j++) {
            y[offset++] = v_encode[j];
        }
        y[offset++] = 1;
    }

    *y_len_bits = offset;

    return 0;
}

int EncodePublic(uint8_t *pub, int32_t *q00, int32_t *q01, uint32_t n)
{
    if (n != HAWK_N) {
        return -1;
    }
    
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    // Calculate q00
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    uint32_t y00_len_bits = 0;
    if (q00[0] < -(1 << 15) || q00[0] >= (1 << 15)) {
        return -1;
    }
    int32_t v = 16 - HAWK_Q00_HIGH_BITS;
    int32_t q00_half[n / 2U];

    for (uint32_t i = 0; i < n / 2U; i++) {
        q00_half[i] = q00[i];
    }

    int32_t divisor = 1 << v;

    q00_half[0] = q00[0] / divisor;

    if (q00[0] < 0 && (q00[0] % divisor) != 0) {
        q00_half[0]--;
    }
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    // Calculate y00
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    int8_t y00[Y00_MAX_BITS + v + 7U];
    int result = CompressGR(y00, q00_half, n/2, &y00_len_bits, HAWK_Q00_LOW_BITS, HAWK_Q00_HIGH_BITS);
    if (result != 0) {
        return -1;
    }

    int32_t q00_low = q00[0] % divisor;

    if (q00_low < 0) {
        q00_low += divisor;
    }

    if (EncodeInt(y00 + y00_len_bits, (uint32_t)q00_low, v) != 0) {
        return -1;
    }

    y00_len_bits += v;

    while ((y00_len_bits % 8U) != 0U) {
        y00[y00_len_bits++] = 0;
    }

    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    // Calculate y01
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    int8_t y01[Y01_MAX_BITS];
    uint32_t y01_len_bits = 0;
    result = CompressGR(y01, q01, n, &y01_len_bits, HAWK_Q01_LOW_BITS, HAWK_Q01_HIGH_BITS);
    if (result != 0) {
        return -1;
    }
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    // Calculate y
    //-------------------------------------------------------------------
    //-------------------------------------------------------------------
    uint32_t publen_bits = HAWK_PUB_BYTES * 8U;

    if (y00_len_bits > publen_bits ||
        y01_len_bits > publen_bits - y00_len_bits) {
        return -1;
    }

    uint32_t total_len_bits = 0;
    int8_t pub_buffer[publen_bits];

    for (uint32_t i = 0; i < y00_len_bits; i++) {
        pub_buffer[total_len_bits++] = y00[i];
    }

    for (uint32_t i = 0; i < y01_len_bits; i++) {
        pub_buffer[total_len_bits++] = y01[i];
    }

    while (total_len_bits < publen_bits) {
        pub_buffer[total_len_bits++] = 0;
    }

    PackBits(pub, pub_buffer, publen_bits);
    return 0;
}

int EncodeSignature(uint8_t *sig,
                    uint32_t sig_len_bits,
                    const uint8_t *salt,
                    const int32_t *s1)
{
    uint32_t y_len_bits = 0;

    int8_t y[YS1_MAX_BITS];

    if (sig_len_bits != HAWK_SIG_BYTES * 8U) {
        return -1;
    }

    int result_GR = CompressGR(y, s1, HAWK_N, &y_len_bits, HAWK_S1_LOW_BITS, HAWK_S1_HIGH_BITS);
    if (result_GR != 0 || y_len_bits > sig_len_bits - HAWK_SALTLEN_BITS) {
        return -1;
    }

    while (y_len_bits < (sig_len_bits - HAWK_SALTLEN_BITS)) {
        y[y_len_bits++] = 0;
    }
    uint32_t y_len_bytes = y_len_bits / 8;
    uint8_t y_bytes[y_len_bytes];
    PackBits(y_bytes, y, y_len_bits);

    /* sig = salt || y */
    memcpy(sig, salt, HAWK_SALTLEN_BYTES);

    memcpy(sig + HAWK_SALTLEN_BYTES, y_bytes, y_len_bytes);

    return 0;
}
