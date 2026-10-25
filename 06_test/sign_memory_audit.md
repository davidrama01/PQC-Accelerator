# Diagnostico de la firma: latencia de BRAM

La IP `blk_mem_gen_0` tiene `Register_PortA_Output_of_Memory_Primitives=true`:
su lectura tiene dos ciclos de latencia. `poly_mul` etiqueta los datos como
si la lectura tuviera un ciclo. `calculate_s1` tampoco espera lo suficiente
tras cambiar la direccion al siguiente coeficiente.

Se ha comprobado con el modelo de simulacion de la IP real generado por
Vivado, sin sustituir la RAM por un modelo propio. La prueba inicializa tres
RAM y ejecuta en paralelo:

- Un producto negaciclico de 256 coeficientes, comparado coeficiente a
  coeficiente con una convolucion directa Python (semilla 20261025).
- `calculate_s1` con h1=0, sym_break=1 y w1[i]=2*i; se espera s1[i]=-i.

Con las fuentes originales:

```text
S1 mismatch index=1 expected=-1 actual=0
S1 mismatch index=2 expected=-2 actual=-1
POLY mismatch index=1 expected=42 actual=54
POLY mismatch index=2 expected=-116 actual=-96
AUDIT COMPLETE poly_errors=233 s1_errors=255
```

Repitiendo la misma prueba con un ciclo adicional de alineacion de datos
y etiquetas en poly_mul, y un estado de espera adicional en calculate_s1:

```text
AUDIT COMPLETE poly_errors=0 s1_errors=0
```

La prueba inicial aplico esos ajustes SOLO a copias dentro de
`.work/sign_memory/aligned`. Posteriormente se han implementado en
`03_design/poly_mul.vhd`, `03_design/calculate_s1.vhd` y las dos copias de
la IP empaquetada en `02_project/ip_repo/hawk_acc_1.0/src`.

```powershell
python 06_test/audit_sign_memory.py --n 256
python 06_test/audit_sign_memory.py --n 512
python 06_test/audit_sign_memory.py --n 1024
python 06_test/check_sign_integration.py
```

Los logs iniciales estan en `.work/sign_memory/xsim.log`. La prueba de
control historica esta en `.work/sign_memory/aligned/xsim.log`.
Las regresiones actuales usan las fuentes de produccion y guardan logs en
`.work/sign_memory/current_256` (tambien 512 y 1024). Han pasado ambas ramas
de signo, h1 alternante, reset durante calculo, operaciones consecutivas,
estabilidad bajo backpressure, conteo de resultados y bandera final.

Esto confirma dos errores anteriores a la verificacion, capaces de alterar
la firma. No reconstruye los x0/x1 exactos de la firma del log UART, porque
esos datos no se imprimieron; tampoco prueba el DMA de la placa.

La regresion anterior `04_testbench/tb_poly_mul/run_pipeline.py` usaba una
memoria de un ciclo: por eso pasaba aunque no representaba la configuracion
real de la BRAM usada por HawkSign. Ahora modela dos ciclos; pasa para
16/32 bits, 256/512/1024, vuelta a 256 sin reset, operandos extremos,
reinicio con productos en vuelo y la composicion calculate_w1.

## Integracion completa tras la correccion

La prueba `check_sign_integration.py` encontro ademas que `cnt_t` en
`hawk_sign.vhd` avanzaba tambien durante las transferencias de s1. Al cambiar
de 256 a 512 sin reset, la siguiente salida empezaba por t1[0] en lugar de
t0[0]. Se ha limitado el incremento a `current_state = READ_T` y actualizado
la IP empaquetada y la copia generada actual `ipshared/118f/src`.

Con las tres correcciones pasa HawkSign completo con la BRAM real para la
secuencia 256, 512, 1024, 256 sin reset entre operaciones. Se comparan todas
las palabras de t0/t1 y todos los coeficientes de s1 con convolucion directa,
ambas ramas de simetria, estabilidad bajo backpressure y TLAST exacto.
Resultado: `PASS: complete signing integration` en
`06_test/.work/sign_integration/xsim.log`.

Estas pruebas no sustituyen la implementacion de timing ni la comprobacion
de DMA en placa. Para usar el cambio hay que regenerar/recompilar la IP y
el bitstream; un checkpoint de sintesis anterior conserva el RTL antiguo.
