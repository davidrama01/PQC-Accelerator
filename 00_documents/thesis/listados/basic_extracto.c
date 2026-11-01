/* Extracto documental de basic.c.
   Adjunto, producto negaciclico y norma; se omiten las otras utilidades.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

void reciprocal(int32_t *f, int32_t *f_rec, uint32_t n)
{
    f_rec[0] = f[0];
    for (uint32_t i = 1U; i < n; i++) {
        f_rec[i] = -f[n - i];
    }
}

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

int32_t norm(const int32_t *f, const int32_t *g, uint32_t n)
{
    int64_t sum = 0;
    for (uint32_t i = 0U; i < n; i++) {
        sum += (int64_t)f[i] * f[i];
        sum += (int64_t)g[i] * g[i];
    }
    return (int32_t)sum;
}
