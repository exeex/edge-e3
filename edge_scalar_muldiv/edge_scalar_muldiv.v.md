# edge_scalar_muldiv.v

## Purpose

RV64M wrapper containing one shared multiply domain and an independent
`edge_scalar_divrem` domain. It arbitrates their held results onto the scalar
pipe's existing single M completion port.

## Ownership

`edge_scalar_muldiv` owns:

- RV64M `mul`, `mulh`, `mulhsu`, `mulhu`
- RV64M word `mulw`
- the single-MUL busy/ready state and partial-product accumulator
- lossless arbitration between held MUL and DIV/REM completions

`edge_scalar_divrem` owns divide/remainder arithmetic, corner cases, local
busy state, metadata, and its held completion.

It does not own ordinary RV64I ALU operations, branch/jump facts, scalar pipe
issue selection, WBT, retire, or redirect.

## Current Implementation Note

Multiply uses one shared 32x32 registered partial-product datapath:

- RV64W `mulw` feeds one 32x32 product in the accept cycle and completes on the
  next cycle
- low-result RV64 `mul` starts with `LL`, then uses a three-bit pending-work
  mask to feed only the required `LH` and/or `HL` cross partials; both
  zero-extended-32 operands complete in one cycle, exactly one nonzero upper
  half completes in two, and two nonzero upper halves complete in three
- RV64 `mulh`, `mulhsu`, and `mulhu` force `LH`, `HL`, and `HH` pending and
  therefore retain the full four-cycle path
- returned partial products are accumulated into a 128-bit product
- high-half signed variants convert signed operands to magnitudes before the
  partial-product loop, then apply a final 128-bit two's-complement correction
- `m_issue_ready` remains low until the current multiply completes, so 32-bit
  and 64-bit multiply instructions cannot interleave inside the shared pipe

The 32x32 multiply is fully combinational before the product register. Earlier
RTL carried that already-computed product through three additional delay
registers without splitting the multiply path. Those delay-only stages are not
part of the maintained contract: one product register preserves the same
multiplier and accumulator timing boundaries. The first cleanup reduced RV64
multiply latency from seven to four cycles and RV64W multiply latency from four
to one; the pending-work mask now shortens only low-result operations whose
upper halves prove that cross partials are mathematically zero.

Divide and remainder are instantiated through `edge_scalar_divrem`, which uses
a radix-4 iterative unsigned core with a signed wrapper:

- every round consumes two dividend bits and emits two quotient bits
- RV64 `div/rem` runs 32 rounds
- RV64W `divw/remw` runs 16 rounds
- signed operations convert operands to absolute values before the unsigned
  loop, then correct quotient and remainder signs at completion
- divide-by-zero and signed-overflow cases bypass the iterative loop and return
  the architectural result through the normal registered complete path

The RTL intentionally avoids Verilog `/` and `%` so the divider area is explicit
and predictable under synthesis.

## Interface

`m_issue_ready` is selected by the current request class. MUL readiness depends
only on the single multiplier and its completion holding slot; DIV/REM readiness
depends only on `edge_scalar_divrem`. Thus one multiply and one divide may be
active concurrently, but two multiply requests cannot overlap.

MUL and DIV/REM each hold a completed packet until selected. The existing M
completion port consumes one packet per cycle, with MUL priority when both are
valid; DIV/REM remains stable and is emitted on the following cycle. RTU and
WBT are not part of this arbitration.

## Tests

Covered through:

```text
src/test-e3/edge_scalar_muldiv/edge_scalar_muldiv_arith_tb.v
src/test-e3/edge_scalar_alu/edge_scalar_alu_rv64i_tb.v
src/test-e3/edge_scalar_pipe/edge_scalar_pipe_rv64i_alu_control_tb.v
```

The local arithmetic test checks exact one-, two-, three-, and four-cycle MUL
classes, both two-partial directions, MULW sign extension, all high-result
signedness variants, shared-MUL saturation, and simultaneous MUL/DIV completion
arbitration.
