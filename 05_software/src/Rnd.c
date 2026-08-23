#include "Rnd.h"
#include "shake256.h"

#include "xil_printf.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/*
 * El Zynq-7000 no tiene TRNG integrado. En la primera llamada se reciben por
 * UART 32 bytes generados por una fuente externa segura. SHAKE256 expande la
 * semilla y actualiza el estado despues de cada bloque generado.
 */
static uint8_t rng_state[32];
static uint64_t rng_counter;
static int rng_initialized;

/* Recibe por UART 256 bits de entropia y con ellos inicializa el estado. */
static void rng_initialize(void)
{
    uint8_t entropy[32];

    xil_printf("Send 32 random bytes through UART.\r\n");
    for (size_t i = 0; i < sizeof(entropy); i++) {
        entropy[i] = (uint8_t)inbyte();
    }

    shake256(rng_state, sizeof(rng_state), entropy, sizeof(entropy));
    memset(entropy, 0, sizeof(entropy));
    rng_counter = 0U;
    rng_initialized = 1;
}

/* Genera num_bits pseudoaleatorios con SHAKE256 y actualiza el estado interno. */
int Rnd(uint8_t *out, size_t num_bits)
{
    uint8_t input[40];
    uint8_t block[64];
    size_t num_bytes;
    size_t produced = 0U;

    if (out == NULL || num_bits == 0U) {
        return -1;
    }

    if (!rng_initialized) {
        rng_initialize();
    }

    num_bytes = (num_bits + 7U) / 8U;

    while (produced < num_bytes) {
        size_t amount = num_bytes - produced;

        if (amount > 32U) {
            amount = 32U;
        }

        memcpy(input, rng_state, sizeof(rng_state));

        for (size_t i = 0; i < 8U; i++) {
            input[32U + i] = (uint8_t)(rng_counter >> (8U * i));
        }

        shake256(block, sizeof(block), input, sizeof(input));
        memcpy(out + produced, block, amount);
        memcpy(rng_state, block + 32U, sizeof(rng_state));

        produced += amount;
        rng_counter++;
    }

    if ((num_bits & 7U) != 0U) {
        out[num_bytes - 1U] &= (uint8_t)((1U << (num_bits & 7U)) - 1U);
    }

    memset(input, 0, sizeof(input));
    memset(block, 0, sizeof(block));
    return 0;
}
