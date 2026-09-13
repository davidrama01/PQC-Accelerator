#ifndef BASIC_H
#define BASIC_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

int ConcatBytes2(uint8_t *out,
                 size_t out_len,
                 const uint8_t *first,
                 size_t first_len,
                 const uint8_t *second,
                 size_t second_len);

int ConcatBytes4(uint8_t *out,
                 size_t out_len,
                 const uint8_t *first,
                 size_t first_len,
                 const uint8_t *second,
                 size_t second_len,
                 const uint8_t *third,
                 size_t third_len,
                 const uint8_t *fourth,
                 size_t fourth_len);

int BytesToWords32(uint32_t *out,
                   size_t out_words,
                   const uint8_t *in,
                   size_t in_len);

int PolyParityToWords32(uint32_t *out,
                        size_t out_words,
                        const int8_t *poly,
                        size_t n);

void reciprocal(int32_t *f, int32_t *f_rec, uint32_t n);

void poly_mul(const int32_t *a, const int32_t *b, int32_t *c, uint32_t n);

void poly_inverse(const int32_t *a, double *a_inv, uint32_t n);

int32_t norm(const int32_t *f, const int32_t *g, uint32_t n);

void poly_conj(int32_t *f, int32_t *f_conj, uint32_t n);

void norm_ring (int32_t *f, int32_t *f_norm, uint32_t n);

void expand_ring (int32_t *f, int32_t *f_exp, uint32_t n);

uint32_t bit_reverse(uint32_t x, uint32_t k);

bool poly_is_zero(const int32_t *k, uint32_t n);

int32_t infinite_norm(const int32_t *a, const int32_t *b, uint32_t n);

uint32_t log2_uint(uint32_t n);

#endif
