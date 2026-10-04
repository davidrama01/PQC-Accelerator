# INTT (Algoritmo 22)

`03_design/intt.vhd` adapta la estructura de `ntt.vhd`: misma interfaz,
tres procesos, RAM de doble puerto y temporizacion de lectura/escritura.
La primera etapa tiene `m=256, t=1`; cada etapa divide `m` por dos y
duplica `t`, hasta `m=1, t=256`.

Para cada pareja calcula `(u0+u1)/2` y `Gamma_inv[m+i]*(u0-u1)/2`, modulo p.
La division modular suma p si el residuo es impar antes de desplazarlo.
Las nueve etapas incorporan el factor 1/512: no hay normalizacion adicional.
Las tablas inversas son inversos modulares de Gamma, sin escalado Montgomery.

## Interfaz e IP

- Configuracion admitida: 512 muestras, datos de 32 bits, direcciones de 9 bits.
- `g_modulus`: P1=2147473409 o P2=2147389441, seleccionado al elaborar.
- `blk_mem_gen_1`: misma definicion de RAM que NTT, doble puerto y lectura
  de dos ciclos con EN. Cada instancia tiene su propia memoria.
- `blk_mem_gen_5`: ROM 512x32, EN, cargada con `gamma_inv_p1_n512.coe`.
- `blk_mem_gen_6`: ROM equivalente, cargada con `gamma_inv_p2_n512.coe`.
- Las ROM admiten uno o dos ciclos de lectura.
- Aplicar `start` un ciclo estando en reposo. Desde el siguiente ciclo,
  se aceptan 512 residuos en [0,p-1] cuando `data_in_valid='1'`.
- La entrada conserva exactamente el orden producido por `ntt.vhd`.
  La salida entrega los coeficientes originales en orden natural, uno por
  ciclo. `done` coincide con la ultima de las 512 salidas validas.
- Reset sincrono activo bajo; permite abortar y comenzar otra operacion.

Para anadir los modulos y configurar las ROM directas e inversas en un proyecto
que ya contiene `blk_mem_gen_1`, ejecutar en la consola Tcl de Vivado:

```tcl
source C:/David/TFM/hawk_fw/04_testbench/tb_intt/configure_vivado.tcl
```

El script activa `sim_intt`, configura `intt_tb` como top y registra los cuatro
archivos `vectors_p*_*.txt` como **Data Files**, para que Vivado los copie al
directorio de XSim. Estos archivos se incluyen junto al testbench y se pueden
regenerar con `python -B 04_testbench/tb_intt/run_intt.py --vectors-only`.
Tras ejecutar el Tcl, cerrar la simulacion anterior y volver a lanzar
**Run Behavioral Simulation**. Un simple Restart no actualiza los archivos
del conjunto de simulacion.

## Validacion reproducible

```powershell
python -B 04_testbench/tb_intt/run_intt.py
```

Requiere Python y Vivado 2022.1 (ruta configurable con `--vivado-bin`).
Los modelos, vectores y logs se generan en un directorio temporal.
`--ram-ip <ruta/blk_mem_gen_1.v>` permite usar el modelo de RAM de Xilinx.
No anadir los modelos temporales al proyecto que contiene las IP reales.

El banco ejecuta cuatro instancias en paralelo:

- Lanes 0 y 1: INTT para P1/P2 contra la matriz inversa de evaluacion,
  calculada en Python sin reproducir los bucles de mariposas del RTL.
- Lanes 2 y 3: NTT RTL seguida de INTT RTL para P1/P2, con recuperacion
  exacta de los datos originales.

Cada instancia prueba ceros, impulsos en 0 y 511, todos p-1, un patron
0/1/p-1/p-2 y datos pseudoaleatorios reproducibles: 24 casos y 12.288
coeficientes. Comprueba pausas de carga, operaciones consecutivas, reset
durante carga/calculo, rango, conteo, salida continua, timeout y done.

Validacion ejecutada con XSim y modelos de memoria de dos ciclos: todos
los casos superados. Es una comprobacion funcional; no se ha ejecutado
sintesis ni analisis de timing. La reduccion usa `mod` por constante,
igual que el modulo NTT original.
