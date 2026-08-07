# edge_fpu_slow

`edge_fpu_slow` owns the variable-latency, single-outstanding FP32 FDIV/FSQRT
slot. It follows the integer mul/div ready/busy/registered-completion contract
and retains sequence, epoch, destination, and bank metadata until completion.

The numerical datapath follows Berkeley SoftFloat Release 3e concepts: exact
significand quotient or integer square root, sticky-bit formation, canonical
RISC-V NaNs, and the same round-pack rules for the five static rounding modes.
Subnormal operands normalize one bit per cycle. Divide uses one restoring
quotient bit per cycle and square root uses one radix-2 digit per cycle through
the same single-outstanding state machine. A negative result exponent is
right-shifted with jam one bit per cycle before the registered round/pack step.
There is no synthesizable `/`, combinationally unrolled square-root loop,
remainder-check multiplier, or variable-distance result shifter.
The final round/pack addition retains the full 25-bit rounded significand so a
carry across the hidden-bit boundary advances the encoded exponent; this is
required for directed rounding of values immediately below an exponent
boundary, such as `sqrt(nextafter(1,0))` under RUP.

`DIV_LATENCY` and `SQRT_LATENCY` remain source-compatible parameters but do not
set the execution latency. Latency depends on operand normalization and result
denormalization in addition to the 31/32 arithmetic iterations.

Cancel drops busy state and suppresses completion. Dynamic rounding and FCSR
state remain out of scope.

The manual scalar-pipe `hw_edge_scalar_pipe_fpu_random_diff` flow mixes
SoftFloat-referenced FDIV/FSQRT with four-cycle FMAC and one-cycle misc/FCVT
instructions. It verifies final FP32 payloads, slow-slot backpressure through
the normal issue handshake, empty GPR/FPR WBTs, and strict sequence/epoch
retirement even when execution completes out of order.
