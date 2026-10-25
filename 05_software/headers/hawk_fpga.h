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

/* Envia x0 seguido de x1: HAWK_N coeficientes int32_t por polinomio. */
int HawkFpgaSendX(const int32_t x0[HAWK_N],
                  const int32_t x1[HAWK_N]);

/* Recibe mediante DMA los HAWK_N coeficientes de 32 bits de s1. */
int HawkFpgaReceiveS1(int32_t s1[HAWK_N]);

/*
 * Envia h0 || q00 || q01 || w1 por MM2S y espera el registro 0x0C.
 * Devuelve 0 si la operacion termina y escribe *error (0=valida, 1=fallo).
 * Un retorno negativo indica argumentos/configuracion/DMA/timeout, no una
 * firma incorrecta. Tras un fallo de transporte, reiniciar DMA/acelerador
 * antes de reintentar. No utilizar simultaneamente con la ruta de firma.
 */
int HawkFpgaVerify(const uint32_t h0[HAWK_N_WORDS32],
                   const int32_t q00[HAWK_N],
                   const int32_t q01[HAWK_N],
                   const int32_t w1[HAWK_N],
                   uint32_t *error);

#endif
