# Testbench de HawkVerify

`hawk_verify_tb.vhd` prueba el RTL completo: `sym_break_w1`, `rebuild_s0`,
las dos instancias de `polyqnorm`, FIFO, conversion a residuos y salida.
Los vectores estan incluidos en el VHDL; no necesita abrir archivos TXT.

## Ejecutar desde PowerShell

Desde la raiz del repositorio:

```powershell
python -B 04_testbench/tb_hawk_verify/run_hawk_verify.py
```

Por defecto lee las IP generadas de `C:/David/TFM/project_1` y utiliza Vivado
2022.1 en `C:/Xilinx/Vivado/2022.1/bin`. Ambos directorios se pueden cambiar
con `--project` y `--vivado-bin`. No modifica el proyecto de Vivado.

Compila en un directorio temporal, cuya ruta imprime al comenzar. Alli quedan
los logs, los MIF copiados y el snapshot de simulacion. Utiliza las IP reales
de simulacion Xilinx; no reemplaza los bloques de calculo ni las memorias.
El script comprueba tambien que ningun componente quede sin enlazar.

## Ejecutar en Vivado

1. Anadir `hawk_verify_tb.vhd` a Simulation Sources y seleccionarlo como top.
2. Utilizar VHDL-2008 para el testbench y los archivos de diseno.
3. Incluir `hawk_pkg.vhd`, `fft.vhd`, `ifft.vhd`, `rebuild_s0.vhd`, `ntt.vhd`,
   `polyqnorm.vhd`, `sym_break_w1.vhd` y `hawk_verify.vhd`.
4. Incluir las IP `fifo_generator_0` y `blk_mem_gen_1/2/3/4`, con sus productos
   de simulacion generados y las tablas Delta/Gamma correspondientes.
5. Lanzar la simulacion y ejecutar **Run All**.

El testbench usa `stop` al completar las pruebas, para poder inspeccionar el
waveform. El mensaje de exito es:

```text
PASS: HawkVerify, todos los casos y resets superados
```

## Cobertura

Los 13 casos se ejecutan consecutivamente sin reset externo:

| Caso | Comprobacion | Error esperado |
| --- | --- | --- |
| 0 | Impulso valido | 0 |
| 1 | q00[0] negativo: rechazo temprano de RebuildS0 | 1 |
| 2 | Recuperacion; primer w1 no nulo en indice 511; h0 no uniforme | 0 |
| 3 | w1 completamente cero | 1 |
| 4 | Primer w1 no nulo negativo, seguido de uno positivo | 1 |
| 5 | Residuos P1/P2 distintos | 1 |
| 6 | Residuos iguales a 1, no divisibles entre 512 | 1 |
| 7 | Norma 6688, debajo del umbral | 0 |
| 8 | Norma 6689, exactamente el umbral | 0 |
| 9 | Norma 6690, encima del umbral | 1 |
| 10 | Recuperacion, w1 denso con signos y h0 no uniforme | 0 |
| 11 | q00 no constante y q01/w1 densos | 1 |
| 12 | Recuperacion final | 0 |

Antes de estos casos se aplica reset externo durante una carga parcial,
durante RebuildS0 y durante PolyQnorm. Tambien se comprueban:

- Pausas de `ack_in` sin introducir X.
- Un unico anuncio `start_out` y una unica transferencia por operacion.
- `data_out` estable y `valid` mantenido mientras `ready=0`.
- Receptor listo de antemano en los casos alternos.
- `input_ready=0` durante calculo, salida y limpieza.
- Recuperacion de `input_ready` con timeout, sin depender de un numero exacto
  de ciclos de reset interno.
- Datos ofrecidos durante la limpieza que no contaminan la siguiente carga.
- Ausencia de controles desconocidos, resultados prematuros y salidas extra.

## Oraculos y regeneracion

```powershell
python -B 04_testbench/tb_hawk_verify/generate_vectors.py
```

El generador reutiliza el modelo entero independiente de RebuildS0 y el modelo
de PolyQnorm por evaluacion directa en raices, sin leer salidas del DUT.
Comprueba ademas resultados analiticos de los casos de residuos y umbral.
Actualiza las constantes del testbench y `expected_results.json` (solo para
consulta; Vivado no necesita este JSON).

Son pruebas del bloque que recibe `h0`, `q00`, `q01` y `w1`, no de la
decodificacion ni del hashing de una firma completa. Los casos validos son
entradas algebraicas del bloque, no un corpus de firmas HAWK publicadas.
La simulacion comprueba comportamiento; no valida sintesis ni temporizacion.
