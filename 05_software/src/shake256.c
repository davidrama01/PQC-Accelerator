#include <string.h>
#include <stdint.h>
#include "shake256.h"

#define SHAKE256_RATE 136

static const uint64_t keccakf_rndc[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL,
    0x800000000000808aULL, 0x8000000080008000ULL,
    0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL,
    0x000000000000008aULL, 0x0000000000000088ULL,
    0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL,
    0x8000000000008089ULL, 0x8000000000008003ULL,
    0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL,
    0x8000000080008081ULL, 0x8000000000008080ULL,
    0x0000000080000001ULL, 0x8000000080008008ULL
};

static const int keccakf_rotc[24] = {
    1, 3, 6, 10, 15, 21,
    28, 36, 45, 55, 2, 14,
    27, 41, 56, 8, 25, 43,
    62, 18, 39, 61, 20, 44
};

static const int keccakf_piln[24] = {
    10, 7, 11, 17, 18, 3,
    5, 16, 8, 21, 24, 4,
    15, 23, 19, 13, 12, 2,
    20, 14, 22, 9, 6, 1
};

/* Rota una palabra de 64 bits a la izquierda. */
static uint64_t rol64(uint64_t x, int s)
{
    return (x << s) | (x >> (64 - s));
}

/* Aplica las 24 rondas de la permutacion Keccak-f[1600]. */
static void keccakf(uint64_t st[25])
{
    int i, j, round;
    uint64_t t, bc[5];

    for (round = 0; round < 24; round++) {

        for (i = 0; i < 5; i++)
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];

        for (i = 0; i < 5; i++) {
            t = bc[(i + 4) % 5] ^ rol64(bc[(i + 1) % 5], 1);
            for (j = 0; j < 25; j += 5)
                st[j + i] ^= t;
        }

        t = st[1];
        for (i = 0; i < 24; i++) {
            j = keccakf_piln[i];
            bc[0] = st[j];
            st[j] = rol64(t, keccakf_rotc[i]);
            t = bc[0];
        }

        for (j = 0; j < 25; j += 5) {
            for (i = 0; i < 5; i++)
                bc[i] = st[j + i];

            for (i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }

        st[0] ^= keccakf_rndc[round];
    }
}

/* Absorbe bytes little-endian mediante XOR en el estado Keccak. */
static void xor_bytes_into_state(uint64_t st[25], const uint8_t *in, size_t len)
{
    uint8_t *s = (uint8_t *)st;

    for (size_t i = 0; i < len; i++)
        s[i] ^= in[i];
}

/* Calcula SHAKE256: absorbe in y extrae outlen bytes del XOF. */
void shake256(uint8_t *out, size_t outlen,
              const uint8_t *in, size_t inlen)
{
    uint64_t st[25];
    uint8_t *s = (uint8_t *)st;
    size_t i;

    memset(st, 0, sizeof(st));

    while (inlen >= SHAKE256_RATE) {
        xor_bytes_into_state(st, in, SHAKE256_RATE);
        keccakf(st);

        in += SHAKE256_RATE;
        inlen -= SHAKE256_RATE;
    }

    xor_bytes_into_state(st, in, inlen);

    s[inlen] ^= 0x1F;
    s[SHAKE256_RATE - 1] ^= 0x80;

    keccakf(st);

    while (outlen > 0) {
        size_t block_size = outlen < SHAKE256_RATE ? outlen : SHAKE256_RATE;

        for (i = 0; i < block_size; i++)
            out[i] = s[i];

        out += block_size;
        outlen -= block_size;

        if (outlen > 0)
            keccakf(st);
    }
}

/* Decodifica hasta 64 bits little-endian desde una secuencia de bytes. */
uint64_t DecodeIntBytes(const uint8_t *buf, size_t k_bits)
{
    uint64_t x = 0;

    for (size_t i = 0; i < k_bits; i++) {
        size_t byte_pos = i / 8;
        size_t bit_pos  = i % 8;

        uint64_t bit = (buf[byte_pos] >> bit_pos) & 1ULL;

        x |= bit << i;
    }

    return x;
}

/* Codifica los k bits bajos de x en bytes little-endian. */
void EncodeIntBytes(uint8_t *out, uint64_t x, size_t k_bits)
{
    size_t nbytes = (k_bits + 7) / 8;

    for (size_t b = 0; b < nbytes; b++) {
        out[b] = 0;
    }

    for (size_t i = 0; i < k_bits; i++) {
        size_t byte_pos = i / 8;
        size_t bit_pos  = i % 8;

        out[byte_pos] |= ((x >> i) & 1ULL) << bit_pos;
    }
}

/* Genera palabras de 64 bits interpretando la salida de SHAKE256. */
void shake256w(uint64_t *w, size_t nwords,
               const uint8_t *m, size_t mlen)
{
    uint8_t buf[8 * nwords];

    shake256(buf, sizeof(buf), m, mlen);

    for (size_t i = 0; i < nwords; i++) {
        w[i] = DecodeIntBytes(&buf[8 * i], 64);
    }
}

/* Ejecuta cuatro dominios SHAKE256 y concatena sus palabras de salida. */
void shake256x4(uint64_t *out, size_t nwords,
                const uint8_t *m, size_t mlen)
{
    for (size_t j = 0; j < 4; j++) {

        uint8_t msg_ext[mlen + 1];

        for (size_t t = 0; t < mlen; t++) {
            msg_ext[t] = m[t];
        }

        EncodeIntBytes(&msg_ext[mlen], j, 8);

        uint64_t tmp[nwords];

        shake256w(tmp, nwords, msg_ext, mlen + 1);

        for (size_t i = 0; i < nwords; i++) {
            out[4 * i + j] = tmp[i];
        }
    }
}
