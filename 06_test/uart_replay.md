# Reproducir la verificacion del log UART

`replay_uart_verify.py` extrae `public_key` y `signature` de una variante
del log. Usa el mensaje indicado (por defecto `Hola HAWK`, el del programa
actual), ejecuta el frontend C real y captura h0, q00, q01 y w1.
No necesita ni reproduce la clave privada. Es una reconstruccion de las
entradas a partir del log, no una captura de las transferencias AXI/DMA.

El resultado esperado procede del backend matematico de
`main_hawk_pipeline_test.c`, con los parametros actuales. Una firma del log
puede ser rechazada por ese backend; el test RTL comprueba que coincidan
aceptacion/rechazo, no presupone que las firmas sean validas.

Ejemplo desde la raiz del repositorio:

```powershell
python 06_test/replay_uart_verify.py RUTA_AL_LOG --n 512
```

Usa los productos de simulacion generados del proyecto `02_project/hawk_acc`
y XSim 2022.1. Los resultados quedan en `06_test/.work/uart_replay/512`.
`--ps-only` ejecuta unicamente la comprobacion matematica.

Si la IP P2 esta configurada como RAM y el componente RTL como ROM, XSim
falla en elaboracion por las entradas `wea` y `dina` ausentes. La opcion
`--tie-rom-write-inputs` conecta esas entradas a cero exclusivamente en una
copia temporal de `ntt.vhd`, para poder continuar la comparacion con la
misma memoria inicializada y su latencia. No cambia el RTL de produccion,
la IP ni el proyecto de Vivado. Esta variante no demuestra que el diseno
original sin esas conexiones funcione en hardware.

La prueba cubre HawkVerify completo y las IP de memoria/FIFO de Xilinx.
No cubre AXI, DMA, la generacion PL de la firma ni interoperabilidad con
otra implementacion externa. Los modelos de Xilinx tampoco representan
exactamente las colisiones de memoria del dispositivo fisico.
