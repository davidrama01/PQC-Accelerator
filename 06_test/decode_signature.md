# DecodeSignature

Implementado en `05_software/src/decode.c`, declarado en `decode.h`.
Sigue el algoritmo 11 de la especificacion HAWK del repositorio.

    int DecodeSignature(uint8_t *salt, int32_t *s1,
                        const uint8_t *sig, size_t sig_len);

La entrada son HAWK_SIG_BYTES bytes: salt seguido de s1 comprimido y relleno.
La salida salt necesita HAWK_SALTLEN_BYTES bytes y s1 necesita HAWK_N int32_t.
Los parametros se obtienen de hawk_params.h, igual que EncodeSignature.

Devuelve 0 en exito, -1 por argumentos, -2 por longitud incorrecta y -3 por
codificacion invalida. En error s1 puede estar parcialmente escrito; salt
solo se copia al terminar correctamente. Comprueba la compresion y el relleno
de ceros; la comprobacion criptografica pertenece al verificador posterior.

## Pruebas

Desde la raiz del repositorio:

    python .\06_test\run_decode_signature.py

Compila con C99, -O2 -Wall -Wextra -Werror. Selecciona cada variante mediante
copias locales de los headers, sin modificar la configuracion del proyecto.
Ejecutables y logs en `06_test/.work/decode_signature`.

Resultado obtenido el 2026-10-24: PASS en HAWK-256, HAWK-512 y HAWK-1024.

- 50 vectores por variante (150 en total), creados por un escritor de bits
  independiente de CompressGR/EncodeSignature.
- Comparacion completa de salt y s1, codificacion de referencia y
  recodificacion identica byte a byte con EncodeSignature.
- Coeficientes cero, negativos, densos y extremos de los limites admitidos;
  transiciones entre parte baja y cociente unario.
- Canarios antes y despues de ambos buffers de salida.
- Rechazo de cada bit de relleno cambiado a uno, cocientes excesivos,
  terminador final ausente, cargas de ceros/unos, todas las longitudes
  truncadas, longitud excesiva y punteros nulos.
- Variaciones de cada byte de salt: conserva el valor exacto sin alterar s1.
