#ifndef TOWERSOLVER_H
#define TOWERSOLVER_H

#include <stdint.h>

void extended_gcd(int32_t a, int32_t b, int32_t *gcd, int32_t *x, int32_t *y);

int towersolver(int32_t *f, int32_t *g, int32_t *f_solve, int32_t *g_solve, int32_t n);

#endif