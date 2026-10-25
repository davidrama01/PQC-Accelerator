# PolyQnorm (Algoritmo 19)

`03_design/polyqnorm.vhd` conserva la interfaz prevista y la estructura
`p_state`, `p_next_state`, `p_datapath` con estados `ST_*`. Instancia cuatro
NTT y cuatro BRAM adicionales `blk_mem_gen_1`. Usa las ROM Gamma P1/P2 que
ya selecciona `ntt.vhd`; no requiere nuevas IP ni una iNTT.

## Operaciones

1. NTT de q00, q01, w0 y w1 en paralelo.
2. Para cada posicion: inverso de q00 mediante exponenciacion binaria
   `q00^(p-2) mod p`, `d=w1*inverso mod p`, `e=w0+d*q01 mod p`.
   q01_ram se reutiliza para e y w0_ram para d.
3. Lectura de q00[i], e[i], e[n-1-i], d[i] y w1[n-1-i].
   Calcula `c[i]=q00[i]*e[i]*e[n-1-i]+d[i]*w1[n-1-i] mod p`.
4. Acumula los n coeficientes modulo p y entrega un unico resultado.

En el orden bit-reversal de esta NTT, la raiz asociada a n-1-i es la inversa
de la asociada a i. Por tanto NTTadj se implementa invirtiendo direcciones;
no necesita LIFO ni transformada inversa. La division es inverso modular,
no division entera ni iNTT. No se divide el acumulado por n: la salida es
la indicada en el algoritmo, `n*norma_Q(w)^2 mod p` para las entradas Q validas.

Los productos tienen 64 bits para datos de 32 bits y se reducen en el estado
siguiente. Las sumas usan un bit de acarreo y reduccion modulo p. Las BRAM
mantienen EN durante ambos ciclos de lectura, incluido su registro de salida.

## Interfaz

- Configuracion actual: n=512, ancho=32, direcciones=9, P1 o P2.
- Las cuatro entradas son residuos unsigned `[0,p-1]`. Convertir los negativos
  a su residuo modulo p antes de enviarlos; no enviar complemento a dos.
- Aplicar reset y al menos un ciclo en reposo; pulsar start un ciclo. Desde
  el siguiente ciclo se consumen 512 cuaternas cuando data_in_valid=1.
- Se admiten pausas de carga; no se avanza el contador durante ellas.
- En una operacion valida, done y data_out_valid pulsan juntos durante un
  ciclo. data_out contiene un unico residuo; se conserva hasta otro start/reset.
- Si una entrada esta fuera de rango o NTT(q00) contiene un cero, done pulsa
  con error=1 y data_out_valid=0. Ignorar data_out en ese caso. Error permanece
  activo hasta el siguiente start aceptado o reset. Tras una entrada invalida,
  el emisor debe detener la carga de esa operacion cuando reciba done/error.
- Start mientras el bloque esta ocupado se ignora. El reset aborta tambien
  las cuatro NTT. Se puede iniciar otra operacion tras done, sin reset externo.

No se comprueba que q00/q01 procedan de una clave HAWK valida; se implementan
las operaciones del algoritmo sobre los residuos suministrados. La salida es
modular: la reconstruccion/comprobacion posterior usando ambos primos queda
fuera de este bloque. No se ha cerrado timing de la reduccion combinacional.
No hay report/assert en el RTL.

## Pruebas

```powershell
python -B 04_testbench/tb_polyqnorm/run_polyqnorm.py
```

El script lee las IP generadas de `C:/David/TFM/project_1` sin modificar el
proyecto; se puede indicar otro directorio con `--project`. Compila el RTL y
el testbench VHDL-2008 en un directorio temporal e incluye los MIF de Gamma.
Las IP RAM/ROM son los modelos de Xilinx del proyecto, no sustitutos propios.

`polyqnorm_tb.vhd` ejecuta P1 y P2 simultaneamente, seis casos validos y dos
errores por modulo: salida cero, norma de w0, norma de w1 con division no
trivial, q00 no constante/autoadjunto y vectores densos con signos mixtos,
residuos en todo el rango, denominador cero en posicion NTT 17, entrada fuera
de rango y recuperacion valida. Tambien verifica reset durante el calculo,
pausas de carga, timeout y pulsos de salida. No inyecta X.

El modelo Python evalua directamente los polinomios en todas las raices
impares, en orden natural, y calcula los adjuntos evaluando en las raices
inversas. No reproduce las mariposas ni la inversion de indices del RTL.
Comprueba ademas dos resultados analiticos simples.

Para preparar los datos junto al testbench:

```powershell
python -B 04_testbench/tb_polyqnorm/run_polyqnorm.py --vectors-only
```

En Vivado: anadir polyqnorm.vhd y ntt.vhd como VHDL-2008, las IP
blk_mem_gen_1/3/4 y, en Simulation Sources, polyqnorm_tb.vhd y ambos
polyqnorm_p1.txt/polyqnorm_p2.txt como Data Files. Seleccionar polyqnorm_tb
como top. Run All se pausa con stop solo cuando ambos modulos pasan.

