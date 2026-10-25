# Casos negativos de la aplicacion de placa

`05_software/src/helloworld.c` y su copia en el proyecto Vitis ejecutan 13
comprobaciones para cada variante 256, 512 y 1024, reutilizando la misma
clave y firma originales:

| Caso | Resultado esperado |
|---|---|
| Firma original | hawk_verify = 1 |
| Mensaje alterado | hawk_verify = 0 |
| Un bit del salt alterado | hawk_verify = 0 |
| Campo s1 con codificacion invalida | Rechazo PS, hawk_verify = 0 |
| Firma truncada | Rechazo PS, hawk_verify = 0 |
| Clave publica con codificacion invalida | Rechazo PS, hawk_verify = 0 |
| Clave publica truncada | Rechazo PS, hawk_verify = 0 |
| Impulso PL valido | status = 0, verify_error = 0 |
| Primer coeficiente w1 negativo | status = 0, verify_error = 1 |
| q00[0] negativo | status = 0, verify_error = 1 |
| Norma 65536, superior a todos los umbrales | status = 0, verify_error = 1 |
| Impulso PL valido despues de los rechazos | status = 0, verify_error = 0 |
| Firma original despues de todos los errores | hawk_verify = 1 |

Los vectores directos PL usan h0=0, q01=0, q00=1 y un unico coeficiente
de w1, salvo la mutacion indicada. La norma excesiva usa w1[0]=256, por lo
que r1=r2=n*65536 y la norma tras dividir por n es 65536. Los vectores
directos prueban el verificador polinomico; no son claves/firma HAWK codificadas.

`PASS` en un caso negativo significa que se ha obtenido el rechazo esperado.
Los errores de transporte, inicializacion o timeout cuentan como FAIL;
no se aceptan como prueba de rechazo criptografico. No se fuerzan timeouts
en la placa. Los tests del driver cubren esos fallos mediante mocks.

```powershell
python 06_test/run_helloworld.py
```

La prueba ejecuta el programa real con un backend matematico y comprueba
los 13 resultados por variante. El log queda en `.work/helloworld/test.log`.
Para ejecutarlo en la PYNQ-Z2 hay que recompilar la aplicacion de Vitis.
No hay cambios RTL ni se requiere otro bitstream para estos nuevos casos.
