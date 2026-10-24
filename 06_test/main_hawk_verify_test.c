#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "hawk_verify.h"
#include "hawk_fpga.h"
#include "xaxidma.h"
#include "xparameters.h"
#include "verify_vectors.h"

enum fault_t { NONE, LOOKUP, INITIALIZE, SCATTER_GATHER, BUSY_TX, BUSY_RX,
               SUBMIT, DMA_ERROR, DMA_TIMEOUT, RESULT_TIMEOUT };
static enum fault_t fault;
static unsigned tx_count, rx_count, status_reads, start_count, busy_reads;
static uint32_t mode, size_reg, result_error;
static UINTPTR flushed_address;
static unsigned flushed_length;
static int submitted, signing;
static const uint32_t *expected_packet;

static void reset_mock(enum fault_t value)
{
    fault = value;
    tx_count = rx_count = status_reads = start_count = busy_reads = 0U;
    mode = 0U;
    size_reg = 0U;
    result_error = 0U;
    flushed_address = 0U;
    flushed_length = 0U;
    submitted = signing = 0;
    expected_packet = expected_packets[0];
}

XAxiDma_Config *XAxiDma_LookupConfig(unsigned id)
{
    static XAxiDma_Config config;
    assert(id == XPAR_AXI_DMA_0_DEVICE_ID);
    return fault == LOOKUP ? NULL : &config;
}

int XAxiDma_CfgInitialize(XAxiDma *dma, XAxiDma_Config *config)
{
    assert(dma != NULL && config != NULL);
    return fault == INITIALIZE ? -1 : XST_SUCCESS;
}

int XAxiDma_HasSg(XAxiDma *dma)
{
    (void)dma;
    return fault == SCATTER_GATHER;
}

int XAxiDma_Busy(XAxiDma *dma, unsigned direction)
{
    (void)dma;
    if ((fault == BUSY_TX && direction == XAXIDMA_DMA_TO_DEVICE) ||
        (fault == BUSY_RX && direction == XAXIDMA_DEVICE_TO_DMA)) {
        return 1;
    }
    if (submitted && direction == XAXIDMA_DMA_TO_DEVICE) {
        if (fault == DMA_TIMEOUT) {
            return 1;
        }
        return busy_reads++ < 2U;
    }
    return 0;
}

uint32_t XAxiDma_IntrGetIrq(XAxiDma *dma, unsigned direction)
{
    (void)dma;
    (void)direction;
    return submitted && fault == DMA_ERROR ? XAXIDMA_IRQ_ERROR_MASK : 0U;
}

int XAxiDma_SimpleTransfer(XAxiDma *dma, UINTPTR address, unsigned length,
                           unsigned direction)
{
    (void)dma;
    assert(size_reg == HAWK_N && start_count == 1U);
    assert((address & 63U) == 0U);
    if (direction == XAXIDMA_DEVICE_TO_DMA) {
        assert(signing && mode == 0U);
        assert(length == 2U * HAWK_N_WORDS32 * sizeof(uint32_t));
        memset((void *)address, 0, length);
        rx_count++;
        return XST_SUCCESS;
    }
    assert(address == flushed_address && length == flushed_length);
    if (signing) {
        const uint32_t *words = (const uint32_t *)address;
        assert(mode == 0U);
        assert(length == (4U * HAWK_N_WORDS32 + 2U * HAWK_N) * 4U);
        for (size_t i = 0U; i < length / 4U; i++) {
            assert(words[i] == 0U);
        }
    } else {
        assert(mode == 1U);
        assert(length == sizeof expected_packets[0]);
        /* Includes h0 from hashlib SHAKE256, signed q00/q01 and every w1. */
        assert(memcmp((const void *)address, expected_packet, length) == 0);
    }
    tx_count++;
    submitted = 1;
    return fault == SUBMIT ? -1 : XST_SUCCESS;
}

void Xil_DCacheFlushRange(UINTPTR address, unsigned length)
{
    flushed_address = address;
    flushed_length = length;
}

void Xil_DCacheInvalidateRange(UINTPTR address, unsigned length)
{
    (void)address;
    (void)length;
}

int xil_printf(const char *format, ...)
{
    (void)format;
    return 0;
}

