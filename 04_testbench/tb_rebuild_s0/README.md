# RebuildS0 testbench

El testbench conserva las tres pruebas basicas y anade tres casos numericos
de 512 coeficientes. Los casos se ejecutan consecutivamente, sin reset entre
operaciones validas.

| Prueba | Entradas y comprobacion |
| --- | --- |
| 1 | q01=w1=0, q00[0]=1: w0=-h0 (empate redondeado hacia arriba) |
| 2 | q00[0]=-1: done y error, sin salida valida |
| 3 | Recuperacion tras error y pausas de entrada: w0=-h0 |
| 4 | q00[0]=64, resto cero; q01 y w1 densos, signos mixtos |
| 5 | Como 4, con q00[1]=3, q00[511]=-3, q00[7]=-2, q00[505]=2 |
| 6 | Como 5, invirtiendo el signo de todos los coeficientes de q01 |

Los casos 4..6 comparan exactamente cada salida con un modelo entero separado,
sin tolerancia y sin obtener los valores esperados del DUT. Usan una semilla
fija (20261002); producen resultados entre -112 y 112. Mas de 450 coeficientes
por caso difieren de h0. Las pausas incluyen datos invalidos deliberadamente
distintos para detectar su consumo accidental. Se comprueban timeout, numero
de salidas, datos desconocidos, error, terminacion prematura y ausencia de
salidas/pulsos done durante cuatro ciclos tras terminar.

## Modelo de referencia

`generate_vectors.py` implementa las ecuaciones enteras FFT/IFFT del software
(`05_software/src/fft_transform.c`), productos complejos, division hacia cero
y el redondeo final `z=floor((t+c_s0*h0+c_s0)/(2*c_s0))` del algoritmo 18.
Usa enteros Python sin desbordamiento
intermedio y comprueba que los resultados almacenados caben en 32 bits.
Incluye dos anclas analiticas de impulso con signos opuestos para verificar
normalizacion y floor. Los twiddles se calculan matematicamente, mientras que
la simulacion independiente carga la ROM real `delta_rom.coe`.

Los seis casos del testbench basico usan n=512 y los desplazamientos
q00=20, q01=17, w1=19, s0=8.

`run_runtime.py` comprueba ademas la secuencia 256, 512, 1024, 256 sin reset,
con un vector denso independiente por operacion, comparacion de todos los
coeficientes y comprobacion de los umbrales 2223, 8317 y 20218.
Tambien prueba el bloque threshold con normas umbral-1, umbral y umbral+1.
El modelo Python selecciona los desplazamientos de cada variante.

```powershell
python 04_testbench/tb_rebuild_s0/run_runtime.py
```

Desde la raiz del repositorio:

```powershell
python 04_testbench/tb_rebuild_s0/generate_vectors.py
python 04_testbench/tb_rebuild_s0/run_standalone.py
```

Las constantes generadas estan incluidas en el propio VHDL: no hay que anadir
un paquete ni configurar rutas de ficheros de vectores en Vivado. Ejecutar
`rebuild_s0_tb` durante 4 ms o mas. El `finish` final esta comentado para
mantener abierta la simulacion interactiva; el script batch limita la duracion
a 10 ms. Con Run All y el reloj activo es necesario pausar manualmente.
Cualquier diferencia es `severity failure`.

## Alcance de la validacion

Las seis pruebas pasan con XSim 2022.1 en 3.650186 ms simulados, usando el RTL
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


## Division secuencial

`03_design/signed_divider.vhd` debe compilarse antes de `rebuild_s0.vhd`.
Rebuild comparte una instancia entre las componentes real e imaginaria:
start, espera de done, captura del cociente, y siguiente componente.
El divisor captura los operandos al aceptar start mientras esta libre y procesa
un bit por ciclo (65 ciclos con los anchos actuales), truncando hacia cero.
Un divisor cero produce cociente cero y divide_by_zero; reset aborta el calculo.
El caso minimo signed dividido por -1 desborda y conserva el patron de bits
modulo 2^g_numerator_width. Rebuild excluye ese caso mediante sus cotas previas.

Ejecutar `python 04_testbench/tb_rebuild_s0/run_divider.py` para 249 casos
reproducibles, incluidos limites, signos, entradas cambiantes y reset activo.
`run_runtime.py` comprueba los tamanos 256, 512, 1024 y 256 sin reset.
Estas pruebas usan modelos de memoria; el cierre de timing requiere volver a
sintetizar e implementar con las IP reales. Al actualizar la IP empaquetada,
incluir signed_divider en los grupos de sintesis y simulacion, actualizar la IP
del block design y regenerar sus productos antes de lanzar las ejecuciones.


## Operandos FFT registrados

ST_CAPTURE_FFT captura q01_re_operand, q01_im_operand, w1_re_operand y
w1_im_operand desde las salidas de memoria. ST_MUL_FFT calcula los cuatro
productos desde esos registros, y ST_CALC_X conserva la suma/resta siguiente.
La secuencia de lectura de BRAM, las divisiones y la salida no cambian.
Se agrega un ciclo por pareja compleja, es decir n/2 ciclos por reconstruccion
valida: 512 ciclos (5,12 us a 100 MHz) para n=1024. Las pruebas funcionales
usan modelos de memoria; la mejora de timing debe verificarse en implementacion.
