/* Extracto documental no compilable de helloworld.c.
   Se omiten buffers, mensajes UART y auxiliares de comprobacion.
   Las pruebas negativas se resumen mediante un comentario. */
static int run_case(uint32_t n)
{
    if (hawk_select_params(n) != 0)
        return -1;
    /* Dimensionar buffers despues de seleccionar los parametros.
       Inicializar case_checks y case_failures a cero. */
    keygen(pub, priv);
    int result = hawk_sign(sig, priv, message, sizeof message - 1U);
    if (result != 0)
        return -1;
    result = hawk_verify(sig, sizeof sig, pub, sizeof pub,
                         message, sizeof message - 1U);
    check_verify("original signature", result, 1);
    if (result != 1)
        return -1;
    /* Pruebas negativas con mensaje y salt alterados,
       firma y clave malformadas o truncadas, y errores FPGA.
       Verificar de nuevo la firma original tras los errores. */
    return case_failures == 0U ? 0 : -1;
}

int main(void)
{
    static const uint32_t sizes[] = {256U, 512U, 1024U};
    unsigned failures = 0U;
    init_platform();
    for (size_t i = 0U; i < sizeof sizes / sizeof sizes[0]; i++) {
        int result = run_case(sizes[i]);
        failures += result != 0;
    }
    cleanup_platform();
    return failures == 0U ? 0 : 1;
}
