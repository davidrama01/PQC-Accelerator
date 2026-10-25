# Helloworld con los tres tamanos

`05_software/src/helloworld.c` ejecuta en un mismo programa:

1. Seleccionar HAWK-256, generar claves, firmar `Hola HAWK` y verificar.
2. Repetir con HAWK-512.
3. Repetir con HAWK-1024.

Muestra las claves y firma de cada caso, PASS/FAIL y el total de casos
correctos. Devuelve 0 si pasan los tres y 1 si alguno falla.

## Vitis

Incluir el nuevo `05_software/src/hawk_params.c` junto con los otros fuentes
del programa. La configuracion predeterminada es ahora seleccion en ejecucion:
`hawk_select_params(256)`, `hawk_select_params(512)` o `hawk_select_params(1024)`.
La seleccion incluye longitudes de claves/firma, limites, sigma y las tablas
T0/T1 del muestreador. No basta con cambiar el registro de longitud de la FPGA.

El controlador reserva capacidad maxima de 1024 y ajusta tanto las longitudes
DMA/cache como el registro de longitud al conjunto activo. No se necesita
recompilar el programa ni resintetizar entre los tres casos.

Seleccionar parametros solo entre operaciones terminadas. Todas las funciones
comparten el conjunto activo y no admiten usos concurrentes de variantes.
Cada clave y firma debe usarse con el mismo conjunto con el que se genero.
Un n no soportado devuelve -1 sin cambiar la seleccion. El valor inicial es 512.

Los algoritmos usan arrays locales de longitud variable: la pila del linker
de Vitis debe dimensionarse para los algoritmos completos a n=1024, no solo
para los pequenos buffers de helloworld. Esto no se valida en la prueba host.

Los tests antiguos que compilan una variante independiente usan
`HAWK_FIXED_PARAMS`; no definirlo para este helloworld.

## Pruebas host

```powershell
python .\06_test\run_helloworld.py
python .\06_test\run_hawk_verify.py --runtime
```

La primera compila el helloworld real y ejecuta los tres casos con los
algoritmos C reales y un modelo matematico de las operaciones FPGA. Sustituye
Rnd por una fuente determinista de prueba y las llamadas de plataforma.
Los tres casos pasan en un mismo ejecutable.

La segunda prueba el controlador FPGA real con perifericos simulados para
cada variante: paquetes independientes de hashlib, longitud DMA, registro n,
alineacion/cache, resultado aceptado/rechazado y fallos de comunicacion.
Tambien comprueba el retorno al modo de firma.

Son pruebas host: queda ejecutar el programa en Vitis sobre el acelerador y
las IP reales. Logs en `06_test/.work/helloworld/` y
`06_test/.work/hawk_verify/`.
