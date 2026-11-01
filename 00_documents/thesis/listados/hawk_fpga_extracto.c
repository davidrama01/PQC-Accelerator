/* Extracto documental no compilable de hawk_fpga.c.
   Ruta de verificacion: se resumen validaciones y empaquetado.
   Se omiten las rutas de firma, la inicializacion y los diagnosticos. */
int HawkFpgaVerify(const uint32_t h0[HAWK_N_WORDS32],
                   const int32_t q00[HAWK_N],
                   const int32_t q01[HAWK_N],
                   const int32_t w1[HAWK_N], uint32_t *error)
{
    uint32_t timeout = HAWK_FPGA_VERIFY_TIMEOUT;
    /* Validar error antes de escribirlo, luego h0, q00, q01 y w1.
       Las validaciones fallidas devuelven VerifyTransportError(-1,...). */
    *error = 1U;
    if (HawkFpgaInit() != 0 || XAxiDma_HasSg(&hawk_dma))
        return VerifyTransportError(-2, "DMA configuration");
    /* memcpy: hawk_verify_tx_buffer = h0 || q00 || q01 || w1. */
    Xil_DCacheFlushRange((UINTPTR)hawk_verify_tx_buffer,
        HAWK_FPGA_VERIFY_WORDS * sizeof(hawk_verify_tx_buffer[0]));
    HAWK_ACC_mWriteReg(HAWK_FPGA_AXI_ADDR,
                       HAWK_FPGA_MODE_OFFSET, 1U);
    HAWK_ACC_mWriteReg(HAWK_FPGA_AXI_ADDR,
                       HAWK_FPGA_SIZE_OFFSET, HAWK_N);
    HAWK_ACC_mWriteReg(HAWK_FPGA_AXI_ADDR,
                       HAWK_FPGA_START_OFFSET, 1U);
    if (XAxiDma_SimpleTransfer(&hawk_dma,
            (UINTPTR)hawk_verify_tx_buffer,
            HAWK_FPGA_VERIFY_WORDS * sizeof(hawk_verify_tx_buffer[0]),
            XAXIDMA_DMA_TO_DEVICE) != XST_SUCCESS)
        return VerifyTransportError(-4, "MM2S transfer");
    if (WaitForDma(XAXIDMA_DMA_TO_DEVICE) != 0)
        return VerifyTransportError(-5, "DMA error or timeout");
    while (timeout-- != 0U) {
        const uint32_t status = HAWK_ACC_mReadReg(
            HAWK_FPGA_AXI_ADDR, HAWK_FPGA_VERIFY_OFFSET);
        if ((status & HAWK_FPGA_VERIFY_DONE) != 0U) {
            *error = status & HAWK_FPGA_VERIFY_ERROR;
            return 0;
        }
    }
    return VerifyTransportError(-6, "FPGA result timeout");
}
