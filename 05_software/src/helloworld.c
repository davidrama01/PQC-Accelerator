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

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "hawk_acc.h"
#include "xil_cache.h"
#include "xaxidma.h"
#include "xparameters.h"
#include "stdlib.h"
#include "xscutimer.h"

#define MAX_BURST 256
#define DMA_ID XPAR_AXI_DMA_0_DEVICE_ID
#define AXI_LITE_ADDR XPAR_HAWK_ACC_0_S00_AXI_BASEADDR
#define REG0_OFFSET HAWK_ACC_S00_AXI_SLV_REG0_OFFSET
#define REG1_OFFSET HAWK_ACC_S00_AXI_SLV_REG1_OFFSET

#define NUM_WORDS       16
#define NUM_BYTES       (NUM_WORDS * sizeof(u32))

static XAxiDma AxiDma;

u32 tx_buffer[NUM_WORDS] __attribute__((aligned(64)));

XStatus status;

int main()
{
    init_platform();

    int status;

	xil_printf("DMA TX test\r\n");

	XAxiDma_Config *cfg = XAxiDma_LookupConfig(DMA_ID);
	if (!cfg) {
		xil_printf("DMA config not found\r\n");
		return XST_FAILURE;
	}

	status = XAxiDma_CfgInitialize(&AxiDma, cfg);
	if (status != XST_SUCCESS) {
		xil_printf("DMA init failed\r\n");
		return XST_FAILURE;
	}

	if (XAxiDma_HasSg(&AxiDma)) {
		xil_printf("DMA is in Scatter-Gather mode\r\n");
		return XST_FAILURE;
	}

	// Generar X datos de 32 bits
	for (int i = 0; i < NUM_WORDS; i++) {
		tx_buffer[i] = 0xA0000000 + i;
	}

	// Importante si la caché está activada
	Xil_DCacheFlushRange((UINTPTR)tx_buffer, NUM_BYTES);

    // Se activa la transferencias de datos de entrada
    HAWK_ACC_mWriteReg(AXI_LITE_ADDR, REG0_OFFSET, 1);

    // Enviar datos: DDR -> DMA -> AXI Stream -> PL
	status = XAxiDma_SimpleTransfer(
		&AxiDma,
		(UINTPTR)tx_buffer,
		NUM_BYTES,
		XAXIDMA_DMA_TO_DEVICE
	);

	if (status != XST_SUCCESS) {
		xil_printf("DMA TX transfer failed\r\n");
		return XST_FAILURE;
	}

	while (XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE));

	xil_printf("DMA TX transfer completed\r\n");

	//while(HAWK_ACC_mReadReg(XPAR_HAWK_ACC_0_S00_AXI_BASEADDR, HAWK_ACC_S00_AXI_SLV_REG1_OFFSET) != 1){}; //Se espera a que termine la suma (Done = 1)

	return XST_SUCCESS;

    print("Hello World\n\r");
    print("Successfully ran Hello World application\n");

    cleanup_platform();
    return 0;
}
