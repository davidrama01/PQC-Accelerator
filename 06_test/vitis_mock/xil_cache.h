#ifndef MOCK_XIL_CACHE_H
#define MOCK_XIL_CACHE_H
#include "xaxidma.h"
void Xil_DCacheFlushRange(UINTPTR address, unsigned length);
void Xil_DCacheInvalidateRange(UINTPTR address, unsigned length);
#endif
