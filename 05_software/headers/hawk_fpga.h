#ifndef HAWK_FPGA_H
#define HAWK_FPGA_H

#include <stdint.h>
#include "hawk_params.h"

/* Inicializa una vez el AXI DMA usado por el acelerador HAWK. */
int HawkFpgaInit(void);

/*
 * Envia h0, h1, F mod 2, G mod 2, f y g al acelerador y recibe t0 y t1.
 * Los polinomios binarios contienen HAWK_N_WORDS32 palabras; f y g contienen
 * HAWK_N coeficientes completos de 32 bits con signo.
 */
int HawkFpgaCalculateT(const uint32_t h0[HAWK_N_WORDS32],
                       const uint32_t h1[HAWK_N_WORDS32],
                       const uint32_t F_mod2[HAWK_N_WORDS32],
                       const uint32_t G_mod2[HAWK_N_WORDS32],
                       const int32_t f[HAWK_N],
                       const int32_t g[HAWK_N],
                       uint32_t t0[HAWK_N_WORDS32],
                       uint32_t t1[HAWK_N_WORDS32]);

#endif
