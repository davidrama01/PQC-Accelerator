#ifndef MOCK_HAWK_ACC_H
#define MOCK_HAWK_ACC_H
#include <stdint.h>
#define HAWK_ACC_S00_AXI_SLV_REG0_OFFSET 0U
void mock_write_reg(uintptr_t address, uint32_t offset, uint32_t value);
uint32_t mock_read_reg(uintptr_t address, uint32_t offset);
#define HAWK_ACC_mWriteReg mock_write_reg
#define HAWK_ACC_mReadReg mock_read_reg
#endif