void mock_write_reg(uintptr_t address, uint32_t offset, uint32_t value)
{
    assert(address == XPAR_HAWK_ACC_0_S00_AXI_BASEADDR);
    if (offset == 0x10U) {
        assert(start_count == 0U);
        mode = value;
    } else if (offset == 0x14U) {
        assert(start_count == 0U);
        size_reg = value;
    } else {
        assert(offset == 0U && value == 1U && size_reg == HAWK_N);
        assert(mode == (signing ? 0U : 1U));
        start_count++;
        status_reads = 0U; /* RTL start clears the old result. */
    }
}

uint32_t mock_read_reg(uintptr_t address, uint32_t offset)
{
    assert(address == XPAR_HAWK_ACC_0_S00_AXI_BASEADDR && offset == 0x0CU);
    assert(submitted && start_count == 1U && !signing);
    assert(rx_count == 0U);
    if (fault == RESULT_TIMEOUT || status_reads++ < 2U) {
        return 0U;
    }
    return 2U | result_error;
}

static int verify_case(unsigned index)
{
    return hawk_verify(signature, sizeof signature, public_key, sizeof public_key,
                        message_lengths[index] ? messages[index] : NULL,
                        message_lengths[index]);
}

int main(void)
{
#ifdef HAWK_TEST_N
    assert(hawk_select_params(HAWK_TEST_N) == 0);
#endif
    uint8_t bad_sig[HAWK_SIG_BYTES], bad_pub[HAWK_PUB_BYTES];
    const enum fault_t failures[] = {LOOKUP, INITIALIZE, SCATTER_GATHER,
        BUSY_TX, BUSY_RX, SUBMIT, DMA_ERROR, DMA_TIMEOUT, RESULT_TIMEOUT};
    uint32_t h0[HAWK_N_WORDS32], error;
    int32_t polynomial[HAWK_N];
    memset(h0, 0, sizeof h0);
    memset(polynomial, 0, sizeof polynomial);

    for (unsigned i = 0U; i < VERIFY_CASES; i++) {
        for (unsigned rejected = 0U; rejected <= 1U; rejected++) {
            reset_mock(NONE);
            expected_packet = expected_packets[i];
            result_error = rejected;
            assert(verify_case(i) == (rejected ? 0 : 1));
            assert(tx_count == 1U && rx_count == 0U && status_reads >= 3U);
        }
    }
    for (size_t i = 0U; i < sizeof failures / sizeof failures[0]; i++) {
        reset_mock(failures[i]);
        assert(verify_case(0U) == -3);
        assert(rx_count == 0U);
    }

    reset_mock(NONE);
    memcpy(bad_sig, signature, sizeof bad_sig);
    memcpy(bad_pub, public_key, sizeof bad_pub);
    bad_sig[sizeof bad_sig - 1U] |= 0x80U;
    bad_pub[sizeof bad_pub - 1U] |= 0x80U;
    assert(hawk_verify(bad_sig, sizeof bad_sig, public_key, sizeof public_key,
                       NULL, 0U) == 0);
    assert(hawk_verify(signature, sizeof signature, bad_pub, sizeof bad_pub,
                       NULL, 0U) == 0);
    assert(hawk_verify(signature, sizeof signature - 1U, public_key,
                       sizeof public_key, NULL, 0U) == 0);
    assert(hawk_verify(signature, sizeof signature, public_key,
                       sizeof public_key + 1U, NULL, 0U) == 0);
    assert(hawk_verify(NULL, sizeof signature, public_key, sizeof public_key,
                       NULL, 0U) == -1);
    assert(hawk_verify(signature, sizeof signature, NULL, sizeof public_key,
                       NULL, 0U) == -1);
    assert(hawk_verify(signature, sizeof signature, public_key, sizeof public_key,
                       NULL, 1U) == -1);
    assert(hawk_verify(signature, sizeof signature, public_key, sizeof public_key,
                       messages[1], SIZE_MAX) == -1);
    assert(tx_count == 0U && start_count == 0U);
    assert(HawkFpgaVerify(NULL, polynomial, polynomial, polynomial, &error) == -1);
    assert(error == 1U);
    assert(HawkFpgaVerify(h0, polynomial, polynomial, polynomial, NULL) == -1);

    /* Signature path must restore mode=0 after a verification operation. */
    reset_mock(NONE);
    mode = 1U;
    signing = 1;
    assert(HawkFpgaCalculateT(h0, h0, h0, h0, polynomial, polynomial, h0, h0) == 0);
    assert(mode == 0U && tx_count == 1U && rx_count == 1U);
    printf("PASS: hawk_verify %s, hashlib packets, AXI/DMA protocol and failures\n",
           HAWK_NAME);
    return 0;
}
