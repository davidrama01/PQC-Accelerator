#include "ntt_transform.h"
#include "hawk_params.h"
#include "basic.h"
#include <stdint.h>
#include <math.h>

/* Multiplica dos residuos usando 64 bits y reduce el resultado modulo p. */
static uint32_t mod_mul(uint32_t a, uint32_t b, uint32_t p)
{
    return (uint32_t)(((uint64_t)a * b) % p);
}

/* Calcula base^exp mod p mediante exponenciacion binaria. */
static uint32_t mod_pow(uint32_t base, uint32_t exp, uint32_t p)
{
    uint32_t result = 1U;

    while (exp > 0U)
    {
        if (exp & 1U)
        {
            result = mod_mul(result, base, p);
        }

        base = mod_mul(base, base, p);
        exp >>= 1U;
    }

    return result;
}

/* Busca el menor generador del grupo multiplicativo modulo el primo p. */
uint32_t find_generator(uint32_t p)
{
    uint32_t phi = p - 1U;

    const uint32_t factors_p1[] = {
        2U, 1048571U
    };

    const uint32_t factors_p2[] = {
        2U, 3U, 5U, 7U, 4993U
    };

    const uint32_t *factors;
    uint32_t number_factors;

    if (p == P1) {
        factors = factors_p1;
        number_factors = sizeof(factors_p1) / sizeof(factors_p1[0]);
    } else if (p == P2) {
        factors = factors_p2;
        number_factors = sizeof(factors_p2) / sizeof(factors_p2[0]);
    } else {
        return 0U;
    }

    for (uint32_t g = 2U; g < p; g++) {
        uint32_t valid = 1U;

        for (uint32_t i = 0; i < number_factors; i++) {
            if (mod_pow(g,
                        phi / factors[i],
                        p) == 1U) {
                valid = 0U;
                break;
            }
        }
        if (valid) {
            return g;
        }
    }
    return 0U;
}

/* Obtiene una raiz primitiva de orden 2n a partir del generador g. */
uint32_t compute_gamma(uint32_t g, uint32_t p, uint32_t n)
{
    return mod_pow(g, (p - 1U) / (2U * n), p);
}

/* Devuelve Gamma[index] aplicando el orden bit-reversal requerido por la NTT. */
uint32_t gamma_function(uint32_t g, uint32_t p, uint32_t n, uint32_t index)
{
    uint32_t log_bits       = log2_uint(n);
    uint32_t gamma          = compute_gamma(g, p, n);
    uint32_t index_rev      = bit_reverse(index, log_bits);
    uint32_t gamma_result   = mod_pow(gamma, index_rev, p);
    return gamma_result;
    
}

/* Transforma in-place un polinomio a representacion NTT modulo p. */
void NTT(uint32_t *u, uint32_t g, uint32_t p, uint32_t n)
{
    uint32_t u0;
    uint32_t u1;
    uint32_t s;
    uint32_t t = n;
    uint32_t m = 1U;
    uint32_t su1;
    while (m < n)
    {
        t = t/2U;
        for (uint32_t i = 0; i < m; i++)
        {
            s = gamma_function(g, p, n, (i+m));
            for (uint32_t j = 0; j < t; j++)
            {
                u0 = u[2*t*i+j];
                u1 = u[2*t*i+t+j];
                su1 = mod_mul(s,u1,p);
                u[2*t*i+j] = u0 + su1;
                if (u[2*t*i+j] >= p)
                {
                    u[2*t*i+j] -= p;
                }
                if (u0 >= su1)
                {
                    u[2*t*i+t+j] = u0 - su1;
                } else {
                    u[2*t*i+t+j] = u0 - su1 + p;
                }
            }
        }
        m = m*2U;
    }
}

/* Comprueba invertibilidad modulo p verificando que la NTT no contiene ceros. */
uint32_t IsInvertible (const int32_t *u, uint32_t g, uint32_t p, uint32_t n)
{
    uint32_t u_ntt[n];
    int64_t value;
    for (uint32_t i = 0U; i < n; i++)
    {
        value = u[i] % (int64_t)p;
        if (value < 0)
        {
            value += p;
        }
        u_ntt[i] = (uint32_t)value;
    }
    NTT(u_ntt, g, p, n);
    for (uint32_t i = 0U; i < n; i++)
    {
        if (u_ntt[i] == 0)
        {
            return 0;
        }
    }
    return 1;
}

/* Comprueba invertibilidad modulo 2 mediante la paridad de la suma. */
uint32_t IsInvertible_mod2 (const int32_t *u, uint32_t n)
{
    uint32_t u_mod2;
    uint32_t sum = 0;
    for (uint32_t i = 0U; i < n; i++)
    {
        u_mod2 = ((uint32_t)u[i]) & 1U;
        sum = sum ^ u_mod2;
    }
    if (sum == 1)
    {
        return 1;
    } else {
        return 0;
    }
}
