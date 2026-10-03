# NTT (Algoritmo 21)

`03_design/ntt.vhd` mantiene los tres procesos (estado, transiciones y
datapath), RAM de doble puerto y ROM de twiddles. La mariposa opera sobre
residuos unsigned: `su1 = Gamma[i+m]*u1 mod p`, y produce `u0+su1` y
`u0-su1`, ambos reducidos a `[0,p-1]`. No hay formato complejo ni escalado Q31.

Configuracion actual para n=512:

- `blk_mem_gen_1`: RAM de doble puerto, 512 x 32, direcciones de 9 bits,
  lectura de dos ciclos. EN permanece activo en ambos ciclos de lectura.
- `blk_mem_gen_3`: ROM Gamma, 512 x 32, direcciones de 9 bits, EN,
  lectura de uno o dos ciclos. Cargar `gamma_p1_n512.coe` para el modulo
  por defecto `g_modulus=2147473409`.
- `blk_mem_gen_4`: ROM con la misma interfaz, cargada con `gamma_p2_n512.coe`.
  Se instancia cuando `g_modulus=2147389441`.
- Los bloques `gen_gamma_p1` y `gen_gamma_p2` seleccionan la IP durante la
  elaboracion: solo se instancia la correspondiente al generico. Los unicos
  modulos admitidos son P1 y P2; no es una seleccion durante la ejecucion.
- Las entradas deben estar reducidas a `[0,p-1]`. Un coeficiente negativo
  se entrega como su residuo modulo p, no en complemento a dos.
- Tras reset, aplicar `start` durante un ciclo y enviar las 512 entradas
  desde el siguiente ciclo. Solo se consumen cuando `data_in_valid='1'`.
- La salida conserva el orden NTT del algoritmo (raices impares en orden
  bit-reversal); no se aplica una permutacion adicional. Se producen 512
  palabras consecutivas. `done` dura un ciclo y coincide con la ultima.
- La reduccion del producto usa `mod` con modulo constante. No se ha
  introducido un reductor Montgomery/Barrett ni cambiado la arquitectura
  para optimizar area o frecuencia. La frecuencia objetivo necesita su
  propia comprobacion de timing.

No anadir los modelos temporales al proyecto que contiene las IP reales.
Las ROM `blk_mem_gen_3` (P1) y `blk_mem_gen_4` (P2) deben crearse/configurarse
en el proyecto Vivado;
el generador de COE no crea una IP por si solo.

## Validacion reproducible

Desde la raiz del repositorio, con Python y Vivado 2022.1:

```powershell
python -B 04_testbench/tb_ntt/run_ntt.py
```

Para utilizar la RAM de Xilinx del proyecto vecino:

```powershell
python -B 04_testbench/tb_ntt/run_ntt.py --ram-ip C:/David/TFM/project_1/project_1.gen/sources_1/ip/blk_mem_gen_1/sim/blk_mem_gen_1.v
```

El script genera ambos archivos de vectores en un directorio temporal y
lanza una unica simulacion. `ntt_tb` instancia dos DUT mediante generate:

- `modules(0).dut`: P1, lee `vectors_p1.txt`.
- `modules(1).dut`: P2, lee `vectors_p2.txt`.

Cada instancia tiene sus propias entradas, salidas, estimulos y comprobaciones.
Solo comparten reloj. No se inyectan X: durante las pausas se mantiene el dato.
Cada modulo ejecuta seis casos; `stop` se llama solo cuando ambos han terminado
correctamente. Los mensajes identifican P1/P2. El testbench ya no tiene generico
`g_modulus`; las dos constantes se conectan a los genericos de sus respectivos DUT.

## Proyecto Vivado

`configure_vivado.tcl` configura las ROM y el conjunto `sim_ntt`, que queda
activo, con `ntt_tb.vhd` como top y ambos TXT como Data Files. Tambien actualiza
los antiguos conjuntos `sim_ntt_p1` y `sim_ntt_p2` para que no conserven el
antiguo generico y tengan ambos archivos. No elimina esos conjuntos ni sim_1.
Guarda una copia del XPR antes de modificarlo, ejecuta la prueba y registra ondas.

Para regenerar los archivos de datos:

```powershell
python -B 04_testbench/tb_ntt/run_ntt.py --vectors-only
```

En Vivado: activar `sim_ntt`, Run Behavioral Simulation y Run All. Si el proyecto
estaba abierto al modificarlo externamente, volver a abrirlo para cargar los cambios.
No hace falta cambiar de modulo ni ejecutar dos veces. En Scope se pueden examinar
`modules(0)` y `modules(1)` para ver las señales de cada instancia.

Por modulo se comprueban 3072 coeficientes: ceros, impulso en 0, impulso en 511,
todos p-1, patron 0/1/p-1/p-2 y vector pseudoaleatorio reproducible. Los resultados
se obtienen por evaluacion directa del polinomio en raices impares, independiente
de los bucles de mariposas del RTL. Tambien se comprueban pausas de carga,
ejecuciones consecutivas, reset durante carga/calculo, rango, conteo, timeout,
salida continua y done. En total son 12 casos y 6144 coeficientes.

El script Python usa modelos de las ROM; la opcion --ram-ip permite utilizar la
RAM de Xilinx. La configuracion de Vivado usa las IP reales de RAM y ambas ROM.
La validacion es funcional; no comprueba timing ni sustituye la implementacion.
