#include <stddef.h>
#include <string.h>

#include "hawk_fpga.h"
#include "hawk_acc.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"

#define HAWK_FPGA_DMA_ID        XPAR_AXI_DMA_0_DEVICE_ID
#define HAWK_FPGA_AXI_ADDR      XPAR_HAWK_ACC_0_S00_AXI_BASEADDR
#define HAWK_FPGA_START_OFFSET  HAWK_ACC_S00_AXI_SLV_REG0_OFFSET

#define HAWK_FPGA_INPUT_WORDS   (4U * HAWK_N_WORDS32 + 2U * HAWK_N)
#define HAWK_FPGA_OUTPUT_WORDS  (2U * HAWK_N_WORDS32)
#define HAWK_FPGA_DMA_TIMEOUT   100000000U

static XAxiDma hawk_dma;

static int32_t hawk_tx_buffer[HAWK_FPGA_INPUT_WORDS]
    __attribute__((aligned(64)));
static uint32_t hawk_rx_buffer[HAWK_FPGA_OUTPUT_WORDS]
    __attribute__((aligned(64)));

static int WaitForDma(unsigned direction)
{
    uint32_t timeout = HAWK_FPGA_DMA_TIMEOUT;

    while (XAxiDma_Busy(&hawk_dma, direction)) {
        if (--timeout == 0U) {
            return -1;
        }
    }
    return 0;
}

static void PrintPolynomialMod2(const char *name,
                                const uint32_t value[HAWK_N_WORDS32])
{
    xil_printf("%s = 0x", name);
    for (size_t i = HAWK_N_WORDS32; i > 0U; i--) {
        xil_printf("%08lx", (unsigned long)value[i - 1U]);
    }
    xil_printf("\r\n");
}

static uint32_t GetPackedBit(const uint32_t value[HAWK_N_WORDS32],
                             size_t index)
{
    return (value[index / 32U] >> (index % 32U)) & 1U;
}

/*
 * Convolución cíclica en F2[X]/(X^n + 1). En característica 2,
 * X^n + 1 y X^n - 1 producen el mismo plegado de coeficientes.
 */
static void PolyMulMod2Packed(const uint32_t a[HAWK_N_WORDS32],
                              const uint32_t b[HAWK_N_WORDS32],
                              uint32_t result[HAWK_N_WORDS32])
{
    memset(result, 0, HAWK_N_WORDS32 * sizeof(uint32_t));

    for (size_t i = 0U; i < HAWK_N; i++) {
        uint32_t acc = 0U;

        for (size_t j = 0U; j < HAWK_N; j++) {
            size_t b_index = (i + HAWK_N - j) % HAWK_N;
            acc ^= GetPackedBit(a, j) & GetPackedBit(b, b_index);
        }
        result[i / 32U] |= acc << (i % 32U);
    }
}

static void PackCoefficientParity(const int32_t input[HAWK_N],
                                  uint32_t output[HAWK_N_WORDS32])
{
    memset(output, 0, HAWK_N_WORDS32 * sizeof(uint32_t));

    for (size_t i = 0U; i < HAWK_N; i++) {
        output[i / 32U] |= ((uint32_t)input[i] & 1U) << (i % 32U);
    }
}

static void CalculateTReference(
    const uint32_t h0[HAWK_N_WORDS32],
    const uint32_t h1[HAWK_N_WORDS32],
    const uint32_t F_mod2[HAWK_N_WORDS32],
    const uint32_t G_mod2[HAWK_N_WORDS32],
    const int32_t f[HAWK_N],
    const int32_t g[HAWK_N],
    uint32_t t0[HAWK_N_WORDS32],
    uint32_t t1[HAWK_N_WORDS32])
{
    uint32_t f_mod2[HAWK_N_WORDS32];
    uint32_t g_mod2[HAWK_N_WORDS32];
    uint32_t product[HAWK_N_WORDS32];

    PackCoefficientParity(f, f_mod2);
    PackCoefficientParity(g, g_mod2);

    PolyMulMod2Packed(h0, f_mod2, t0);
    PolyMulMod2Packed(h1, F_mod2, product);
    for (size_t i = 0U; i < HAWK_N_WORDS32; i++) {
        t0[i] ^= product[i];
    }

    PolyMulMod2Packed(h0, g_mod2, t1);
    PolyMulMod2Packed(h1, G_mod2, product);
    for (size_t i = 0U; i < HAWK_N_WORDS32; i++) {
        t1[i] ^= product[i];
    }
}

static void VerifyT(const uint32_t received_t0[HAWK_N_WORDS32],
                    const uint32_t received_t1[HAWK_N_WORDS32],
                    const uint32_t expected_t0[HAWK_N_WORDS32],
                    const uint32_t expected_t1[HAWK_N_WORDS32])
{
    int t0_ok = memcmp(received_t0, expected_t0,
                       HAWK_N_WORDS32 * sizeof(uint32_t)) == 0;
    int t1_ok = memcmp(received_t1, expected_t1,
                       HAWK_N_WORDS32 * sizeof(uint32_t)) == 0;

    xil_printf("DMA verification: t0 %s, t1 %s\r\n",
               t0_ok ? "OK" : "FAIL",
               t1_ok ? "OK" : "FAIL");

    if (!t0_ok) {
        PrintPolynomialMod2("expected_t0", expected_t0);
    }
    if (!t1_ok) {
        PrintPolynomialMod2("expected_t1", expected_t1);
    }
}

