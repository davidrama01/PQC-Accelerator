# Revision de PS y PL, 25-10-2026

No se ha encontrado otro fallo numerico en las pruebas descritas abajo,
despues de corregir la latencia de lectura de firma y el contador de salida
de t0/t1. Esto es una revision funcional acotada, no una prueba formal de
ausencia de errores ni una certificacion criptografica.

## Hallazgo pendiente: tiempo variable del muestreador

`05_software/src/sampler_sign.c`, funcion `u80_less` y lineas 58, 62, 69 y
75, contiene decisiones que dependen de datos secretos del muestreo.
Se ha compilado ese modulo con el GCC ARM de Vitis 2022.1, Cortex-A9 y -O0,
que coincide con la configuracion Debug actual. El ensamblador conserva
saltos condicionales en el comparador de 80 bits, los incrementos de v0/v1
y las selecciones de paridad/signo. Evidencia:
`06_test/.work/sampler_sign_arm_O0.s`.

La seccion de implementacion de SamplerSign en la especificacion local
(paginas impresas 39-40) recomienda evitar decisiones temporales sobre esos
secretos. Se confirma la presencia de saltos dependientes de secretos; no
se ha demostrado un ataque ni medido una fuga en la placa. El resultado
matematico del muestreador coincide con la referencia. Queda convertir
comparacion y seleccion a operaciones sin esos saltos y revisar el codigo
ARM resultante. Esta revision no ha modificado el muestreador de produccion.

## Pruebas nuevas realizadas

- `check_pipeline_variants.py`: claves reales, firma y verificacion PS para
  256, 512 y 1024, con backend matematico en lugar del acelerador. Pasan nueve
  firmas y sus correspondientes mensajes/codificaciones alterados se rechazan.
  Se exige igualdad exacta entre la norma muestreada y la verificada.
- `run_decode_public.py` y `run_decode_signature.py`: 50 vectores
  independientes por variante y por decodificador, ademas de entradas
  malformadas. Pasan los 300 vectores y los rechazos.
- `check_sampler_spec.py`: compara las tablas CDT con la Tabla 5 del PDF
  local; verifica SHAKE256x4, RegenerateFG y todos los coeficientes de
  SamplerSign para las tres variantes y patrones de paridad cero, uno y
  mixto. La referencia usa hashlib y enteros Python de precision arbitraria,
  no el comparador C de 80 bits. Pasa.
- `run_hawk_verify.py --runtime`: pasan hashes y paquetes contra hashlib,
  tamanos DMA, recepcion signed de s1, secuencia de registros, resultado
  valido/invalido, errores y timeouts, con hardware simulado. Se ha ajustado
  el test antiguo BUSY_RX a la implementacion actual: Verify no usa S2MM y
  no debe depender de que el canal receptor este inactivo. No se ha cambiado
  el driver de produccion.
- `check_verify_integration.py`: tres firmas validas de PS atraviesan el
  HawkVerify RTL completo, consecutivamente con longitudes 256/512/1024.
  Los modelos de memoria conservan la latencia de dos ciclos y las tablas
  COE actuales. Se comprueba cada coeficiente de w0 y ambos residuos, ademas
  de la aceptacion final. No se sustituyen FFT, divisiones, NTT ni normas.
- `check_verify_integration.py --real-ip --n 256`: repite la firma valida
  de 256 usando todas las memorias y FIFO de simulacion generadas por Xilinx.
  Pasa sin adaptaciones de puertos. La IP P2 actual ya es Single_Port_ROM.

| n | r1 = r2, RTL y referencia | Norma r/n | Limite |
|---|---:|---:|---:|
| 256 | 537344 | 2099 | 2223 |
| 512 | 3149824 | 6152 | 8317 |
| 1024 | 14235648 | 13902 | 20218 |

Los logs estan en `.work/pipeline_variants`, `.work/decode_public`,
`.work/decode_signature`, `.work/hawk_verify`, `.work/sampler_spec`,
`.work/verify_models/xsim.log` y `.work/verify_real/256/xsim.log`.

Los vectores para RTL se exportan desde el backend matematico solo tras
verificar la igualdad de normas; no se usan resultados de simulacion para
calcular los esperados. Las aserciones adicionales de w0/r1/r2 se inyectan
solo en una copia de HawkVerify dentro de .work; no anaden logica al hardware.
Las lineas HISTORICAL del test C conservan diagnosticos del RTL antiguo,
ahora etiquetados explicitamente; no describen la version actual.

## Alcance y limites

Se han revisado parametros, rangos signed/unsigned, redondeo de RebuildS0,
seleccion de tablas, latencias de lectura, reduccion modular, division,
calculo de normas, empaquetado y orden de las etapas. Las pruebas de firma
completa con BRAM real y sus correcciones estan en `sign_memory_audit.md`.

Las pruebas completas de verificacion con IP reales de este turno cubren
256; 512/1024 usan modelos de memoria con la misma latencia. No se ha probado
el nuevo bitstream en la PYNQ-Z2, el DMA fisico, el cierre de timing, la
fuente externa de entropia ni interoperabilidad con una implementacion
externa de HAWK. No se puede concluir que cualquier entrada posible sea
correcta solo porque estos vectores pasan.
