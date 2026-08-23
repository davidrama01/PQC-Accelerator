#include <stdint.h>
#include "hawk_params.h"
#include "basic.h"
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>

/* Calcula el adjunto f*(x)=f(x^-1) en Z[x]/(x^n+1). */
void reciprocal(int32_t *f, int32_t *f_rec, uint32_t n)
{
    f_rec[0] = f[0];
    for (uint32_t i = 1U; i < n; i++) {
        f_rec[i] = -f[n - i];
    }
}

/* Multiplica dos polinomios modulo x^n+1 mediante convolucion negaciclica. */
void poly_mul(const int32_t *a, const int32_t *b, int32_t *c, uint32_t n)
{
    int64_t temp[n];
    for (uint32_t i = 0U; i < n; i++) {
        temp[i] = 0;
    }

    for (uint32_t i = 0U; i < n; i++) {
        for (uint32_t j = 0U; j < n; j++) {
            uint32_t k = i + j;
            int64_t product = (int64_t)a[i] * b[j];
            if (k >= n) {
                k -= n;
                product = -product;
            }
            temp[k] += product;
        }
    }

    for (uint32_t i = 0U; i < n; i++) {
        c[i] = (int32_t)temp[i];
    }
}

/* Variante en double de la multiplicacion negaciclica, usada por la inversion. */
static void poly_mul_d(const double *a, const double *b, double *c, uint32_t n)
{
    double temp[n];
    for (uint32_t i = 0U; i < n; i++) {
        temp[i] = 0.0;
    }

    for (uint32_t i = 0U; i < n; i++) {
        for (uint32_t j = 0U; j < n; j++) {
            uint32_t k = i + j;
            double product = a[i] * b[j];
            if (k >= n) {
                k -= n;
                product = -product;
            }
            temp[k] += product;
        }
    }

    for (uint32_t i = 0U; i < n; i++) {
        c[i] = temp[i];
    }
}

/* Aproxima sobre los racionales el inverso de a modulo x^n+1. */
void poly_inverse(const int32_t *a, double *a_inv, uint32_t n)
{
    double a_d[n];
    for (uint32_t i = 0U; i < n; i++) {
        a_d[i] = (double)a[i];
    }

    for (uint32_t i = 0U; i < n; i++) {
        a_inv[i] = 0.0;
    }

    if (a_d[0] == 0.0) {
        return;
    }

    a_inv[0] = 1.0 / a_d[0];

    double t[n];
    double u[n];

    for (uint32_t m = 1U; m < n; m <<= 1) {
        poly_mul_d(a_d, a_inv, t, n);

        u[0] = 2.0 - t[0];
        for (uint32_t i = 1U; i < n; i++) {
            u[i] = -t[i];
        }

        poly_mul_d(a_inv, u, a_inv, n);
    }
}

/* Devuelve la norma cuadrada sum_i(f[i]^2+g[i]^2). */
int32_t norm(const int32_t *f, const int32_t *g, uint32_t n)
{
    int64_t sum = 0;

    for (uint32_t i = 0U; i < n; i++) {
        sum += (int64_t)f[i] * f[i];
        sum += (int64_t)g[i] * g[i];
    }

    return (int32_t)sum;
}

/* Calcula el conjugado de Galois f(-x), negando los grados impares. */
void poly_conj(int32_t *f, int32_t *f_conj, uint32_t n)
{
    for (uint32_t i = 0U; i < n; i++)
    {
        if (i % 2 == 0U) {
            f_conj[i] = f[i];
        } else {
            f_conj[i] = -f[i];
        }
    }
}

/* Proyecta f al subanillo de grado n/2 mediante la norma f(x)f(-x). */
void norm_ring (int32_t *f, int32_t *f_norm, uint32_t n)
{
    int32_t f_conj[n];
    int32_t f_prod[n];
    poly_conj(f, f_conj, n);
    poly_mul(f, f_conj, f_prod, n);
    for (uint32_t i = 0U; i < n/2U; i++) {
        f_norm[i] = f_prod[2*i];
    }
}

/* Eleva un polinomio del subanillo sustituyendo x por x^2. */
void expand_ring (int32_t *f, int32_t *f_exp, uint32_t n)
{
    for (uint32_t i = 0U; i < n; i++) {
        if (i % 2 == 0U) {
            f_exp[i] = f[i/2];
        } else {
            f_exp[i] = 0U;
        }
    }
}

/* Invierte el orden de los k bits menos significativos de x. */
uint32_t bit_reverse(uint32_t x, uint32_t k)
{
    uint32_t result = 0U;

    for (uint32_t i = 0U; i < k; i++)
    {
        result <<= 1U;
        result |= x & 1U;
        x >>= 1U;
    }

    return result;
}

/* Indica si todos los coeficientes del polinomio son cero. */
bool poly_is_zero(const int32_t *k, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++) {
        if (k[i] != 0) {
            return false;
        }
    }
    return true;
}

/* Devuelve el mayor valor absoluto entre los coeficientes de a y b. */
int32_t infinite_norm(const int32_t *a, const int32_t *b, uint32_t n)
{
    int32_t max_value = 0;
    for (uint32_t i = 0U; i < n; i++) {
        if (abs(a[i]) > max_value) {
            max_value = abs(a[i]);
        }
        if (abs(b[i]) > max_value) {
            max_value = abs(b[i]);
        }
    }
    return max_value;
}

/* Calcula floor(log2(n)) mediante desplazamientos enteros. */
uint32_t log2_uint(uint32_t n)
{
    uint32_t result = 0U;

    while (n > 1U) {
        n >>= 1U;
        result++;
    }

    return result;
}
