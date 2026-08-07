# edge_fpu_fmac

## Purpose

`edge_fpu_fmac` is the Edge-owned source location for the FP32 FMAC arithmetic
slice of the floating-point unit. It is instantiated by `edge_scalar_pipe` for
the first scalar FPU integration slice.

The Edge FPR contract for this slice is not RISC-V NaN-boxing. Architectural
FPR values are 32-bit FP32 payloads. Arithmetic ignores the encoded
`.S/.D/.H` format and always returns the same FP32 result. The scalar pipe and `edge_fpu_fmac`
exchange 32-bit operands and completions directly, with no internal boxing or
64-bit arithmetic state. FP loads of smaller formats should promote to
FP32, and FP loads of larger formats should round to FP32 before writing the
FPR file. FP stores that target larger formats should expand/round from the
stored FP32 value.

The current scalar-pipe hookup sends FP32 FADD, FSUB, FMUL, FMADD, FMSUB,
FNMADD, and FNMSUB through one shared FMAC pipeline. Every operation uses the
same fixed stage count and completion latency, allowing the scalar single-issue
boundary to select any arithmetic mode on consecutive cycles. Every
FADD/FSUB/FMUL/FMADD-family encoding performs its arithmetic on the same
physical FP32 payload. Instruction `fmt[1:0]` neither selects an arithmetic
datapath nor applies a result-side cast. FPU load/store formatting is handled
at the shared LSU boundary, while `edge_fpu_slow` implements FP32 divide and
square root in a variable-latency single-outstanding slot. CSR-visible fflags
remain a later integration step. Maintained `edge_fpu_misc` and `edge_fpu_cvt` blocks
implement scalar sign injection, min/max, compare, class, integer/FPR moves,
and conversions at focused issue/complete boundaries. The scalar pipe uses
one shared fixed-latency arithmetic instance, pipelines metadata in the same
style as the integer fast ALU, and routes all results through a shared
completion queue to the appropriate GPR or FPR writeback domain.

Because Edge has one physical FP32 FPR payload, FCVT among D/S/H is an identity
FPR move. Integer FCVT performs real numeric conversion with all five static
rounding modes. External H moves remain a representation boundary: FMV.X.H
rounds physical FP32 to binary16 before sign-extending its 16-bit payload.
The scalar-pipe decode accepts immediate rounding encodings `000..100` for
FMAC and FCVT operations. Reserved `101/110` and dynamic `111` are illegal in
this slice; no `frm/FCSR` state is implied.

The fused FP32 add path keeps the exact 24x24 product in a 64-bit working
canvas, matching the information retained by SoftFloat's `shiftRightJam64`
model. Alignment is split across a register boundary: the smaller magnitude
first moves by a multiple of four bits, then a 0..3-bit fine shift completes
the alignment. Bits leave the canvas only through sticky/jam reduction. The
following add/subtract and normalize stage reduces the result to the fused
round/pack interface. This deliberately favors an easily proved bit-true
baseline over an early intermediate-width reduction.

Input capture, coarse alignment, fine alignment plus add/normalize, and
writeback form a four-cycle fixed-latency path. Valid, destination, rounding
mode, special-case state, and scalar sequence metadata cross the same stage
count. The datapath remains fully pipelined and accepts one arithmetic mode per
cycle.

## Source Files

```text
src/edge-e3/edge_fpu_fmac/edge_fpu_fmac.v
src/edge-e3/edge_fpu_fmac/rtl/edge_fpu_fmac_align_add.v
src/edge-e3/edge_fpu_fmac/rtl/edge_fpu_fmac_narrow_fmadd.v
src/edge-e3/edge_fpu_fmac/rtl/edge_fpu_fmac_fp32_unpack.v
src/edge-e3/edge_fpu_fmac/rtl/edge_fpu_fmac_fp32_round_pack.v
src/edge-e3/edge_fpu_fmac/rtl/edge_fpu_fmac_narrow_shift_sticky_2stage.v
src/edge-e3/edge_fpu_fmac/rtl/edge_fpu_fmac_fp32_fused_round_pack.v
```

## Validation

The scalar pipe has a focused `edge_scalar_pipe_fpu_fmac` hardware test that
verifies raw FP32 FPR read, cross-domain dependency wait, FMAC/misc/conversion
completion, GPR/FPR writeback, producer, retire behavior, external FMV rules,
integer rounding, and `.S/.D/.H` format aliasing. The ROM-backed
ROM cases for FADD, FSUB, FMUL, FMADD, FMSUB, FNMADD, and FNMSUB each generate
64 deterministic SoftFloat vectors, embed them in a freestanding program, and
check every result on the shared Edge SoC runner. The testbench independently
snoops each FMAC completion and compares both its result and `fflags` with the
same `.vec` file.

The shared fused datapath marks pure FMUL explicitly. Although FMUL is formed
internally as `product + +0`, an exact zero result keeps the XOR of the operand
signs as required for multiplication instead of taking the adder's exact-zero
sign rule.

Exact add/subtract cancellation selects `-0` only for round-down and `+0` for
the other supported static rounding modes. The 64-bit fused path also performs
subnormal right-shift-with-jam and rounding directly; it does not fall back to
the early 24+GRS product compression when cancellation drives the result below
the normal exponent range.
