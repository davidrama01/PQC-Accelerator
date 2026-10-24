/******************************************************************************
*
* Copyright (C) 2009 - 2014 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* Use of the Software is limited solely to applications:
* (a) running on a Xilinx device, or
* (b) that interact with a Xilinx device through a bus or interconnect.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
* OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* Except as contained in this notice, the name of the Xilinx shall not be used
* in advertising or otherwise to promote the sale, use or other dealings in
* this Software without prior written authorization from Xilinx.
*
******************************************************************************/

/*
 * helloworld.c: simple test application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable only in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include <stdint.h>
#include "platform.h"
#include "xil_printf.h"
#include "hawk_params.h"
#include "keygen.h"
#include "hawk_sign.h"
#include "hawk_verify.h"

/* Imprime sin reservar otro buffer del doble de tamano en la pila. */
static void print_bytes(const char *name, const uint8_t *bytes, size_t length)
{
    xil_printf("%s = 0x", name);
    for (size_t i = 0U; i < length; i++) {
        xil_printf("%02x", (unsigned int)bytes[i]);
    }
    xil_printf("\r\n");
}

static int run_case(uint32_t n)
{
    /* Seleccionar antes de dimensionar buffers o llamar a cualquier algoritmo. */
    if (hawk_select_params(n) != 0) {
        xil_printf("Unsupported n: %lu\r\n", (unsigned long)n);
        return -1;
    }
    uint8_t pub[HAWK_PUB_BYTES];
    uint8_t priv[HAWK_PRIV_BYTES];
    uint8_t sig[HAWK_SIG_BYTES];
    static const uint8_t message[] = "Hola HAWK";

    xil_printf("\r\n=== %s: n=%lu ===\r\n", HAWK_NAME, (unsigned long)HAWK_N);
    keygen(pub, priv);
    print_bytes("public_key", pub, sizeof pub);
    print_bytes("private_key", priv, sizeof priv);
    xil_printf("Key generation completed\r\n");

    int result = hawk_sign(sig, priv, message, sizeof message - 1U);
    if (result != 0) {
        xil_printf("Signing execution error: %d\r\n", result);
        return -1;
    }
    print_bytes("signature", sig, sizeof sig);
    xil_printf("Signing completed\r\n");

    result = hawk_verify(sig, sizeof sig, pub, sizeof pub,
                         message, sizeof message - 1U);
    if (result == 1) {
        xil_printf("Signature verified successfully\r\n");
        return 0;
    }
    if (result == 0) {
        xil_printf("Signature verification failed\r\n");
    } else {
        xil_printf("Verification execution error: %d\r\n", result);
    }
    return -1;
}

int main(void)
{
    static const uint32_t sizes[] = {256U, 512U, 1024U};
    unsigned failures = 0U;
    init_platform();
    for (size_t i = 0U; i < sizeof sizes / sizeof sizes[0]; i++) {
        int result = run_case(sizes[i]);
        xil_printf("HAWK-%lu: %s\r\n", (unsigned long)sizes[i],
                   result == 0 ? "PASS" : "FAIL");
        failures += result != 0;
    }
    xil_printf("Completed: %u/3 cases passed\r\n", 3U - failures);
    cleanup_platform();
    return failures == 0U ? 0 : 1;
}
