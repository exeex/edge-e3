# edge_pc_redirect_ctrl.v

## Purpose

PC generation and redirect control for the dual-stream target. This block should
reuse the existing C906 IFU/PCGEN change-flow structure where practical, but
adapt the frontend contract for a 32/64-only instruction stream and extra
vector/tensor cleanup paths.

## Reference RTL

Existing sources to study before implementation:

```text
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_pcgen.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_top.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_btb.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_bht.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_ipack.v
```

The inherited `aq_ifu_pcgen` priority is a good starting point:

```text
RTU redirect > IU branch target > predictor redirect > sequential fetch
```

The dual-stream target can keep this priority shape. Compared with C906, the
first slice only adds a program-order kill boundary so vector queue entries,
tensor queue entries, lite-rename capture slots, and VR WBT reservations can be
cancelled with the same redirect.

## Implemented First Slice

Implemented file:

```text
edge_pc_redirect_ctrl/edge_pc_redirect_ctrl.v
```

The current RTL is a narrow redirect arbiter for resolved scalar control flow
plus a static loop predictor path. Conditional branches whose decoded target is
below their own PC may request a predicted redirect. Scalar branch resolution
remains authoritative: a correct prediction is only confirmed, while a
prediction miss redirects to the actual next PC and flushes the predicted-path
epoch.

This slice also accepts a higher-priority retire redirect input for the later
trap/exception/privileged path, but the current integration tests drive it low.

## Inputs

From scalar branch/execute:

```text
scalar_control_valid
scalar_control_taken
scalar_control_target
scalar_control_seq_id
scalar_control_epoch
```

From scalar/retire redirect:

```text
retire_redirect_valid
retire_redirect_pc
retire_redirect_seq_id
retire_redirect_epoch
```

From loop-branch prediction helper:

```text
loop_predict_valid
loop_predict_target
loop_predict_fallthrough
loop_predict_seq_id
loop_predict_epoch
```

From fetch/I-cache:

```text
fetch_grant
fetch_reissue
```

## Outputs

To IFU/I-cache:

```text
ifu_redirect_valid
ifu_redirect_pc
ifu_redirect_epoch
```

To predecoder/scalar/vector/tensor queues:

```text
current_epoch
redirect_flush_valid
redirect_predict_valid
redirect_kill_seq_id
redirect_kill_epoch
redirect_new_epoch
```

`redirect_predict_valid` marks redirects that came from the predictor source.
Frontend queues consume the normal `redirect_flush_valid` to drop younger
tokens and restart fetch, but the scalar pipe must not treat a prediction-only
redirect as a kill of the branch instruction that is currently issuing. Scalar
WBT/pipe kill should use `redirect_flush_valid && !redirect_predict_valid`.

## PC Increment Rule

C906 increments fetch PC by 4 at the PCGEN fetch boundary and lets the IFU/IPACK
handle 16-bit/32-bit packing details. The dual-stream target does not support
compressed instructions, so token length tracking is simpler:

```text
32-bit scalar instruction:            pc += 4 in token stream
64-bit Edge Vector instruction:       pc += 8 in token stream
64-bit Edge Tensor DMA/Tensor command: pc += 8 in token stream
```

The fetch PC generator does not need to retire one instruction per increment.
It only needs to keep I-cache fetch packets flowing. Program-order PC belongs to
the predecoder/token stream.

## Redirect Priority

Use the same broad priority as C906:

```text
1. scalar/retire redirect
2. scalar branch/jump resolved redirect
3. loop-branch predictor / BTB predicted redirect
4. sequential fetch
```

Scalar/retire redirect is authoritative and must kill scalar, vector, and tensor
younger work. The first slice does not implement trap-vector, interrupt, or
debug-halt redirects.

## Redirect/Kill Rule

The first-slice model is simpler than a ROB. The predecoder creates one
monotonic program-order `seq_id` stream for scalar instructions, vector tokens,
tensor tokens, vector commands, and tensor commands. A resolved branch/jump or
retire redirect provides the last correct-path sequence id:

