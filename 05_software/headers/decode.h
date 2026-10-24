#ifndef DECODE_H
#define DECODE_H

#include <stdint.h>
#include <stddef.h>
#include "hawk_params.h"

uint64_t DecodeInt(const uint8_t *buf,
                   size_t k_bits);

/*
 * Descomprime k coeficientes Golomb-Rice (k positivo y multiplo de 8).
 * bits contiene un bit 0/1 por byte, no bytes empaquetados; sus campos
 * enteros estan en orden LSB-first, como en CompressGR/DecodeInt.
 * x debe tener espacio para k int32_t. low <= high <= 31.
 * En exito devuelve 0 y escribe los bits consumidos en used_bits; los bits
 * posteriores quedan para el llamador (no comprueba el relleno).
 * Errores: -1 argumentos, -2 entrada truncada, -3 codificacion invalida.
 * En error used_bits queda a cero y x puede estar parcialmente modificado.
 */
int DecompressGR(int32_t *x,
                 const uint8_t *bits,
                 size_t bits_len,
                 uint32_t k,
                 size_t *used_bits,
                 uint8_t low,
                 uint8_t high);

int DecodePrivate(uint8_t *kgseed,
                  uint8_t *F_mod2,
                  uint8_t *G_mod2,
                  uint8_t *hpub,
                  const uint8_t *priv,
                  size_t priv_len);

/*
 * Algoritmo 9: decodifica una clave publica empaquetada LSB-first.
 * q00 y q01 deben disponer de HAWK_N coeficientes int32_t cada uno.
 * Exige HAWK_PUB_BYTES bytes y comprueba ambos rellenos de ceros.
 * Devuelve 0 en exito; -1 argumentos, -2 longitud, -3 codificacion.
 * En error los polinomios pueden estar parcialmente modificados.
 */
int DecodePublic(int32_t *q00,
                 int32_t *q01,
                 const uint8_t *pub,
                 size_t pub_len);

/*
 * Algoritmo 11: separa el salt y descomprime s1 de una firma empaquetada.
 * salt necesita HAWK_SALTLEN_BYTES bytes; s1, HAWK_N int32_t.
 * Exige HAWK_SIG_BYTES bytes y relleno final de ceros.
 * Devuelve 0 en exito; -1 argumentos, -2 longitud, -3 codificacion.
 * En error s1 puede estar parcialmente modificado. No verifica la firma.
 */
int DecodeSignature(uint8_t *salt,
                    int32_t *s1,
                    const uint8_t *sig,
                    size_t sig_len);

#endif