El testbench busca primero los TXT en el directorio de trabajo de XSim.
Si no los encuentra, usa el generico `g_vectors_dir`, cuyo valor por defecto
es `C:/David/TFM/hawk_fw/04_testbench/tb_polyqnorm/`. Asi tambien funciona
sin copiar los TXT al directorio de simulacion. Si se mueve el repositorio,
actualizar este generico incluyendo la barra final. Un fallo al abrirlos
se comunica al inicio, antes de ejecutar las pruebas.


La reduccion del producto para e se registra ahora en `e_reduced` durante
ST_REDUCE_E. ST_ADD_E hace la suma modular en el ciclo siguiente; la escritura
en BRAM sigue en ST_COMMIT_E. Esto agrega un ciclo por coeficiente y separa
las dos operaciones sin cambiar la aritmetica.

Para probar el RTL con modelos de RAM y ROM de dos ciclos y las tablas Gamma
n1024 del repositorio (prefijos para n=512):

```powershell
python 04_testbench/tb_polyqnorm/run_polyqnorm.py --models
```

La prueba con IP reales usa por defecto 02_project/hawk_acc y requiere que
las IP generadas coincidan en ancho y puertos con el RTL. Los modelos no
validan esa configuracion ni el timing de implementacion.


## Reduccion modular secuencial

Compilar `03_design/mod_reducer.vhd` antes de polyqnorm. Una instancia por
PolyQnorm atiende sus siete operaciones de reduccion. Los estados ST_*REDUCE
inician la operacion y los estados correspondientes *_WAIT conservan los
operandos y esperan done antes de guardar el residuo. El reductor procesa
un bit por ciclo: 64 ciclos para cada producto, mas control. Captura la entrada
al aceptar start, mantiene el resultado y aborta operaciones al recibir reset.
La suma modular de e conserva su etapa independiente ST_ADD_E.

Esta implementacion prioriza recursos y caminos cortos sobre latencia:
la exponenciacion modular ejecuta muchas reducciones por coeficiente.
Los limites de simulacion de PolyQnorm y HawkVerify se han ampliado.
Los emisores deben esperar el resultado; revisar tambien los timeouts del
software antes de usar la nueva implementacion en placa.

Prueba independiente de limites, valores aleatorios y reset (418 casos P1/P2):

```powershell
python 04_testbench/tb_polyqnorm/run_reducer.py
```

La IP empaquetada incluye mod_reducer en los grupos de sintesis y simulacion.
Actualizar la IP del block design y regenerar los productos antes de sintetizar.
NTT e INTT tambien usan mod_reducer para reducir sus productos anchos.
No quedan operadores mod ejecutables en las fuentes VHDL de 03_design.


## Registros de operandos del multiplicador

Las siete operaciones que antes asignaban directamente un producto cargan
mul_operand_a y mul_operand_b en su estado ST_*MUL/ST_INV_SQUARE. Un estado
*_EXEC adicional deja registrar la multiplicacion antes de activar la reduccion.
Un proceso dedicado captura continuamente el producto de esos registros,
sin selector ni habilitacion dependiente de la FSM en la entrada del multiplicador.
mod_reducer captura ese producto al aceptar start y no depende de sus cambios
posteriores. Se agrega un ciclo por multiplicacion. Las sumas, validaciones,
reset e interfaces mantienen su comportamiento previo. La mejora de timing
requiere verificar sintesis e implementacion con las IP reales.


## Validacion de entrada registrada

input_invalid acumula en un registro las comparaciones de rango de cada
palabra aceptada (ST_LOAD con data_in_valid=1). La FSM solo consulta ese
registro; los datos crudos de FIFO ya no alimentan su decision de error.
Las NTT siguen recibiendo las mismas palabras en los mismos ciclos. Ante
una palabra invalida, se aborta y se reinician los nucleos internos mediante
la secuencia ST_ERROR existente. ST_CHECK_LOAD agrega un ciclo despues de
la ultima palabra para incluir su validacion antes de continuar.
El registro de error se limpia con reset o al aceptar el siguiente start.

El testbench prueba cada uno de los cuatro flujos con valor p invalido en
las posiciones 0, 255 y 511, recuperacion sin reset y valores invalidos
presentes durante huecos sin valid. Estos son 12 casos por primo ademas
de los 16 casos completos contra el modelo matematico.


## Acumulacion final en dos ciclos

ST_SUM_TERMS registra add_mod(term_a, term_b) en term_sum.
ST_ACCUMULATE calcula add_mod(r, term_sum) y avanza el indice como antes.
La salida solo se publica tras acumular tambien el ultimo coeficiente.
Esto agrega n ciclos por operacion (10,24 us para n=1024 a 100 MHz) y evita
encadenar dos sumas modulares entre registros.


La validacion se divide ahora en dos etapas: input_range_errors registra las
cuatro comparaciones por separado (cero durante ciclos no aceptados), y
input_invalid acumula esos bits en el ciclo siguiente. ST_DRAIN_LOAD espera
la segunda etapa tras aceptar la ultima palabra; ST_CHECK_LOAD consulta luego
el error acumulado. Se agrega un ciclo al final de la carga respecto a la
validacion registrada de una sola etapa. No cambia el caudal de entrada.
Reset y un nuevo start vacian ambos registros para impedir errores residuales.