static void BuildInputBuffer(const uint32_t h0[HAWK_N_WORDS32],
                             const uint32_t h1[HAWK_N_WORDS32],
                             const uint32_t F_mod2[HAWK_N_WORDS32],
                             const uint32_t G_mod2[HAWK_N_WORDS32],
                             const int32_t f[HAWK_N],
                             const int32_t g[HAWK_N])
{
    size_t offset = 0U;

    memcpy(hawk_tx_buffer + offset, h0, HAWK_N_WORDS32 * sizeof(uint32_t));
    offset += HAWK_N_WORDS32;
    memcpy(hawk_tx_buffer + offset, h1, HAWK_N_WORDS32 * sizeof(uint32_t));
    offset += HAWK_N_WORDS32;
    memcpy(hawk_tx_buffer + offset, F_mod2, HAWK_N_WORDS32 * sizeof(uint32_t));
    offset += HAWK_N_WORDS32;
    memcpy(hawk_tx_buffer + offset, G_mod2, HAWK_N_WORDS32 * sizeof(uint32_t));
    offset += HAWK_N_WORDS32;
    memcpy(hawk_tx_buffer + offset, f, HAWK_N * sizeof(int32_t));
    offset += HAWK_N;
    memcpy(hawk_tx_buffer + offset, g, HAWK_N * sizeof(int32_t));
}

int HawkFpgaInit(void)
{
    XAxiDma_Config *config;
    int status;

    config = XAxiDma_LookupConfig(HAWK_FPGA_DMA_ID);
    if (config == NULL) {
        return -1;
    }

    status = XAxiDma_CfgInitialize(&hawk_dma, config);
    if (status != XST_SUCCESS) {
        return -2;
    }
    return 0;
}

int HawkFpgaCalculateT(const uint32_t h0[HAWK_N_WORDS32],
                       const uint32_t h1[HAWK_N_WORDS32],
                       const uint32_t F_mod2[HAWK_N_WORDS32],
                       const uint32_t G_mod2[HAWK_N_WORDS32],
                       const int32_t f[HAWK_N],
                       const int32_t g[HAWK_N],
                       uint32_t t0[HAWK_N_WORDS32],
                       uint32_t t1[HAWK_N_WORDS32])
{
    int status;
    uint32_t expected_t0[HAWK_N_WORDS32];
    uint32_t expected_t1[HAWK_N_WORDS32];

    if (h0 == NULL || h1 == NULL || F_mod2 == NULL || G_mod2 == NULL ||
        f == NULL || g == NULL || t0 == NULL || t1 == NULL) {
        return -1;
    }
    status = HawkFpgaInit();
    if (status != 0) {
        return status;
    }

    if (XAxiDma_HasSg(&hawk_dma)) {
        return -3;
    }

    BuildInputBuffer(h0, h1, F_mod2, G_mod2, f, g);
    Xil_DCacheFlushRange((UINTPTR)hawk_tx_buffer, sizeof hawk_tx_buffer);
    Xil_DCacheInvalidateRange((UINTPTR)hawk_rx_buffer, sizeof hawk_rx_buffer);

    HAWK_ACC_mWriteReg(HAWK_FPGA_AXI_ADDR, HAWK_FPGA_START_OFFSET, 1U);

    /* Preparar primero MM2S para enviar las entradas a la FPGA. */
    status = XAxiDma_SimpleTransfer(&hawk_dma,
                                    (UINTPTR)hawk_tx_buffer,
                                    sizeof hawk_tx_buffer,
                                    XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        return -4;
    }

    /* Preparar S2MM antes de arrancar el cálculo y generar TVALID. */
    status = XAxiDma_SimpleTransfer(&hawk_dma,
                                    (UINTPTR)hawk_rx_buffer,
                                    sizeof hawk_rx_buffer,
                                    XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        return -5;
    }

    if (WaitForDma(XAXIDMA_DMA_TO_DEVICE) != 0) {
        return -6;
    }
    if (WaitForDma(XAXIDMA_DEVICE_TO_DMA) != 0) {
        return -7;
    }

    Xil_DCacheInvalidateRange((UINTPTR)hawk_rx_buffer, sizeof hawk_rx_buffer);
    memcpy(t0, hawk_rx_buffer, HAWK_N_WORDS32 * sizeof(uint32_t));
    memcpy(t1, hawk_rx_buffer + HAWK_N_WORDS32,
           HAWK_N_WORDS32 * sizeof(uint32_t));

    PrintPolynomialMod2("t0", t0);
    PrintPolynomialMod2("t1", t1);

    CalculateTReference(h0, h1, F_mod2, G_mod2, f, g,
                        expected_t0, expected_t1);
    VerifyT(t0, t1, expected_t0, expected_t1);

    return 0;
}
