#ifndef BASIC_H
#define BASIC_H

#include <stdint.h>
#include <stdbool.h>

void reciprocal(int32_t *f, int32_t *f_rec, uint32_t n);

void poly_mul(const int32_t *a, const int32_t *b, int32_t *c, uint32_t n);

void poly_inverse(const int32_t *a, double *a_inv, uint32_t n);

int32_t norm(int32_t *f, int32_t *g, uint32_t n);

void conj(int32_t *f, int32_t *f_conj, uint32_t n);

void norm_ring (int32_t *f, int32_t *f_norm, uint32_t n);

void expand_ring (int32_t *f, int32_t *f_exp, uint32_t n);

uint32_t bit_reverse(uint32_t x, uint32_t k);

bool poly_is_zero(const int32_t *k, uint32_t n);

int32_t infinite_norm(const int32_t *a, const int32_t *b, uint32_t n);

#endif