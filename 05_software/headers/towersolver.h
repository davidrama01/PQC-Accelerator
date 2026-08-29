#ifndef TOWERSOLVER_H
#define TOWERSOLVER_H

#include <stdint.h>

int towersolver(int32_t *f, int32_t *g, int32_t *f_solve, int32_t *g_solve, int32_t n);

/* Comprueba (1/q00)[0] < beta_0 con la FFT fixed-point oficial de HAWK. */
int hawk_check_q00_beta(const int32_t *q00, uint32_t n);

#endif
