# DecodePublic

Implementado en `05_software/src/decode.c`, declarado en `decode.h`.
Sigue el algoritmo 9 de la especificacion HAWK del repositorio.

    int DecodePublic(int32_t *q00, int32_t *q01,
                     const uint8_t *pub, size_t pub_len);

La entrada son los bytes empaquetados de la clave publica, en orden LSB-first.
Las salidas necesitan espacio para HAWK_N coeficientes int32_t cada una.
HAWK_N, las longitudes y los limites se obtienen de hawk_params.h.
Devuelve 0 en exito; -1 por argumentos, -2 por longitud incorrecta y -3 por
codificacion invalida. En error, las salidas pueden estar parcialmente escritas.

La funcion comprueba la longitud exacta, descomprime la primera mitad de q00,
restaura los bits bajos de q00[0], valida el relleno hasta el siguiente byte,
reconstruye la mitad autoadjunta, descomprime q01 y valida el relleno final.
Estas son comprobaciones de codificacion; la validez criptografica de la clave
y de la firma corresponde a las etapas posteriores de verificacion.

## Pruebas

Desde la raiz del repositorio:

    python .\06_test\run_decode_public.py

Se compilan copias locales de los headers para cada variante, sin modificar
la seleccion del proyecto. Compilacion C99 con -O2 -Wall -Wextra -Werror.
Los ejecutables y logs quedan en `06_test/.work/decode_public`.

Resultado obtenido el 2026-10-24: PASS en HAWK-256, HAWK-512 y HAWK-1024.

- 50 vectores por variante (150 en total), codificados por un escritor de bits
  independiente de CompressGR/EncodePublic, y comparacion de todos los
  coeficientes decodificados.
- Comparacion con EncodePublic y recodificacion identica byte a byte.
- q00[0] positivo/negativo, casos alrededor de sus bits bajos y extremos
  -32768/32767; coeficientes cero, densos y limites Golomb-Rice.
- Verificacion de la reconstruccion completa de q00 y q00[n/2]=0.
- Rechazo de cada bit de relleno intermedio/final cuando se cambia a uno.
- Cocientes unarios excesivos en q00 y q01, claves de ceros/unos, todas las
  longitudes truncadas, longitud excesiva y punteros nulos.
