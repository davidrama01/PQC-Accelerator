# Multiplicacion ciclica en GF(2)

El RTL poly_mul_mod2 separa el calculo del indice circular, la seleccion dentro
de bancos de 32 bits, la seleccion del banco y la acumulacion XOR en cuatro
etapas que trabajan simultaneamente. Una quinta etapa distribuye el coeficiente a registros locales por banco;
una sexta escribe cada coeficiente.
Se acepta un par de bits por ciclo, tambien entre coeficientes consecutivos.
Las marcas de fin de coeficiente y operacion avanzan junto a los datos. Una habilitacion de un
solo bit que avanza por registros sustituye la escritura con indice variable.
Cada destino de temp_result tiene una asignacion estatica.

Los operandos deben permanecer estables hasta done, como en el bloque original.
num_samples se captura con start. start reinicia una operacion en curso; rst_n
es asincrono y aborta el calculo. done dura un ciclo y el resultado se mantiene
hasta reset o un nuevo start. Los bits fuera de num_samples quedan a cero.

La latencia desde el flanco que acepta start hasta done es n*n+5 ciclos.
Para n=1024 a 100 MHz son unos 10,49 ms; revisar los timeouts del emisor.
El cierre de timing debe comprobarse tras sintesis e implementacion.

```powershell
python 04_testbench/tb_poly_mul_mod2/run_pipeline.py
```

La prueba compara contra convolucion circular calculada en Python, con tamanos
1, 2, 3, 7, 31, 32, 33, 256, 512 y 1024; comprueba envoltura, ceros, bits altos inactivos,
cambio de dimension sin reset, reset activo, reinicio y pulso/latencia de done.
No depende de modelos de memoria ni IP de Xilinx. El CSV y el testbench antiguo
se conservan como prueba interactiva adicional.

La prueba comprueba tambien calculate_t para las dimensiones de produccion,
con dos multiplicadores concurrentes y su combinacion XOR. Se mantienen los
registros entre selectores: aumentar el caudal no concatena las etapas, pero
el retardo fisico final debe medirse de nuevo en Vivado.


Los registros bank_coefficient tienen DONT_TOUCH aplicado exclusivamente a
ese vector de 32 bits para impedir fusionar sus drivers locales. No son
atributos de debug. Cada banco recibe una habilitacion distinta y conserva
su coeficiente hasta la siguiente escritura de ese banco. bank_token y
bank_valid retrasan la seleccion un ciclo; done coincide con la escritura
final, y start/reset invalidan todas las escrituras pendientes.
