/* Host tests only. Never add this directory to a Vitis application. */
#ifndef MOCK_XAXIDMA_H
#define MOCK_XAXIDMA_H
#include <stdint.h>
#include <stddef.h>
typedef uintptr_t UINTPTR;
typedef struct { unsigned unused; } XAxiDma;
typedef struct { unsigned unused; } XAxiDma_Config;
#define XST_SUCCESS 0
#define XAXIDMA_DMA_TO_DEVICE 0U
#define XAXIDMA_DEVICE_TO_DMA 1U
#define XAXIDMA_IRQ_ERROR_MASK 0x4000U
XAxiDma_Config *XAxiDma_LookupConfig(unsigned id);
int XAxiDma_CfgInitialize(XAxiDma *dma, XAxiDma_Config *config);
int XAxiDma_HasSg(XAxiDma *dma);
int XAxiDma_Busy(XAxiDma *dma, unsigned direction);
int XAxiDma_SimpleTransfer(XAxiDma *dma, UINTPTR address, unsigned length,
                          unsigned direction);
uint32_t XAxiDma_IntrGetIrq(XAxiDma *dma, unsigned direction);
#endif
