# edge_fpu_misc

## Purpose

`edge_fpu_misc` owns the one-cycle FP32 sign-inject, min/max, compare, class,
and integer/FPR move operations. The scalar pipe owns GPR/FPR dependency
tracking, architectural writeback, producer publication, and retire.

Architectural FPR state is an unboxed FP32 payload. Arithmetic-format aliases
therefore operate on that FP32 value. External moves are the format boundary:

- `FMV.X.W` sign-extends FP32 bit 31 through XLEN-1 on RV64.
- `FMV.X.H` first rounds the internal FP32 value to IEEE FP16 using RNE (the
  legal move encoding has `funct3=000`), then sign-extends FP16 bit 15 through
  XLEN-1.
- `FMV.W.X` copies GPR bits 31:0 into the physical FP32 FPR.
- `FMV.H.X` promotes the IEEE FP16 payload in GPR bits 15:0 to physical FP32.

The issue/complete boundary is one cycle and carries sequence, epoch,
destination bank/domain, value, and exception flags. Redirect cancellation is
owned by the scalar pipe for this single-cycle unit.

## Operations

`op=0..5` select sign-inject, min/max, compare, class, FPR-to-GPR move, and
GPR-to-FPR move. `funct3` preserves the standard RISC-V sub-operation encoding.
Comparisons and min/max implement canonical NaN, signaling-NaN invalid flags,
and signed-zero ordering.

## Validation

`edge_fpu_misc_tb` checks all operation families, with directed NaN and signed
zero cases. Move checks include RV64 high-bit sign extension and FP32-to-FP16
rounding before `FMV.X.H` becomes externally visible. The scalar-pipe FPU test
also checks FPR and GPR writeback, producer publication, and original-sequence
retirement through the integrated misc boundary. Its manual mixed SoftFloat
flow randomly interleaves `FMV.X.H`/`FMV.H.X` with FLH/FSH and arithmetic,
checking FP16 subnormal, overflow, canonical-NaN, and RV64 sign-extension bits
in final GPR/FPR/memory state.
