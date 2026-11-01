/* Extracto documental de hawk_params.c.
   Seleccion de parametros; se omiten las tablas y las estructuras constantes.
   Seleccion parcial: depende de declaraciones y auxiliares omitidos. */

int hawk_select_params(uint32_t n)
{
    switch (n) {
    case 256: hawk_current_params = &params_256; return 0;
    case 512: hawk_current_params = &params_512; return 0;
    case 1024: hawk_current_params = &params_1024; return 0;
    default: return -1;
    }
}
