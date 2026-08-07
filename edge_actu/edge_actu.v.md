# edge_actu

`edge_actu` is the Edge activation unit. It is currently a standalone module
with a module-local Verilator proof. It must stay independent until the
synthesizable datapath and local tests are stable; only then should it be wired
into `edge_core_top`, DTCM, or the instruction stream.

## Purpose

The module mirrors `tools/actu/activation_asic_model.py` at
the fused activation-ASIC boundary:

- software-visible mode select
- one input element lane and one output element lane
- no BF16 memory round between exp, reciprocal, and finalizer
- one accepted element per cycle when the stream is not backpressured
- final output rounded once to BF16 for the first product target

The standalone RTL now implements every visible mode with synthesizable logic.
`EXP_ONLY`, `RCP_ONLY`, `RSQRT_ONLY`, fused `SIGMOID`/`SILU`/`TANH`, and
`SOFTMAX_EXP` all use local synthesizable arithmetic. RCP and RSQRT share a
three-multiplier, one-Newton-iteration pipeline with mode-specific seed tables
and correction coefficients. No DPI arithmetic is linked into the active mode
test.

## Selected ACTU v1 Datapath

Area-first ACTU v1 uses the Python-selected candidate:

```text
exp:
  split 8+4 base-2 LUT
  z = x * log2(e)
  z = k + f
  f = f_hi[7:0] + f_lo[3:0]
  2^f ~= lut_hi[f_hi] * lut_lo[f_lo]
  keep the Q28 hi*lo product until FP32 pack
  exp(x) ~= 2^k * 2^f

shared reciprocal / reciprocal-square-root:
  normalize the mantissa into [1,2)
  select one of three 32-entry Q12 seed tables:
    reciprocal, rsqrt-even-exponent, rsqrt-odd-exponent
  use Q16 products through three registered multiplier stages
  reciprocal: y1 = y0 * (2 - n * y0)
  rsqrt:       y1 = y0 * (1.5 - 0.5 * n * y0 * y0)
  restore the exponent and pack the result as FP32
```

The quality-first fallback is the same exp path with a 3-hex-digit radix-16
reciprocal seed before the Newton-Raphson correction.

## Modes

```text
0 EXP_ONLY: exp(x)
1 RCP_ONLY: 1 / x, with x == 0 returning 0
2 SIGMOID:  e = exp(-abs(x)); y = x >= 0 ? 1/(1+e) : e/(1+e)
3 SILU:     y = x * sigmoid(x)
4 TANH:     e = exp(-2*abs(x)); y = sign(x) * (1-e)/(1+e)
5 SOFTMAX:  exp(x - softmax_max)
6 RSQRT_ONLY: 1 / sqrt(x + scalar), with x + scalar <= 0 returning 0
7 SOFTMAX_NORMALIZE: x * rcp(last SOFTMAX exp sum)
```

`SOFTMAX` writes BF16 `exp(x-max)` values while accumulating the BF22 internal
EXP values into a job-local FP32 sum. `SOFTMAX_NORMALIZE` reuses the most
recently completed sum and writes `x * rcp(sum)`, allowing a three-pass
short-context softmax without a separate memory reduction pass.

## Standalone Stream Interface

The standalone proof boundary is intentionally simple:

- `forever_cpuclk`, `cpurst_b`: clock and active-low reset.
- `in_valid`, `in_ready`: issue handshake.
- `in_mode[2:0]`: activation mode.
- `in_value[31:0]`: input FP32 bit pattern.
- `in_softmax_max[31:0]`: mode-specific scalar; max value for `SOFTMAX` /
  `SOFTMAX_EXP`, retained sum for `SOFTMAX_NORMALIZE`, and additive epsilon
  for `RSQRT_ONLY`.
- `out_valid`: asserted for each accepted input after the pipeline latency.
- `out_mode`: metadata delayed with the result.
- `out_value[31:0]`: BF16-rounded result in an FP32 container with low 16 bits
  zero.

