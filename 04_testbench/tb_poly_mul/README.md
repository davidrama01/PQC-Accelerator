# Signed negacyclic polynomial product pipeline

poly_mul uses the two-cycle synchronous read interface of blk_mem_gen_0,
including its registered primitive output. Memory indices and
valid are delayed together. Three registered arithmetic stages compute the
full product, its negacyclic sign, then the accumulator. The last-term flag
travels with the product; the next coefficient starts only after the pipe drains.
The result width, signed resize semantics, per-coefficient done pulse, start
restart priority and asynchronous reset are unchanged. Inputs/num_samples must
remain valid for the operation, as with the original block.

A new coefficient completes every n+4 cycles. Throughput within a coefficient
is still one product per cycle. For n=1024 at 100 MHz the arithmetic schedule
takes 1024*1028 cycles, about 10.527 ms. The read alignment adds one cycle per
coefficient (10.24 us at n=1024) to the previous pipeline. Timing closure still
requires implementation.

```powershell
python 04_testbench/tb_poly_mul/run_pipeline.py
```

The regression compares independent Python negacyclic convolution against RTL
using two-cycle synchronous memory models. It covers 16/32-bit operands, n=256/512/1024,
negative products, wrap sign, signed extreme operands, reset, restart while
products are in flight, dimension changes between operations and calculate_w1
with two concurrent multipliers. It checks every coefficient and detects missing
or extra done pulses. No Xilinx memory IP is needed for this functional test.

The real-IP checks are `06_test/audit_sign_memory.py --n 256` (also 512 and
1024) and `06_test/check_sign_integration.py`. They cover calculate_s1 and
the complete HawkSign stream with the generated Xilinx signing RAM.
