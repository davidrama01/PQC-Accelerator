#ifndef HAWK_VERIFY_H
#define HAWK_VERIFY_H

#include <stddef.h>
#include <stdint.h>
#include "hawk_params.h"

/*
 * Verificacion HAWK asistida por el acelerador de Vitis (Algoritmo 20).
 * La variante activa se selecciona con hawk_select_params(n) y se programa
 * en la FPGA. No cambiarla durante una operacion ni entre una clave/firma
 * y su uso: sus formatos dependen del conjunto de parametros.
 * Devuelve 1 si verifica, 0 si la firma/clave no es valida y un valor
 * negativo en error: -1 argumentos, -2 memoria, -3 comunicacion con FPGA.
 * message puede ser NULL solo si message_len es cero.
 * No admite llamadas concurrentes: el controlador comparte DMA y buffers.
 */
int hawk_verify(const uint8_t *sig,
                size_t sig_len,
                const uint8_t *pub,
                size_t pub_len,
                const uint8_t *message,
                size_t message_len);

#endif
