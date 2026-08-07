# edge_scalar_fast_alu.v

## Purpose

Combinational fast integer ALU datapath for the Edge scalar pipe. This block is
instantiated by `edge_scalar_alu` so synthesis reports can separate ordinary
single-cycle integer logic from branch/jump and RV64M multiply/divide logic.

## Ownership

`edge_scalar_fast_alu` owns:

- RV64I arithmetic, logical, shift, and compare result calculation
- RV64I word arithmetic and word sign-extension
- `lui` and `auipc` result calculation
- `jal` and `jalr` link-value calculation
- RV64 Zba and Zba.UW address-generation arithmetic

It does not own branch taken/target calculation, RV64M multiply/divide/remainder
calculation, issue readiness, completion registers, WBT, retire, or redirect.

## Shift Datapath

Variable scalar shifts are implemented as explicit two-stage combinational
shifters instead of unconstrained Verilog variable shifts. The first stage
selects a coarse multiple-of-8 shift (`k[5:3]` for XLEN and `k[4:3]` for word
ops). The second stage selects the remaining 0..7 bit shift (`k[2:0]`). Logical
right shifts fill with zero, arithmetic right shifts fill each stage with the
sign bit, and left shifts fill with zero.

This keeps the synthesized shape bounded to two 8-way mux layers for RV64 shifts
and avoids tool-dependent expansion of 64 independent `shiftx` cases.

## Interface

The block is purely combinational. Inputs are decoded local ALU op metadata,
source values, immediate values, function bits, and shift amounts. The only
output is `fast_result`.

The local operation values are owned by `edge_scalar_alu`; they are not ISA
encodings.

## Tests

Covered through:

```text
src/test-e3/edge_scalar_alu/edge_scalar_alu_rv64i_tb.v
src/test-e3/edge_scalar_pipe/edge_scalar_pipe_rv64i_alu_control_tb.v
```
