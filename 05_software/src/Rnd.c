#include "Rnd.h"
#include "hawk_params.h"

#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <stdio.h>

int Rnd(uint8_t *out, size_t num_bits)
{   
    srand((unsigned)time(NULL));

    if (out == NULL || num_bits == 0) {
        return -1;
        printf("Error: Invalid parameters for Rnd function.\n");
    }

    size_t num_bytes = (num_bits + 7) / 8;

    for (size_t i = 0; i < num_bytes; i++) {
        out[i] = (uint8_t)(rand() & 0xFF);
    }

    /* Eliminar los bits sobrantes del último byte */
    if (num_bits % 8 != 0) {
        out[num_bytes - 1] &= (1U << (num_bits % 8)) - 1U;
    }

    return 0;
}