The shared RCP/RSQRT Newton datapath occupies four registered stages including
normalization/seed lookup. Metadata and the exp path are aligned to it, then the
result traverses five post stages, preserving the current nine-cycle external
latency. The required contract is throughput, not latency:

- `in_ready` may be deasserted only for reset, explicit pipeline flush, or
  future output/DTCM backpressure.
- In a free-running stream, one input element is accepted every cycle.
- Every accepted element produces exactly one result in program order.
- Back-to-back mixed modes are legal and preserve order.

## Internal Forward Packet

Fused sigmoid/silu/tanh modes must forward extra-precision internal values. The
current product target is BF16 output with a BF20/BF22-style internal format:

```text
BF20 internal:
  sign      1
  exponent  8
  fraction 11
  total    20 bits

BF22 internal:
  sign      1
  exponent  8
  fraction 13
  total    22 bits
```

Both keep the BF16/FP32 exponent range, but carry extra fraction bits through
exp, reciprocal, and finalizer. This is the ACTU equivalent of a TF32-like
middle format: enough extra precision to preserve activation tails, but much
cheaper than full FP32 mantissas. BF22 is the preferred candidate when the extra
two fraction bits fit timing/area.

The fused forward packet is:

```text
x        original lane value
e        exp(-abs(x)) or exp(-2*abs(x))
den      1 + e
inv_den  reciprocal(den)
```

The finalizer uses `e` directly. It must not reconstruct `e` by `den - 1`,
because that loses small tails when `den` rounds to `1.0`.

Implementation rules:

- Round input values into the internal format at the lane boundary when needed.
- Round `e`, `den`, `inv_den`, and finalizer products to the selected internal
  BF20/BF22 format, not BF16.
- Round to BF16 only at `out_value` or DTCM store.
- Keep the Python model's `--internal-dtype` sweep updated before changing the
  RTL internal format width.

The current RTL fixes the fused internal format at BF22:

```text
e        = bf22(exp_lut(pre_x))
den      = bf22(1.0 + e)
inv_den  = bf22(rcp_lut_nr(den))
sigmoid  = inv_den or bf22(e * inv_den)
silu     = bf22(bf22(x) * sigmoid)
tanh     = sign(x) * bf22(bf22(1.0 - e) * inv_den)
```

The finalizer helpers intentionally cover the activation numeric envelope
rather than a full IEEE-754 FPU contract. They flush subnormal results to zero,
return canonical NaN for unexpected special arithmetic, and saturate overflow
to max finite. This is acceptable for the standalone ACTU lane because exp
range reduction, one-to-two reciprocal, and activation finalizers keep normal
finite values in the exercised product range.

## Future DTCM Streaming Command Boundary

ACTU will become a DTCM-backed streaming unit with set/start/sync style control,
matching the tensor software pattern instead of scalar load/store instruction
semantics.

Pending descriptor fields:

```text
pending_actu_descriptor:
  dtype
  mode
  input_ptr
  output_ptr
  n_elements
  softmax_max_or_scalar
```

Planned software surface, modeled after tensor wrappers in
`tests/software/include/edge_intrinsic.hpp`:

```text
0x20 actu.setcsr(dtype, mode)
0x21 actu.setin(input_ptr)
0x22 actu.setout(output_ptr)
0x23 actu.setn(n_elements)
0x24 actu.setscalar(value_or_ptr)   // for softmax max or later scalar parameter
0x25 actu.start()
0x26 actu.sync()
```

The encoding should use the same 64-bit stream envelope as tensor/DMA:

```text
low parcel:
  .insn r 0x3f, 0, 0, rd_or_imm, rs1_or_ptr, rs2
high parcel:
  .word EDGE_TENSOR64_HIGH_WORD(ACTU_SUBOP)
```