```text
redirect_kill_valid
redirect_kill_seq_id    // redirecting instruction's seq_id
redirect_kill_epoch     // epoch containing that seq_id
redirect_new_epoch      // epoch assigned to refetched correct-path work
redirect_pc             // corrected fetch PC
```

Every queue-like block applies the same kill rule:

```text
if entry.epoch == redirect_kill_epoch
   and entry.seq_id > redirect_kill_seq_id:
  kill entry

if entry.epoch != current_epoch after redirect:
  treat entry as stale and drop it before use
```

This is the dual-stream version of C906's change-flow plus cancel/flush
broadcast. The PC redirect follows C906 priority; the `seq_id` boundary only
exists because the vector queue and lite-rename file may contain predicted-path
work outside the scalar pipe.

For the first slice, make the epoch counter wide enough that wrap does not occur
within a simulation test. Later designs can add wrap-safe epoch comparison if
needed.

The implemented RTL increments `current_epoch` by one for every redirect and
uses the incremented value as both `ifu_redirect_epoch` and
`redirect_new_epoch`.

## Kill Targets

On redirect, the following structures consume the same kill boundary:

```text
predecoder / scalar token queue:
  drop younger scalar tokens and pseudo tokens

edge_accel_cmd_queue:
  drop younger vector commands

edge_accel_pipe / tensor command queue:
  drop younger DMA/Tensor commands

edge_wbt instances:
  release killed destination reservations

vector writeback:
  suppress killed writeback or done packets
```

## Loop Predictor Integration

The common Edge Vector loop:

```c
for (int n = element_num; n > 0; n -= vl)
```

uses the built-in static helper in `edge_predecoder`: if a 32-bit conditional
branch is accepted and its immediate target is less than the branch PC, the
frontend predicts taken and redirects to the loop head. The same predictor-class
redirect path is also used for direct `jal`, whose target is available from the
J-immediate at predecode time. Forward conditional branches are not predicted.
`jalr` is not predicted because its target depends on a GPR value.

The redirect controller tracks one outstanding predicted branch. If scalar
resolution later reports that the actual next PC differs from the predicted
target, the controller redirects to either the resolved target or the recorded
fallthrough PC and kills the predicted-path epoch. If the scalar branch resolves
in the same cycle as the prediction request, the controller can suppress the
wrong predicted redirect and directly choose the actual next PC.

When an older scalar control result and a younger loop prediction arrive in the
same cycle, and the older control result does not request an authoritative
redirect, the younger loop prediction is still the selected redirect. The
controller must record that prediction unless the scalar control result belongs
to the same branch as the prediction. Otherwise the predicted branch will resolve
one cycle later as an apparently unpredicted taken branch and issue a second
redirect to the same target, creating an avoidable flush/epoch storm.

## Tests

Integration tests:

```text
tests/hardware/DUALSTREAM/edge_frontend_branch_redirect_tb.v
tests/hardware/DUALSTREAM/edge_pc_redirect_predict_tb.v
```

The test proves that a taken scalar branch result redirects IFU fetch to a
32-bit instruction starting in the middle of a 128-bit packet, flushes the
tokenizer/predecoder through a new epoch, and prevents wrong-path scalar
instructions already present in the fetch packet from retiring. The predictor
test proves predicted redirect, stored prediction miss correction to
fallthrough, predicted-correct confirmation without a second redirect, and
ordinary unpredicted taken redirect.

## Recommendation

Reuse C906 PCGEN/IFU ideas, not the exact instruction-packing contract:

```text
reuse:
  redirect priority
  fetch reissue concept
  I-cache fetch packet flow
  BTB/BHT optional structure

replace/adapt:
  predecode length handling for 32-bit scalar, 64-bit Edge Vector, and
  64-bit Edge Tensor
  epoch tags for scalar/vector/tensor redirect kill
  retire token PC length = 4/8 bytes
  loop-branch predictor as a narrow extra predictor source
```
