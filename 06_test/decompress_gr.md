# Prueba de DecompressGR

Fuente: main_decompress_gr_test.c. Comprueba un vector manual, entradas
truncadas, bits invalidos, codigos unarios fuera de rango, extremos int32_t
y 24 combinaciones de longitud y parametros mediante CompressGR.

Desde la raiz del repositorio, crear primero 06_test/.work y ejecutar:

    gcc -std=c99 -Wall -Wextra -Werror -I05_software/headers 05_software/src/decode.c 05_software/src/encode.c 06_test/main_decompress_gr_test.c -o 06_test/.work/test_decompress_gr.exe
    ./06_test/.work/test_decompress_gr.exe

Resultado obtenido: PASS (2026-10-24). Compilacion con -Wall -Wextra
-Werror y ejecucion completadas con codigo de salida 0.
