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
#define REG2_OFFSET HAWK_ACC_S00_AXI_SLV_REG2_OFFSET

#define WORDS_PER_512BIT 16
#define NUM_WORDS       (10 * WORDS_PER_512BIT + 512 + 512)
#define NUM_BYTES       (NUM_WORDS * sizeof(s32))

static XAxiDma AxiDma;

s32 tx_buffer[NUM_WORDS] __attribute__((aligned(64)));
s32 rx_buffer[NUM_WORDS] __attribute__((aligned(64)));

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

	// Cada valor de 512 bits se reparte en 16 palabras de 32 bits
	static const s32 h0_words[WORDS_PER_512BIT] = {0x10000001, 0x10000002, 0x10000003, 0x10000004,
		0x10000005, 0x10000006, 0x10000007, 0x10000008,
		0x10000009, 0x1000000A, 0x1000000B, 0x1000000C,
		0x1000000D, 0x1000000E, 0x1000000F, 0x10000010};
	static const s32 h1_words[WORDS_PER_512BIT] = {0x20000001, 0x20000002, 0x20000003, 0x20000004,
		0x20000005, 0x20000006, 0x20000007, 0x20000008,
		0x20000009, 0x2000000A, 0x2000000B, 0x2000000C,
		0x2000000D, 0x2000000E, 0x2000000F, 0x20000010};
	static const s32 fmod2_words[WORDS_PER_512BIT] = {0x30000001, 0x30000002, 0x30000003, 0x30000004,
		0x30000005, 0x30000006, 0x30000007, 0x30000008,
		0x30000009, 0x3000000A, 0x3000000B, 0x3000000C,
		0x3000000D, 0x3000000E, 0x3000000F, 0x30000010};
	static const s32 gmod2_words[WORDS_PER_512BIT] = {0x40000001, 0x40000002, 0x40000003, 0x40000004,
		0x40000005, 0x40000006, 0x40000007, 0x40000008,
		0x40000009, 0x4000000A, 0x4000000B, 0x4000000C,
		0x4000000D, 0x4000000E, 0x4000000F, 0x40000010};
	static s32 f_words[512];
	static s32 g_words[512];

	for (int i = 0; i < 512; i++) {
		f_words[i] = (i % 5) - 4;
		g_words[i] = 4 - (i % 5);
	}

	int word_index = 0;

	for (int i = 0; i < WORDS_PER_512BIT; i++) {
		tx_buffer[word_index++] = (s32)h0_words[i];
	}
	for (int i = 0; i < WORDS_PER_512BIT; i++) {
		tx_buffer[word_index++] = (s32)h1_words[i];
	}
	for (int i = 0; i < WORDS_PER_512BIT; i++) {
		tx_buffer[word_index++] = (s32)fmod2_words[i];
	}
	for (int i = 0; i < WORDS_PER_512BIT; i++) {
		tx_buffer[word_index++] = (s32)gmod2_words[i];
	}
	for (int i = 0; i < 512; i++) {
		tx_buffer[word_index++] = (s32)f_words[i];
	}
	for (int i = 0; i < 512; i++) {
		tx_buffer[word_index++] = (s32)g_words[i];
	}

	u32 bytes_to_transfer = (4 * WORDS_PER_512BIT + 512 + 512) * sizeof(s32);

	// Importante si la caché está activada
	Xil_DCacheFlushRange((UINTPTR)tx_buffer, NUM_BYTES);

    // Se activa la transferencias de datos de entrada
    HAWK_ACC_mWriteReg(AXI_LITE_ADDR, REG0_OFFSET, 1);

    // Enviar datos: DDR -> DMA -> AXI Stream -> PL
	status = XAxiDma_SimpleTransfer(
		&AxiDma,
		(UINTPTR)tx_buffer,
		bytes_to_transfer,
		XAXIDMA_DMA_TO_DEVICE
	);

	if (status != XST_SUCCESS) {
		xil_printf("DMA TX transfer failed\r\n");
		return XST_FAILURE;
	}

	while (XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE));

	xil_printf("DMA TX transfer completed\r\n");

	bytes_to_transfer = (2 * WORDS_PER_512BIT) * sizeof(s32);

	u32 start_mst = HAWK_ACC_mReadReg(AXI_LITE_ADDR, REG2_OFFSET);

	while(start_mst != 1) {
		start_mst = HAWK_ACC_mReadReg(AXI_LITE_ADDR, REG2_OFFSET);
	}

	// Enviar datos: DDR -> DMA -> AXI Stream -> PL
	status = XAxiDma_SimpleTransfer(
		&AxiDma,
		(UINTPTR)rx_buffer,
		bytes_to_transfer,
		XAXIDMA_DEVICE_TO_DMA
	);

	if (status != XST_SUCCESS) {
		xil_printf("DMA TX transfer failed\r\n");
		return XST_FAILURE;
	}

	while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA));

	return XST_SUCCESS;

    print("Hello World\n\r");
    print("Successfully ran Hello World application\n");

    cleanup_platform();
    return 0;
}
