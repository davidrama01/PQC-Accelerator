/* Extracto documental de ntt_transform.c.
   NTT y comprobaciones de invertibilidad; se omiten las funciones de raices y aritmetica modular.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

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
