#include "ntt_transform.h"
#include "hawk_params.h"
#include "basic.h"
#include <stdint.h>

static uint32_t mod_mul(uint32_t a, uint32_t b, uint32_t p)
{
    return (uint32_t)(((uint64_t)a * b) % p);
}

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

uint32_t find_generator(uint32_t p)
{
    uint32_t phi = p - 1U;

    for (uint32_t g = 2U; g < p; g++)
    {
        if (mod_pow(g, phi / 2U, p) == 1U)
            continue;

        if (mod_pow(g, phi / 1048571U, p) == 1U)
            continue;

        return g;
    }

    return 0U;
}

uint32_t compute_gamma(uint32_t g, uint32_t p, uint32_t n)
{
    return mod_pow(g, (p - 1U) / (2U * n), p);
}

uint32_t gamma_function(uint32_t g, uint32_t p, uint32_t n, uint32_t index)
{
    uint32_t gamma_table = compute_gamma(g, p, n);
    uint32_t index_rev = bit_reverse(index, LOG_BITS);
    uint32_t gamma_result = mod_pow(gamma_table,index_rev,p);
    return gamma_result;
    
}

void NTT(uint32_t u[], uint32_t g, uint32_t p, uint32_t n, uint32_t index) 
{
    uint32_t u[HAWK_N];
    uint32_t u0;
    uint32_t u1;
    uint32_t s;
    uint32_t t = HAWK_N;
    uint32_t m = 1U;
    while (m < HAWK_N) 
    {
        t = t/2U;
        for (uint32_t i = 0; i < HAWK_N; i++)
        {
            s = gamma_function(g, p, n, (i+m));
            for (uint32_t j = 0; j < HAWK_N; j++)
            {
                u0 = u[2*t*i+j];
                u1 = u[2*t*i+t+j];
                u[2*t*i+j] = u0 + mod_mul(s,u1,p);
                if (u[2*t*i+j] >= p)
                {
                    u[2*t*i+j] -= p;
                }
                if (u0 >= mod_mul(s,u1,p))
                {
                    u[2*t*i+t+j] = u0 - mod_mul(s,u1,p);
                } else {
                    u[2*t*i+t+j] = u0 - mod_mul(s,u1,p) + p;
                }
            }
        }
        m = m*2U;
    }
    return u;
}

uint32_t IsInvertible (int32_t u[], uint32_t g, uint32_t p, uint32_t n, uint32_t index)
{
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        if (u[i] < 0U)
        {
            u[i] += p;
        }
    }
    NTT(u, g, p, n, index);
    for (uint32_t i = 0U; i < HAWK_N; i++)
    {
        if (u[i] == 0U)
        {
            return 0;
        }
    }
    return 1;
}

uint32_t IsInvertible_mod2 (int32_t u[])
{
    uint32_t u_mod2;
    uint32_t sum = 0;
    for (uint32_t i = 0U; i < HAWK_N; i++)
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