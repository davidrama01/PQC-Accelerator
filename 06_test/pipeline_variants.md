# Comprobacion de variantes HAWK

Ejecutar desde la raiz del proyecto:

```powershell
python .\06_test\check_keygen_variants.py
python .\06_test\check_pipeline_variants.py
```

Los scripts compilan por separado HAWK-256, HAWK-512 y HAWK-1024 usando
copias de las cabeceras en `.work`. No modifican la seleccion del proyecto.
Requieren GCC; `--cc` permite indicar otro ejecutable.

Se ejecutan la generacion real de claves (incluido NTRU), la firma C y la
verificacion C. El segundo script sustituye las llamadas al acelerador por
un modelo matematico: productos negaciclicos, RebuildS0 segun el algoritmo
18 y PolyQnorm con los dos primos. No sustituye una simulacion del RTL ni
una prueba de DMA en placa. Rnd es determinista y solo sirve para pruebas.

Resultados del 24-10-2026:

| n | Generacion | Firmas verificadas | Mensajes alterados rechazados | Codificaciones alteradas rechazadas |
|---|---|---|---|---|
| 256 | Correcta | 3/3 | 3/3 | 3/3 |
| 512 | Correcta | 3/3 | 3/3 | 3/3 |
| 1024 | Correcta | 3/3 | 3/3 | 3/3 |

Se usa una clave por variante y mensajes de 0, 17 y 137 bytes. Ademas,
la norma obtenida durante la verificacion debe coincidir exactamente con
la suma de cuadrados del vector producido por el muestreador de firma.
Esto es una prueba funcional acotada, no una validacion criptografica
exhaustiva ni una comprobacion de la fuente de entropia.

## Bloqueos encontrados en el RTL actual

1. `03_design/rebuild_s0.vhd`, calculo final de z: implementa
   `floor(v/(2*c_q00))`, con `v=t+c_s0*h0`. La linea 28 del algoritmo 18
   requiere `floor((v+c_s0)/(2*c_s0))`. Falta el redondeo y el divisor
   usa la constante equivocada.
2. `03_design/hawk_pkg.vhd` mantiene fijos los limites altos y
   `c_sigma_verify=10469` en Q13 (aproximadamente 1.278). El software
   configura sigma_verify como 1.042, 1.425 y 1.571; los limites altos
   tambien cambian segun la variante. El umbral RTL de n=512 es 6689,
   mientras que el del software es 8317.

El modelo con la aritmetica final y las constantes actuales del RTL
rechaza las tres firmas validas en cada variante. Corrigiendo solamente
el redondeo, pero manteniendo las constantes RTL, rechaza 0/3, 2/3 y 3/3
respectivamente. Estos resultados son del modelo, no de XSim.
El script termina correctamente cuando las pruebas del modelo de la
especificacion pasan; las lineas RTL AUDIT describen fallos conocidos.

No se ha modificado el RTL en esta revision. Antes de dar por terminado
el acelerador, hay que corregir estos puntos y usar firmas generadas por
software como vectores para verificar el RTL completo.

Los registros de compilacion y ejecucion quedan en
`06_test/.work/keygen_variants/<n>/` y
`06_test/.work/pipeline_variants/<n>/`.
