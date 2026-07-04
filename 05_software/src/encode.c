#include <string.h>
#include "encode.h"
#include "hawk_params.h"

int EncodeInt(uint8_t *buf,
              uint64_t x,
              size_t k_bits)
{
    size_t nbytes = (k_bits + 7) / 8;

    if (buf == NULL || k_bits > 64) {
        return -1;
    }

    memset(buf, 0, nbytes);

    for (size_t i = 0; i < k_bits; i++) {
        size_t byte_pos = i / 8;
        size_t bit_pos  = i % 8;

        buf[byte_pos] |= (uint8_t)(((x >> i) & 1ULL) << bit_pos);
    }

    return 0;
}

int EncodePrivate(uint8_t *priv,
                  size_t priv_len,
                  const uint8_t *kgseed,
                  const uint8_t *F_mod2,
                  const uint8_t *G_mod2,
                  const uint8_t *hpub)
{
    size_t offset = 0;

    if (priv == NULL || kgseed == NULL || F_mod2 == NULL ||
        G_mod2 == NULL || hpub == NULL) {
        return -1;
    }

    if (priv_len != HAWK512_PRIV_BYTES) {
        return -2;
    }

    memcpy(priv + offset, kgseed, HAWK512_KGSEED_BYTES);
    offset += HAWK512_KGSEED_BYTES;

    memcpy(priv + offset, F_mod2, HAWK512_N_BYTES);
    offset += HAWK512_N_BYTES;

    memcpy(priv + offset, G_mod2, HAWK512_N_BYTES);
    offset += HAWK512_N_BYTES;

    memcpy(priv + offset, hpub, HAWK512_HPUB_BYTES);
    offset += HAWK512_HPUB_BYTES;

    return 0;
}

static int AppendBit(uint8_t *y,
                     size_t y_max_bytes,
                     size_t *bit_len,
                     uint8_t bit)
{
    size_t byte_pos = (*bit_len) / 8;
    size_t bit_pos  = (*bit_len) % 8;

    if (byte_pos >= y_max_bytes) {
        return -1;
    }

    if (bit) {
        y[byte_pos] |= (uint8_t)(1U << bit_pos);
    }

    (*bit_len)++;

    return 0;
}

static int AppendEncodeInt(uint8_t *y,
                           size_t y_max_bytes,
                           size_t *bit_len,
                           uint64_t value,
                           uint32_t k_bits)
{
    uint8_t tmp[8];

    if (EncodeInt(tmp, value, k_bits) != 0) {
        return -1;
    }

    for (uint32_t i = 0; i < k_bits; i++) {
        uint8_t bit = (uint8_t)((tmp[i / 8] >> (i % 8)) & 1U);

        if (AppendBit(y, y_max_bytes, bit_len, bit) != 0) {
            return -2;
        }
    }

    return 0;
}

int CompressGR(uint8_t *y,
               size_t y_max_bytes,
               size_t *y_len_bytes,
               size_t *y_len_bits,
               const int16_t *x,
               size_t k,
               uint32_t low,
               uint32_t high)
{
    if (y == NULL || y_len_bytes == NULL || y_len_bits == NULL || x == NULL) {
        return -1;
    }
    size_t bit_len = 0;
    uint32_t v[HAWK_N];

    if (y == NULL || y_len_bytes == NULL || x == NULL) {
        return -1;
    }

    if (k > HAWK_N) {
        return -2;
    }

    if (low > high || high >= 32) {
        return -3;
    }

    memset(y, 0, y_max_bytes);

    /*
     * Lines 3-8:
     * sign bits + computation of v[i]
     */

    for (size_t i = 0; i < k; i++) {
        int32_t xi = x[i];
        uint8_t s = (xi < 0) ? 1 : 0;

        if (AppendBit(y, y_max_bytes, &bit_len, s) != 0) {
            return -4;
        }

        /*
         * v[i] = |x[i] - s(2x[i] + 1)|
         */
        int32_t tmp = xi - ((int32_t)s * (2 * xi + 1));

        if (tmp < 0) {
            tmp = -tmp;
        }

        v[i] = (uint32_t)tmp;

        if (v[i] >= (1UL << high)) {
            return -5;
        }
    }

    /*
     * Lines 9-10:
     * y <- y || EncodeInt(v[i] mod 2^low, low)
     */

    for (size_t i = 0; i < k; i++) {
        uint32_t low_part;

        if (low == 0) {
            low_part = 0;
        } else {
            low_part = v[i] & ((1UL << low) - 1U);
        }

        if (AppendEncodeInt(y,
                            y_max_bytes,
                            &bit_len,
                            low_part,
                            low) != 0) {
            return -6;
        }
    }

    /*
     * Lines 11-12:
     * y <- y || EncodeInt(0, floor(v[i]/2^low)) || 1
     */

    for (size_t i = 0; i < k; i++) {
        uint32_t q = v[i] >> low;

        if (AppendEncodeInt(y,
                            y_max_bytes,
                            &bit_len,
                            0,
                            q) != 0) {
            return -7;
        }

        if (AppendBit(y, y_max_bytes, &bit_len, 1) != 0) {
            return -8;
        }
    }

    *y_len_bits = bit_len;
    *y_len_bytes = (bit_len + 7) / 8;

    return 0;
}

int EncodeSignature(uint8_t *sig,
                    size_t sig_len,
                    const uint8_t *salt,
                    const int16_t *s1)
{
    uint8_t y[HAWK_SIG_BYTES];
    size_t y_len_bytes = 0;
    size_t y_len_bits = 0;

    size_t max_y_bits;
    size_t max_y_bytes;

    if (sig == NULL || salt == NULL || s1 == NULL) {
        return -1;
    }

    if (sig_len != HAWK_SIG_BYTES) {
        return -2;
    }

    memset(sig, 0, sig_len);
    memset(y, 0, sizeof(y));

    /*
     * Algorithm 10, line 1:
     * y <- CompressGR(s1, lows1, highs1)
     */

    max_y_bits =
        (HAWK_SIG_BYTES * 8) - HAWK_SALTLEN_BITS;

    max_y_bytes =
        (max_y_bits + 7) / 8;

    int ret = CompressGR(y,
                         max_y_bytes,
                         &y_len_bytes,
                         &y_len_bits,
                         s1,
                         HAWK_N,
                         HAWK_S1_LOW_BITS,
                         HAWK_S1_HIGH_BITS);

    /*
     * Algorithm 10, lines 2-3:
     * if y = ⊥ or lenbits(y) > siglenbits - saltlenbits return ⊥
     */

    if (ret != 0) {
        return -3;
    }

    if (y_len_bits > max_y_bits) {
        return -4;
    }

    /*
     * Algorithm 10, lines 4-5:
     * while lenbits(y) < siglenbits - saltlenbits do
     *     y <- y || 0
     *
     * Como sig[] ya está inicializado a cero, el padding a 0 queda implícito.
     */

    /*
     * Algorithm 10, line 6:
     * return salt || y
     */

    memcpy(sig, salt, HAWK_SALTLEN_BYTES);
    memcpy(sig + HAWK_SALTLEN_BYTES, y, y_len_bytes);

    return 0;
}