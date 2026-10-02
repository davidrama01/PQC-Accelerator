# RebuildS0 testbench

El testbench conserva las tres pruebas basicas y anade tres casos numericos
de 512 coeficientes. Los casos se ejecutan consecutivamente, sin reset entre
operaciones validas.

| Prueba | Entradas y comprobacion |
| --- | --- |
| 1 | q01=w1=0, q00[0]=1: w0=h0 |
| 2 | q00[0]=-1: done y error, sin salida valida |
| 3 | Recuperacion tras error y pausas de entrada: w0=h0 |
| 4 | q00[0]=64, resto cero; q01 y w1 densos, signos mixtos |
| 5 | Como 4, con q00[1]=3, q00[511]=-3, q00[7]=-2, q00[505]=2 |
| 6 | Como 5, invirtiendo el signo de todos los coeficientes de q01 |

Los casos 4..6 comparan exactamente cada salida con un modelo entero separado,
sin tolerancia y sin obtener los valores esperados del DUT. Usan una semilla
fija (20261002); producen resultados entre -20 y 23. Mas de 450 coeficientes
por caso difieren de h0. Las pausas incluyen datos invalidos deliberadamente
distintos para detectar su consumo accidental. Se comprueban timeout, numero
de salidas, datos desconocidos, error, terminacion prematura y ausencia de
salidas/pulsos done durante cuatro ciclos tras terminar.

## Modelo de referencia

`generate_vectors.py` implementa las ecuaciones enteras FFT/IFFT del software
(`05_software/src/fft_transform.c`), productos complejos, division hacia cero
y el redondeo final hacia menos infinito. Usa enteros Python sin desbordamiento
intermedio y comprueba que los resultados almacenados caben en 32 bits.
Incluye dos anclas analiticas de impulso con signos opuestos para verificar
normalizacion y floor. Los twiddles se calculan matematicamente, mientras que
la simulacion independiente carga la ROM real `delta_rom.coe`.

El modelo esta fijado a n=512 y a los desplazamientos actuales de hawk_pkg:
q00=20, q01=17, w1=19, s0=8. Si cambian, hay que actualizar el modelo y regenerar.

Desde la raiz del repositorio:

```powershell
python 04_testbench/tb_rebuild_s0/generate_vectors.py
python 04_testbench/tb_rebuild_s0/run_standalone.py
```

Las constantes generadas estan incluidas en el propio VHDL: no hay que anadir
un paquete ni configurar rutas de ficheros de vectores en Vivado. Ejecutar
`rebuild_s0_tb` durante 2 ms o mas. El `finish` final esta comentado para
mantener abierta la simulacion interactiva; el script batch limita la duracion
a 3 ms. Con Run All y el reloj activo es necesario pausar manualmente.
Cualquier diferencia es `severity failure`.

## Alcance de la validacion

Las seis pruebas pasan con XSim 2022.1 en 1.934986 ms simulados, usando el RTL
real de FFT, IFFT y rebuild. Tambien se han ejecutado con las IP de Xilinx
generadas en el proyecto vecino `C:/David/TFM/project_1`: blk_mem_gen_1,
blk_mem_gen_2 y fifo_generator_0, con su fichero de inicializacion de ROM.
El script independiente utiliza modelos de BRAM
de dos ciclos, ROM de un ciclo y FIFO estandar de un ciclo (no FWFT). No debe
anadirse ningun modelo generado al proyecto que ya tiene las IP de Xilinx.
Los modelos y logs se guardan en el directorio temporal indicado por el script.

La BRAM de ese proyecto tiene registro de salida sin REGCE independiente:
EN debe permanecer activo durante los dos ciclos de lectura. Rebuild mantiene
ahora EN en ST_WAIT_FFT_2 y ST_RD_Q01_WAIT_2. Antes de esta correccion, la IP
conservaba datos anteriores y la prueba 4 activaba error en u=2 a 938166 ns.
El modelo independiente tambien condiciona el registro de salida a EN para
reproducir este comportamiento. Otras configuraciones de IP deben validarse
por separado.

La cobertura es numerica y de protocolo para estos casos; no es una prueba
exhaustiva ni una certificacion contra la especificacion HAWK. Quedan fuera
otras dimensiones, reset durante calculo, todos los limites aritmeticos y las
ramas de error por denominador/cociente fuera de rango y por z fuera de rango.