`setin`, `setout`, and scalar-pointer forms consume the captured `rs1` value
through the same DTCM-pointer decode convention as tensor. `setn` may support
the low 16 bits of a captured GPR, matching `edge_tensor_setn()` and
`edge_actu_setn()`; SETN has no immediate form.

Descriptor commands update the pending descriptor. `actu.start` snapshots the
pending descriptor into an immutable active job. Following `actu.set*` commands
may update the next pending descriptor but must not modify an active job.
`actu.start` retires when the job is accepted/launched; `actu.sync` is the
ordering point that waits for all older ACTU work to complete.

The first DTCM streaming path should read one element from `input_ptr`, process
it through ACTU, and write one element to `output_ptr`. `n_elements` controls
the number of elements. The product stream path is BF16-only: DTCM stores
16-bit elements packed eight per 128-bit beat. The local DTCM adapter owns
packing/unpacking so the ACTU compute lane can keep a single FP32-container
internal format. The `dtype` CSR field remains reserved for future expansion
but is ignored by the first area target.

## DTCM Scheduling

DTCM is split conceptually into two paths:

```text
upper path:
  scalar LSU
  DMA

lower path:
  tensor
  ACTU
```

ACTU and tensor are not expected to run at the same time in the first product
target. They should share the lower DTCM path rather than adding a competing
upper-path client. This lets DMA run concurrently with ACTU or tensor without
forcing scalar/DMA traffic to block behind activation reads/writes.

Implementation rule:

- Do not route ACTU through D-cache.
- Do not silently steal scalar LSU or DMA upper-path barrels.
- Reuse the tensor-native lower-path style when wiring ACTU to DTCM.
- If tensor and ACTU are both issued concurrently, the first slice may serialize
  at the command pipe or report not-ready; it does not need full lower-path
  arbitration between tensor and ACTU.

## Precision Contract

The Python envelope for the area-first candidate is:

```text
exp split 8+4, reciprocal radix16 2 digits + 1NR, BF16, x=[-8,8]:
sigmoid: rmse=9.8454906e-05 snr_db=76.547
silu:    rmse=0.00039836134 snr_db=78.192
tanh:    rmse=0.00013419606 snr_db=76.866
```

This envelope was measured with full-width FP32-container internal forward
values and BF16 output. The active fused-mode direction is BF20/BF22 internal
plus BF16 output; changing internal format width, LUT sizes, fixed-point
widths, radix16 digits, NR iteration count, or partial-product policy must
update the Python sweep before RTL is treated as an improvement. The RTL tests
should compare directed values and, once random vectors are added, enforce an
SNR/RMSE envelope rather than relying on relative error near zero.

Current BF20 internal experiment for the same area-first candidate:

```text
exp split 8+4, reciprocal radix16 2 digits + 1NR, BF20 internal, BF16 output:
sigmoid: rmse=0.00056436363 snr_db=61.380
silu:    rmse=0.0032750742  snr_db=59.893
tanh:    rmse=0.00062219953 snr_db=63.542
```

BF20 passes the current self-test and preserves finite saturated behavior, but
it is visibly noisier than full-width internal forwarding. BF22 improves the
same candidate to:

```text
exp split 8+4, reciprocal radix16 2 digits + 1NR, BF22 internal, BF16 output:
sigmoid: rmse=0.00029667855 snr_db=66.966
silu:    rmse=0.0016335338  snr_db=65.935
tanh:    rmse=0.00030910375 snr_db=69.619
```

Treat BF22 as the first preferred area-oriented RTL target if the extra
mantissa bits stay cheap after synthesis. Keep SNR/RMSE reports in the loop.

## Focused Tests

Existing:

- `src/test-e3/edge_actu/edge_actu_modes_tb.v`
  - BF16 outputs for all modes against directed Python-model vectors
  - `EXP_ONLY` uses the non-DPI split-LUT exp datapath inside `edge_actu.v`
  - `RCP_ONLY` uses the non-DPI radix16 seed plus 1NR reciprocal datapath
    inside `edge_actu.v`
  - `SIGMOID`, `SILU`, and `TANH` use the non-DPI fused BF22 forward datapath
  - `SOFTMAX` is tested as non-DPI `SOFTMAX_EXP = exp(x - softmax_max)`
  - back-to-back mode ordering
  - one accepted element per cycle in the standalone proof
  - saturation behavior for large positive and negative inputs
  - BF16 fused tail preservation for `sigmoid(-10)` and `silu(-10)`
- `src/test-e3/edge_actu/edge_actu_rcp_rsqrt_pipe_tb.v`
  - consumes Python-generated bit-true vectors for every BF16 bit pattern plus
    exhaustive BF22 fractions at both exponent parities in RCP and RSQRT mode,
    for 163,840 exact output comparisons
  - verifies one accepted/output element per cycle with no mixed-mode bubbles
- `tests/software/cases/EDGE_ACTU_SMOKE/EDGE_ACTU_SMOKE.cpp`
  - SoC stream path coverage for BF16 `EXP_ONLY`, `SIGMOID`, `SILU`, and
    `TANH`, including scalar-store `fence`, DTCM input/output, `actu.sync`,
    and one register-form `actu.setn`
- `tests/software/cases/EDGE_ACTU_PYGEN/actu_pygen.py` and
  `tests/software/cases/EDGE_ACTU_PYGEN/EDGE_ACTU_PYGEN.cpp`
  - Python-generated BF16 input vectors and expected JSON derived from
    `activation_asic_model.py`
  - SoC DTCM stream coverage for BF16 `EXP_ONLY`, `SIGMOID`, `SILU`, `TANH`,
    and `SOFTMAX_EXP = exp(x - softmax_max)`
  - Verilator testbench `ACTU_WRITE[...]` report records are parsed by Python
    to reconstruct the ACTU output buffer instead of relying on C++ self-checks
  - the `SOFTMAX_EXP` case uses nonzero register-form `actu.setscalar`, so it
    covers the scalar-producer to accel-consumer path without software nops
- `src/test-e3/edge_actu/edge_actu_exp2_split_tb.v`
  - directed coverage for the split 8+4 base-2 fraction LUT against the Python
    `2^f` table quantization and Q14 product rounding
- `src/test-e3/edge_actu/edge_actu_exp2_pack_tb.v`
  - directed coverage for `mant_q14 * 2^k` FP32 packing, including
    underflow/overflow policy matching the current Python model envelope
- `src/test-e3/edge_actu/edge_actu_exp2_core_tb.v`
  - directed coverage for the fused `k + frac_code` exp2 backend path:
    split 8+4 fraction LUT followed by Q28 FP32 pack
- `src/test-e3/edge_actu/edge_actu_exp_range_tb.v`
  - directed coverage for FP32 input range conversion into `k + frac_code`,
    including `x <= -87` underflow and `x >= 88` clamp-to-88 behavior
- `src/test-e3/edge_actu/edge_actu_exp_lut_tb.v`
  - directed coverage for full non-DPI split-LUT exp against Python
    `_exp_lut_2base_split()`
- `src/test-e3/edge_actu/edge_actu_rcp_seed_tb.v`
  - exact directed coverage for the radix-16 2-digit seed against
    `_rcp_radix16_seed()`
- `src/test-e3/edge_actu/edge_actu_rcp_nr_tb.v`
  - Q16 one-to-two reciprocal coverage for seed plus one NR correction against
    Python `radix16_nr` rounded to Q16, allowing 1 LSB fixed-point drift
- `src/test-e3/edge_actu/edge_actu_rcp_lut_tb.v`
  - directed coverage for generic FP32 reciprocal normalization, one-to-two
    radix16+1NR, and FP32 repack

- fixed-point width regression against Python-generated expected values
- DTCM streaming test with input/output pointers and `n_elements`
- full softmax normalization test after row-sum reciprocal/final multiply is
  assigned to ACTU or scalar/FPU assist software
