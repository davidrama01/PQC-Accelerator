# Verificacion HAWK en Vitis

Implementacion del Algoritmo 20 con el calculo de polinomios en la FPGA.

## API

    #include "hawk_verify.h"

    int result = hawk_verify(sig, sig_len, pub, pub_len, message, message_len);

- 1: el acelerador acepta la firma.
- 0: clave/firma mal codificada o rechazo del acelerador.
- -1: punteros o longitud de mensaje incorrectos.
- -2: no se pudo reservar memoria temporal para el mensaje concatenado.
- -3: error de inicializacion, configuracion, DMA o timeout.

message puede ser NULL con longitud cero. Las longitudes de clave y firma
deben coincidir exactamente con la variante de hawk_params.h. La API no es
reentrante: usa el DMA y buffers estaticos compartidos del controlador.

hawk_verify.c usa DecodeSignature/DecodePublic y SHAKE256 para obtener:

    hpub = SHAKE256(pub)[0:HAWK_HPUB_BITS]
    M = SHAKE256(message || hpub)[0:512]
    (h0,h1) = SHAKE256(M || salt)[0:2*n]
    w1[i] = h1[i] - 2*s1[i]

h0 se empaqueta en palabras little-endian de 32 bits; q00/q01/w1 son
coeficientes int32_t, sin reducir modulo P1/P2. El RTL hace esa conversion.
El salt y h1 no se envian por separado a la FPGA.

## Controlador y registros

HawkFpgaVerify envia un unico paquete MM2S:

    h0 (n/32 palabras) || q00 (n) || q01 (n) || w1 (n)

Se hace flush de cache antes de la transferencia. No se configura S2MM para
verificacion. El driver escribe mode=1 y HAWK_N antes de start. La ruta de
firma vuelve a programar mode=0 y HAWK_N en HawkFpgaCalculateT.

| Offset | Uso |
|---|---|
| 0x00 | Escribir 1 para habilitar la entrada; captura la longitud y limpia el resultado anterior |
| 0x0C | Bit 1: resultado disponible. Bit 0: error (0 acepta, 1 rechaza) |
| 0x10 | Modo: 0 firma, 1 verificacion |
| 0x14 | Numero de muestras: 256, 512 o 1024 |

La espera de DMA comprueba tambien el bit de error, no solo Busy. Hay limites
de espera configurables mediante HAWK_FPGA_DMA_TIMEOUT y
HAWK_FPGA_VERIFY_TIMEOUT (iteraciones de polling, no microsegundos).
Un fallo de transporte requiere reiniciar DMA y acelerador antes de reintentar;
la API no intenta recuperar una operacion parcialmente recibida.

El polling del DMA usa la API oficial XAxiDma_IntrGetIrq y
XAXIDMA_IRQ_ERROR_MASK:
https://github.com/Xilinx/embeddedsw/blob/master/XilinxProcessorIPLib/drivers/axidma/src/xaxidma.h

## Integracion Vitis

Anadir hawk_verify.c al proyecto y hawk_verify.h a sus includes. Requiere los
fuentes existentes decode.c, shake256.c y hawk_fpga.c, el BSP de AXI DMA y el
driver generado hawk_acc.h. helloworld.c ya llama al verificador tras firmar.

Comprobar que los identificadores de hawk_fpga.c coinciden con xparameters.h:
XPAR_AXI_DMA_0_DEVICE_ID y XPAR_HAWK_ACC_0_S00_AXI_BASEADDR.
La implementacion existente usa el BSP clasico de Vitis y DMA en modo simple.
Los tres relojes AXI del acelerador deben ser comunes, como exige el RTL.

Configurar la pila para los polinomios y los buffers de decodificacion (para
n=1024, el verificador tiene unos 17 KB locales y DecodePublic unos 20 KB
adicionales durante su llamada; 64 KB es un punto de partida para esta ruta).
Otras funciones como keygen/firma tienen sus propios requisitos de pila.
El heap debe permitir message_len + HAWK_HPUB_BYTES bytes, mas la gestion del
asignador. La memoria temporal se libera antes de enviar el paquete.

La variante del software se elige al compilar hawk_params.h. Se programa ese
n en el registro; esta API no selecciona parametros C dinamicamente.

## Pruebas en PC

    python .\06_test\run_hawk_verify.py

Resultado obtenido el 2026-10-24: PASS para HAWK-256, HAWK-512 y HAWK-1024,
compilando C99 con -O2 -Wall -Wextra -Werror.

Se compilan los fuentes reales del verificador, driver, decodificador y SHAKE,
con perifericos Vitis simulados de 06_test/vitis_mock (solo para estas pruebas,
nunca anadir esa carpeta a los includes del proyecto Vitis).

- Clave y firma preparadas por un codificador Python independiente; SHAKE256
  de Python hashlib proporciona los valores esperados de h0 y cada w1.
- Mensaje vacio, mensaje binario de 265 bytes y mensaje de 1024 bytes.
- Comparacion de todas las palabras del paquete, longitud exacta, alineacion
  de 64 bytes, flush de cache y orden de escrituras AXI-Lite.
- Aceptacion/rechazo simulados, ausencia de recepcion DMA en verificacion,
  restauracion del modo firma tras verificar.
- Entradas malformadas y nulas sin arrancar DMA; fallos de inicializacion,
  DMA scatter/gather, canales ocupados, fallo de envio, IRQ de error y
  timeouts de DMA/resultado.

Estas pruebas validan la preparacion y el protocolo, no autentican las firmas
de prueba: el resultado del calculo FPGA se simula. No sustituyen las pruebas
de firmas reales en placa o contra una implementacion de referencia.

## Pendiente del conjunto

Los parametros C y RTL aun deben unificarse: hawk_pkg conserva las constantes
de coeficientes de la variante anterior y c_sigma_verify=10469/8192, mientras
hawk_params.h usa sus valores por variante (para 512: 1425/1000).
Por tanto no se garantiza aun que el umbral hardware acepte exactamente las
firmas admitidas por la especificacion. Este cambio no modifica el RTL ni su
configuracion de IP. Falta la compilacion con el BSP definitivo y la prueba
completa en PYNQ-Z2.
