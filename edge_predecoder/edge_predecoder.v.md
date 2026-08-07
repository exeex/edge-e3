# edge_predecoder.v

## Fast/M scalar pairing

RV64M has a distinct scalar class. The greedy policy may emit `M + fast ALU`,
`fast ALU + M`, or `fast ALU + fast ALU`. The scalar pipe performs the final
opcode, dependency, destination, and control-flow eligibility checks. 64-bit
tensor/DMA commands retain their single-window behavior.
`EDGE_DISABLE_SCALAR_M_FAST_PAIR` disables only this pair class for controlled
performance comparisons while leaving LSU dual issue enabled.

## Current Snapshot Contract

The production tensor/DMA/ACTU operand path no longer uses lite rename. For a
command that reads GPR fields, the predecoder forks one scalar holder pseudo in
program order and encodes `seq_id[2:0]` as its 3-bit snapshot target. The holder
writes the selected GPR into the eight-entry snapshot store before the
tensor/DMA/ACTU command can consume it. References to lite rename and generic
capture-slot allocation later in this document describe the historical vector
proof slice, not the current tensor/DMA/ACTU integration.

Holder and accelerator outputs dispatch atomically: backpressure from either
sink prevents token consumption and prevents the other half from firing. A
redirect flush suppresses both outputs and token consumption in the redirect
cycle; software may then re-present the same command identity in the new epoch
as one fresh bundle.

The window-bundle directed test covers both asymmetric stall directions
(holder stalled or accelerator stalled), redirect while the stalled sink is
released, both-ready redirect suppression, and same-identity new-epoch reuse.

Zero-capture control commands must remain zero-capture even when the
accelerator token is delayed by the frontend window. This includes ACTU
`start` and `sync`; `tensor.setn`, `actu.setn`, and `cmpu.setn` always use a
captured GPR. CMPU pointer setup commands follow the same one-snapshot rule as
ACTU pointer setup, while `cmpu.setcsr/start/sync` require no snapshot.
`setcsr` carries dtype and mode/wtype in the high-parcel control field.
`accel.getcsr` (`0x2f`) is forked atomically into an accelerator command and
scalar pseudo kind 3. Predecode first allocates one of two reverse-snapshot
slots; when both are owned, the token remains blocked. The same 1-bit ID is
written into accelerator instruction bit 52 and scalar pseudo bit 25, while
the low instruction `rd` becomes the scalar definition. Neither half becomes
visible unless the scalar lane, accelerator queue, and allocator can all
accept together.
`tensor.sync`, `dma.sync`, and `actu.sync` use a
different pseudo kind. The predecoder forks
each sync into an accel command and a scalar join pseudo with identical
`seq_id`/epoch. The join has no GPR snapshot sources; it waits in the scalar RTU
until the accel command reports that all older work is complete.

## Purpose

Split the incoming instruction stream before the original scalar IDU boundary.
The predecoder is the ownership point for instruction length classification and
for generating synchronization tokens between scalar, Edge Vector, and Edge
Tensor streams. It also allocates lightweight scalar-operand capture slots for
vector or tensor-pipeline commands that need scalar producer values.

The current RTL is an incremental lite-rename proof slice. It still accepts
already-decoded testbench-facing facts for one scalar producer definition and
one vector/tensor command operand. It also accepts a raw 64-bit Edge Vector
sideband so the vector low-opcode split, `rs4` scalable-vector `n` capture, and
load/store base-GPR capture can be proven before the full IFU parser is wired.

The final predecoder is a 128-bit fetch-packet tokenizer, token packer, and
ordered issue gate, not a single-instruction adapter. The IFU supplies naturally
aligned 128-bit packets; the predecoder owns the byte cursor, packet-middle
redirect start offset, cross-packet 64-bit assembly, and same-cycle stream
sidebands.

The maintained target is a two-lane frontend over three instruction pipelines:

```text
scalar pipe
accelerator pipe
tensor/DMA pipe
```

Each cycle can select at most two adjacent program-order tokens. With scalar
instructions at 32 bits and vector/tensor/DMA instructions at 64 bits, 128-bit
fetch covers the useful two-token combinations:

```text
scalar + scalar = 32b + 32b = 64b
scalar + vector = 32b + 64b = 96b
scalar + tensor = 32b + 64b = 96b
vector + tensor = 64b + 64b = 128b
```

Three-way same-cycle issue is intentionally out of scope. It would require 160
bits for `scalar + vector + tensor`, adds pipe arbitration complexity, and does
not match the expected software scheduling need. The maintained target keeps
vector and tensor semantics separate. They may share the predecoder's physical
64-bit issue window and ordered issue gate, but they dispatch to different
instruction lanes: vector commands enter the vector queue/pipe with VR/WBT
state, while tensor commands enter the tensor queue/pipe without VR state.

In the first implementation, the scalar pipe still accepts one scalar
instruction per cycle. The maintained scalar LSU can accept a limited lane1
memory candidate through the scalar path, so a `scalar + scalar` frontend pair
may either issue as a supported pair or queue in program order with the second
scalar replaying later. The packet and lane contract intentionally leaves room
for a future broader scalar lane1 policy without changing the 128-bit
fetch/token contract.

The next predecoder storage shape is split by physical issue width:

```text
token packer
  -> scalar32_window   // 32-bit scalar entries, pop 0..2
  -> accel64_window    // complete 64-bit vector/tensor entries, pop 0..1
  -> ordered issue gate
  -> accelerator command queue or tensor command queue
```

The split windows do not create independent issue domains. Every complete entry
keeps a global program-order `seq_id`. The ordered issue gate compares the
oldest scalar32 entry with the oldest accel64 entry and only issues from the
oldest stream. Scalar lane1 is allowed only when the second scalar is also the
next global entry and the scalar pair is supported by the scalar backend. For
example, `S0 S1 A2` may issue `S0+S1` and leave `A2`; `S0 A1 S2` may issue only
`S0`, then `A1`, then `S2`.

This is the intended replacement for the current direct `32/64` bundle pattern
logic. A 64-bit entry that sits behind older scalar entries simply remains in
the accel64 window until those scalars are consumed, then issues from the global
head. No younger scalar may bypass it.

The predecoder may look ahead across packet boundaries through its local byte
queue, but by the issue cycle it must present a consistent same-cycle sideband
bundle for both tokens that fire. In particular, scalar producer metadata and
vector/tensor capture-id selection must be computed together so same-window
producer capture is visible to both the scalar pipe and the vector/tensor queues
in the same cycle.

For 64-bit packet-boundary cuts, the token packer owns a single pending-half
state:

```text
pending64_valid
pending64_low32
pending64_pc
pending64_seq_id
pending64_epoch
pending64_kind
```

When a packet ends with only the low 32 bits of a vector/tensor instruction, the
packer records the half and enqueues nothing for that instruction. The next
packet must provide the high 32 bits before younger entries from that packet are
packed. Redirect flush clears the pending half. Downstream windows never see
half entries.

Implemented file:

```text
edge_predecoder/edge_predecoder.v
```

Implemented first-slice limits:

- one scalar capture operand per decoded command
- raw 64-bit Edge Accelerator laneband plus typed token-lane frontend path
- typed mixed/vector token path now normalizes through
  `edge_predecode_token_packer` before selecting scalar/vector command
  sidebands; legacy 96-bit `window_valid` still uses the old direct pattern
  logic until that compatibility path is retired
- raw Vector capture supports `n` and load/store base GPR operands
- typed-token Vector capture supports `rs4` `n` plus `vld/vst` `rs1` base
  GPR operands; load/store window commands emit after the extra base rename
  stage
- typed-token DMA capture uses one GPR per command: `dma.setsrc` and
  `dma.settar` capture low-parcel `rs1`, while `dma.start` captures low-parcel
  `rd` as length or circular tile count. No Tensor/DMA command allocates more
  than one capture id.
- `tensor.setn` and `actu.setn` always allocate one low-`rs1` capture; `x0`
  no longer selects a high-parcel immediate form.
- legacy 96-bit window input remains only as a transitional compatibility path
- IFU refill parsing is owned by `edge_ifu_predecode_frontend`; the production refill
  boundary is 64 bits after the 128-to-64 fetch splitter
- static backward-branch loop prediction for accepted 32-bit conditional
  branch tokens
- no branch/control dependency id allocation yet
- no retire token queue yet
- no final packed multi-operand Tensor setup command allocation yet

## Inputs

Expected fetch input from IFU/I-cache:

```text
fetch_valid
fetch_ready
fetch_block_pc
fetch_bits[127:0]
fetch_start_word[1:0]
fetch_epoch
fetch_predict_info
redirect_kill_valid
redirect_kill_epoch
redirect_new_epoch
```

The current RTL uses this narrower decoded-fact interface until the instruction
parser is added:

```text
scalar_def_valid
scalar_def_domain
scalar_def_dst_reg
scalar_def_seq_id
scalar_def_epoch

decoded_valid
decoded_ready
decoded_seq_id
decoded_epoch
decoded_is_tensor
decoded_capture_count       // first RTL supports 0 or 1
decoded_src0_domain
decoded_src0_reg
decoded_src0_is_n_capture

raw_valid
raw_ready
raw_seq_id
raw_epoch
raw_inst64
raw_is_64b

token0_valid
token_ready
token_consume_count
token0_kind
token0_len_bytes
token0_pc
token0_inst32
token0_inst64
token0_seq_id
token0_epoch

token1_valid
token1_kind
token1_len_bytes
token1_pc
token1_inst32
token1_inst64
token1_seq_id
token1_epoch

redirect_flush_valid
redirect_new_epoch
```

The maintained fetch/predecode path consumes typed tokens from
`edge_ifu_predecode_frontend`, which owns 64-bit chunk assembly and token
assembly. The predecoder owns same-cycle issue selection, scalar/vector rename
sideband, and per-pipeline command handoff.

The scalar-only typed-token path now has the first in-order issue-window slice.
When scalar lane 0 or scalar lane 1 cannot consume the presented bundle, the
predecoder enqueues complete scalar entries instead of blocking tokenizer
acceptance solely because lane 1 refused a candidate. The full scalar/vector
replacement is documented in `edge_token_issue_window.md`: tokenizer output is
first normalized into ordered predecode entries, then an in-order issue window
chooses scalar consume counts of 0, 1, or 2 each cycle.

The implemented token path supports scalar-only, vector-only, tensor-only, and
scalar+scalar bundles as long as tokens are adjacent in program order. Mixed
scalar+accel token pairs are split at the program-order head. If scalar is
older, only that scalar is consumed. If vector/tensor is older, only the accel
token is consumed and any younger scalar remains the next tokenizer head. Tensor
tokens share the current accel64 command sideband and are distinguished by
`accel_command_is_tensor` until a dedicated tensor command pipe is connected.
For the current scalar pipe boundary, token 0 remains the canonical scalar lane
and token 1 is presented as an opportunistic memory or fast-ALU lane-1 candidate
for `load+load`, `store+store`, `ALU+ALU`, or non-control integer
`ALU+memory` / `memory+ALU` pairs. If lane 1
accepts it, the second scalar is consumed in the same cycle; otherwise it
remains in the scalar issue window and replays through lane 0 later. The reverse
`memory+ALU` direction reuses the single physical ALU while lane0 uses the LSU.
Vector/tensor head tokens still use the direct decode path
and wait for the scalar issue window to drain before they can issue.
This preserves snapshot causality: tensor/vector snapshot pseudo instructions
cannot bypass an older scalar instruction that may produce the source GPR. The
legacy 96-bit `window_valid` compatibility path still uses the older direct
mixed bundle logic until that interface is retired. The bundle outputs must
include per-stream valid/ready and per-operand
sideband:

```text
scalar_valid
scalar_ready
scalar_pc
scalar_inst
scalar_def_valid
scalar_def_domain
scalar_def_dst_reg
scalar_def_bank
scalar1_valid
scalar1_ready
scalar1_pc
scalar1_inst
scalar1_def_valid
scalar1_def_dst_reg
scalar1_def_bank

vector_valid
vector_inst64
vector_n_capture_id
vector_n_capture_bank
vector_base_capture_id
vector_base_capture_bank

tensor_valid
tensor_inst64
tensor_capture_id*
tensor_capture_bank*
```

`scalar_def_bank` and vector/tensor capture-bank outputs are retained only as
legacy sideband. The current small-pool capture path drives them to zero; the
capture identity is the generic `capture_id`.

Within a bundle, rename analysis follows program order:

1. Decode fixed vector/tensor operand templates first. For the current Vector
   proof slice, `rs4` is always the scalable-vector `n` GPR operand.
2. For each scalar operand required by vector/tensor, search only earlier lanes
   in the same aligned issue window for a scalar instruction that writes the
   same architectural scalar register.
3. If an earlier scalar producer matches, that producer is assigned a generic
   capture slot as it enters the issue window, and the vector/tensor operand
   sideband points at the same `capture_id` in the same cycle.
4. If there is no earlier same-window producer, the operand uses the current
   producer-version mapping already held by the predecoder.
5. Later lanes in the same window are not visible to earlier vector/tensor
   operands. For example, in `64+32`, the vector in lanes 0/1 must not consume
   the scalar definition in lane 2.

Mappings are producer-version mappings, not permanent register-name aliases. If
`x10` is captured into slot 1, later operands that consume the same producer
version of architectural `x10` reuse slot 1 until another scalar definition of
`x10` closes that mapping. The old slot can remain live for already-issued
vector/tensor consumers and is released by capture refcount; a new producer
version allocates another free slot when a vector/tensor operand needs it.

## 128-bit Packet Tokenization

The IFU fetch packet contract is:

```text
edge_ifu_fetch/edge_ifu_fetch.v.md
```

`fetch_bits[127:0]` is always aligned to `fetch_block_pc[3:0] == 0`. The
predecoder must not assume the first valid instruction starts at byte offset 0.
After a branch or jump redirect, `fetch_start_word` may point to word offset 0,
1, 2, or 3 within the packet:

```text
fetch_start_word = redirect_pc[3:2]
```

The predecoder maintains a byte queue and a program-order cursor:

```text
byte_queue_bits
byte_queue_valid
cursor_pc
cursor_epoch
```

On normal packet accept, bytes are appended in increasing PC order. On
redirect/kill or stale epoch, the queue is flushed and the next accepted packet
starts at `fetch_start_word`.

The byte queue must be wide enough to assemble two issued tokens plus one
lookahead token-length decision. The first maintained RTL should use at least
24 bytes:

```text
max dual issue bytes: 64b + 64b = 16 bytes
lookahead length peek: 32b marker = 4 bytes
cross-packet margin: at least 4 bytes
```

A 32-byte queue is preferred if it keeps the implementation simpler.

## Token Length Rule

The scalar ISA slice has no compressed instructions. Legal instruction starts
are 32-bit aligned:

```text
cursor_pc[1:0] == 2'b00
```

The tokenizer peeks at the next 32 bits at `cursor_pc`:

```text
if inst32[6:0] == 7'b0111111 && inst32[7] == 1'b0:
  token_len = 8
  token_kind = EDGE_VEC64
else if inst32[6:0] == 7'b0111111 && inst32[7] == 1'b1:
  token_len = 8
  token_kind = EDGE_TENSOR64
else:
  token_len = 4
  token_kind = SCALAR_RV64
```

For a 64-bit token, the following high word carries `opcode8 = high_word[7:0]`.
The tokenizer waits until the high word is present before classifying the token
as Vector or Tensor/DMA.

For 64-bit tokens, all eight bytes must be present before issue. This matters
when a redirect lands at offset 12:

```text
packet N offset 12 supplies low 4 bytes
packet N+1 offset 0 supplies high 4 bytes
```

The predecoder waits for the second packet and then emits the assembled 64-bit
token. The IFU does not shift or special-case this crossing.

## Dual-Issue Bundle Rule

Each cycle, the predecoder may emit up to two adjacent program-order tokens.
Token 1 starts exactly after token 0:

```text
token0_pc = cursor_pc
token1_pc = cursor_pc + token0_len
```

Allowed byte-length pairs:

```text
4 + 4
4 + 8
8 + 4
8 + 8
```

The predecoder may emit only token 0 when token 1 is absent, crosses unavailable
bytes, is blocked by downstream ready, or would violate a local ordering rule.
It must not skip token 0 to issue token 1.

A legal issue bundle can contain scalar-only, vector-only, tensor-only,
scalar+scalar, scalar+vector, scalar+tensor, vector+scalar, tensor+scalar,
vector+tensor, or tensor+vector, as long as the instruction bytes are present,
32-bit aligned, adjacent in program order, and all destination stream ready
conditions are satisfied.

Same-pipeline vector/tensor pairs are not dual-issued by the maintained
frontend:

```text
vector + vector
tensor + tensor
```

For `scalar + scalar`, the predecoder may present two scalar frontend lanes or
enqueue the second scalar token behind the first. The current scalar pipe
consumes one scalar token per cycle; future scalar superscalar work may consume
both lanes without changing the 128-bit fetch/token contract.

If token 0 and token 1 target the same vector/tensor pipeline, token 0 may issue
and token 1 remains at the cursor for a later cycle. The predecoder must not
skip token 0 to issue token 1.

Three-way `scalar + vector + tensor` issue is a non-goal for this architecture.
The 128-bit fetch packet is the stable frontend width.

Implemented first-slice RTL now consumes the typed token lanes emitted by
the token assembly logic inside `edge_ifu_predecode_frontend`:

```text
token0_valid
token_ready
token0_kind
token0_len_bytes
token0_pc
token0_inst32
token0_inst64
token0_seq_id
token0_epoch

token1_valid
token1_kind
token1_len_bytes
token1_pc
token1_inst32
token1_inst64
token1_seq_id
token1_epoch
```

`token_consume_count` reports how many complete tokenizer entries were accepted
in the current cycle. `token_ready` is retained as a compatibility observation
signal and is high when `token_consume_count` is non-zero. The predecoder
supports `vector-only`, `tensor-only`, `scalar-only`, and `scalar+scalar` in
this slice. Mixed scalar+accel typed-token pairs are accepted over two cycles in
program order instead of same-cycle mixed issue. Scalar-only token bundles feed
the scalar issue
window. When the window is empty and lane 0 is ready, token 0 can bypass the
window and issue immediately. If token 1 is not accepted by lane 1, the
predecoder either buffers token 1 in the scalar issue window while the window is
below the low-water mark, or consumes only token 0 and leaves token 1 in the
tokenizer as the next head. If lane 0 is not ready, token 0 can still be
accepted into the issue window when space is available.

Lane 1 supports same-class `load+load`, `store+store`, and `ALU+ALU`, plus
mixed `ALU+memory` and `memory+ALU` pairs. If the scalar pipe rejects a pair,
the second scalar remains ordered in the issue window at low water, or remains
in the tokenizer when the scalar issue window is near full. Vector-only and
tensor-only token bundles still use the direct decode path. They are
backpressured while the scalar issue window is non-empty so they cannot bypass
older scalar entries. When an accel token is the head and needs a tensor
snapshot pseudo instruction, the pseudo instruction is issued on scalar lane 0
with the accel command in the same cycle; a younger scalar token in token1 is
not consumed in that cycle.

The pseudo stores its 2-bit target in instruction bits `26:25`; bits `31:27`
are cleared. The scalar pipe therefore carries only the four reachable slot
values instead of the previous 3-bit target.

The typed-token mixed/vector path now uses `edge_predecode_token_packer` as the
normalization helper. `token0/token1` are expanded back into ordered 32-bit
slots only inside this local path, then the packer emits scalar and accel
entries. The current integrated path consumes only the first accel entry. If a
second accel entry is visible in the same token bundle, such as `vector+vector`
or `vector+tensor`, the predecoder consumes only token 0 so token 1 remains the
next tokenizer head. Tensor accel entries remain backpressured until the tensor
command boundary is implemented.

This is not yet the full split-window architecture. Scalar-only token bundles
still use the existing scalar issue-window path, and mixed/vector token bundles
still issue directly once the scalar issue window is empty. The next integration
slice should add the real accel64 window and move the `edge_predecode_order_gate`
into `edge_predecoder`.

The legacy 96-bit `window_*` input remains as a transitional compatibility
path for older module/integration tests. New frontend wiring should use
`token*` ports.

## Bundle Rename Rule

Within a dual-issue bundle, capture analysis follows program order:

1. Decode fixed vector/tensor operand templates for each emitted lane.
2. For each scalar operand required by vector/tensor, search only earlier lanes
   in the same issue bundle for a scalar instruction that writes the same
   architectural scalar register.
3. If an earlier scalar producer matches, that producer is assigned a generic
   capture slot as it enters the issue window, and the vector/tensor operand
   sideband points at the same `capture_id` in the same cycle.
4. If there is no earlier same-bundle producer, the operand uses the current
   producer-version mapping already held by the predecoder.
5. Later lanes in the same bundle are not visible to earlier vector/tensor
   operands. For example, in `64+32`, the vector/tensor token in lane 0 must not
   consume the scalar definition in lane 1.

Mappings are producer-version mappings, not permanent register-name aliases. If
`x10` is captured into slot 1, later operands that consume the same producer
version of architectural `x10` reuse slot 1 until another scalar definition of
`x10` closes that mapping. The old slot can remain live for already-issued
vector/tensor consumers and is released by capture refcount; the new producer
version allocates another free slot only when a vector/tensor operand needs it.

## Instruction Classes

Edge Vector and Edge Tensor share the standard RISC-V 64-bit length marker and
split streams with the low instruction byte:

```text
inst64[6:0] = 7'b0111111
inst64[39:32] = opcode8
opcode8[7]    = Vector versus Tensor/DMA stream select
```

The predecoder must assemble all 64 bits before dispatching either command
family. The scalar IDU must not see the real 64-bit Edge Vector or Edge Tensor
instruction. The RTL uses one shared `EDGE64_LENGTH_MARKER` parameter and
classifies Vector versus Tensor with high-word `opcode8[7]`.

```text
SCALAR_RV64
  Normal 32-bit RV64IM/floating-point instruction.
  Sent to edge_scalar_pipe.

EDGE_VEC64
  64-bit Edge Vector instruction.
  Sent to edge_accel_pipe.
  Also creates a retire-visible token in scalar program order.

EDGE_VEC64_GPR_SYNC
  Edge Vector instruction requiring GPR operands such as address, index, stride,
  length `n`, or scalar parameter.
  Sent to edge_accel_pipe.
  Allocates lightweight GPR rename/capture slots. The vector command waits for
  those slots to become ready.

EDGE_VEC64_FPR_SYNC
  Edge Vector instruction requiring FPR operands.
  Sent to edge_accel_pipe.
  Allocates lightweight FPR rename/capture slots. The vector command waits for
  those slots to become ready.

EDGE_TENSOR64
  64-bit Edge Tensor instruction.
  Sent to edge_accel_pipe.
  Also creates a retire-visible token in scalar program order.

EDGE_TENSOR64_DMA
  Edge Tensor instruction for DMA start/sync commands.
  Sent to edge_accel_pipe and then to edge_dma_engine.
  Uses GPR capture slots for source, destination, and length operands when the
  encoding names scalar registers.

EDGE_TENSOR64_OP
  Edge Tensor instruction for tensor.set*, tensor.wld*, tensor.start, or
  tensor.sync commands.
  Sent to edge_accel_pipe and then to edge_tensor_unit.
  Uses scalar capture slots for pointer, count, scale, or parameter operands
  when the encoding names scalar registers.

EDGE_TENSOR64_WLD_WAIT_DMA
  Edge Tensor instruction that describes how many bytes a following or attached
  tensor.wld command must wait for from an older DMA command before WLD can
  issue. This is a tensor/DMA-pipeline dependency, not a scalar CSR polling
  loop.

CONTROL_DEP
  Queue pseudo entry for a conditional branch, jump, or other scalar control
  boundary that can redirect younger vector or tensor work. This is not a scalar
  retire-visible pseudo instruction and does not capture an operand value. The
  predecoder allocates a virtual control dependency id, similar to a
  lightweight rename slot, so younger vector/tensor commands know which scalar
  control result must become ready before issue.
```

## Outputs To Scalar Pipe

```text
scalar_valid
scalar_ready
scalar_pc
scalar_len
scalar_inst
scalar_is_pseudo
scalar_pseudo_kind
scalar_seq_id
scalar_epoch
scalar_gpr_src_mask
scalar_fpr_src_mask
scalar_n_src_gpr
scalar_alloc_n_capture
scalar_n_capture_id
scalar_wait_vector_done
scalar_wait_tensor_done
```

Pseudo kinds:

```text
VEC_TOKEN
  Retire-order token for one Edge Vector instruction. This is the retire-visible
  entry for the vector command, even when the command waits for scalar capture
  slots.

TENSOR_GPR_HOLDER
  Internal scalar-order snapshot write for a Tensor/DMA command with GPR
  operands. It does not allocate the scalar RTU.

TENSOR_SYNC_JOIN
  Scalar half of `tensor.sync` or `dma.sync`. It shares sequence/epoch with the
  accel half, allocates the scalar RTU, and waits for the accel sync-done event.

VECTOR_SYNC
  User-visible `vector.sync` instruction. The predecoder emits this instruction
  to both the scalar retire path and the accelerator command queue with the same
  sync id. It waits until older vector commands are complete before scalar
  retirement proceeds past the sync point. This mirrors `tensor.sync` and is
  mainly intended for explicit software/debug ordering, such as reading DTCM
  results back through scalar code for printing.
```

Operand readiness is not represented by inserted pseudo instructions. Scalar
operand and `n` dependencies are tracked through IFU-local capture ids and
producer tags; the vector/tensor command queues wait for scalar producer/WBT
sideband payloads before issue. The current contract is a small generic 64-bit
capture-id pool, not a GPR/FPR shadow register file:

```text
capture_id[CAPTURE_ID_WIDTH-1:0]  // default 8 entries, 3-bit id
src_reg[4:0]                      // provenance/debug only
domain/bank                       // legacy sideband, driven/treated as zero
```

The predecoder/decoder owns this classification. Execution units receive the
capture id sideband and do not re-derive scalar provenance from opcode. Vector
registers are architectural VRF entries and are never renamed.

## Outputs To Redirect Control

```text
loop_predict_valid
loop_predict_target
loop_predict_fallthrough
loop_predict_seq_id
loop_predict_epoch
```

The first predictor is intentionally static. When the accepted scalar token is a
32-bit conditional branch and its decoded B-immediate target is less than the
branch PC, the predecoder predicts taken and emits `loop_predict_*` in the same
cycle that the branch is accepted. Direct `jal` also emits through this path
because its J-immediate target is known in predecode; this prevents the
fallthrough packet from entering the scalar pipe while still letting the `jal`
itself retire normally and write its link register.

The predictor also covers scalar issue-window replay and scalar token bypass,
so a queued backward branch or direct `jal` still predicts when it later issues
through lane 0. Forward conditional branches are predicted not-taken by
omission. `jalr` does not use this helper because its target depends on a GPR
value.

`loop_predict_fallthrough` records `control_pc + 4` so
`edge_pc_redirect_ctrl` can correct the final loop-exit case when the static
backward-taken prediction is wrong.

## Outputs To Vector Pipe

```text
vec_valid
vec_pc
vec_inst64
vec_seq_id
vec_epoch
vec_needs_gpr_operands
vec_needs_fpr_operands
vec_uses_gpr_n
vec_n_src_gpr
vec_n_capture_id
vec_operand_spec
vec_capture_src_kind
vec_capture_id_list
vec_capture_ref_count

vec_control_dep_valid
vec_control_dep_seq_id
vec_control_dep_epoch
vec_control_dep_id
vec_control_dep_kind

vec_control_wait_valid
vec_control_wait_dep_id
```

The accelerator pipe may accept the command before scalar operands are ready, but it
must not issue that command until the required scalar rename/capture slots have
become ready.

The current RTL exposes the raw Vector proof-slice command fields as:

```text
accel_command_valid
accel_command_is_tensor
accel_command_inst64
accel_command_seq_id
accel_command_epoch
accel_command_capture_count
accel_command_n_capture_valid
accel_command_n_capture_id
accel_command_n_capture_bank
accel_command_n_producer_tag
accel_command_n_src_gpr
accel_command_base_capture_valid
accel_command_base_capture_id
accel_command_base_capture_bank
accel_command_base_producer_tag
accel_command_base_src_gpr
accel_command_ready
accel_decode_is_accel
accel_decode_needs_base_gpr
```

`accel_command_valid` is a one-cycle pulse after the required local capture
bookkeeping completes and `accel_command_ready` is high. If a
no-base Vector/Tensor command would emit directly from the token window,
`accel_command_ready` also backpressures token consumption so the command pulse
cannot be dropped. `accel_command_is_tensor` marks that the 64-bit command
belongs to the Tensor stream even though it uses this first-slice accel
sideband. The command carries capture ids plus bank bits, not scalar values. A
downstream vector or tensor queue uses `{src_gpr, producer_tag, epoch}` to match
scalar producer/WBT sideband payloads. For the current vector `n/base`
operands, domain/bank sideband is kept at zero for compatibility.

## Outputs To Accelerator Pipe

```text
tensor_valid
tensor_pc
tensor_inst64
tensor_seq_id
tensor_epoch
tensor_kind              // DMA or Tensor
tensor_subop             // dma.start/sync, tensor.set*/wld*/start/sync/etc.
tensor_needs_gpr_operands
tensor_needs_fpr_operands
tensor_operand_spec
tensor_capture_src_kind
tensor_capture_id_list
tensor_capture_ref_count

tensor_control_dep_valid
tensor_control_dep_seq_id
tensor_control_dep_epoch
tensor_control_dep_id
tensor_control_dep_kind

tensor_control_wait_valid
tensor_control_wait_dep_id
```

The accelerator pipe may accept DMA/Tensor/ACTU commands before scalar operands are ready,
but it must not apply tensor descriptor writes, accept `tensor.start`, accept
`dma.start`, or complete a sync command until the required capture slots are
ready and the protecting scalar control dependency has resolved correct.
Before the scalar side computes the actual branch/jump outcome, tensor progress
is limited to queue and bookkeeping fill, matching the vector-side no-steal-run
rule.

The predecoder assigns all capture ids. Instruction-pipeline entries carry
extra metadata for scalar/vector/tensor operand sources. The target scalar
operand metadata is:

```text
operand_valid[3:0]
operand_is_write[3:0]
operand_scalar_domain[3:0]  // 0 = GPR, 1 = FPR
operand_capture_id[3:0]     // generic capture-pool id when operand is captured
operand_reg[3:0][4:0]       // rd, rs1, rs2, rs3 architectural index
```

Only scalar operands use this sideband. VR operands keep their architectural
`vd/vs1/vs2/vs3` names and are protected by vector queue ordering and VR WBT,
not rename.

When a vector or tensor command uses a captured scalar operand, its queue entry
records the corresponding generic `capture_id`. Legacy domain/bank bits remain
on some RTL ports for compatibility, but they are driven and treated as zero by
the small-pool implementation. When a scalar producer instruction completes,
its writeback/forwarding metadata tells the downstream queue which producer
tuple can be filled and marked ready.

The predecoder also specifies capture-slot lifetime. It creates a capture
mapping only when the current scalar GPR/FPR producer version has at least one
Edge Vector or Edge Tensor consumer. Pure scalar uses do not allocate
capture slots. For captured producer versions, the predecoder maintains an
active mapping:

```text
{domain, src_reg, producer_tag} -> capture_id
```

For vector or tensor commands that name the same scalar producer version, later
predecode windows may reuse the same capture id while the original
architectural scalar register has not been overwritten by a new scalar producer. The
predecoder extends the slot lifetime by incrementing that capture slot's local
reference count once per vector/tensor command consumer.

When the scalar stream overwrites that architectural scalar register, the predecoder
closes the old mapping. New vector/tensor commands after the overwrite allocate
or use a capture id for the new producer version if they need that value. The
old slot remains live only for the consumers that already named it, and is
released when its reference count reaches zero after those consumers issue or
are killed by redirect. Scalar overwrite does not release the old slot by
itself.

The pool is deliberately small. Four to eight live 64-bit captures are intended
to cover vector load/store addresses, `rs4(n)`, `vx` scalar operands, and future
scalar-tensor parameter exchange without building a full physical-register
rename engine.

For each predicted scalar branch/jump or other scalar control boundary that can
redirect younger work, the predecoder also allocates vector-visible and
tensor-visible virtual control dependency ids and emits matching `CONTROL_DEP`
pseudo entries to the vector and tensor command queues. The id behaves like a
lite-rename slot with no data operand: it only carries resolved/not-resolved
state and the branch result. Younger vector and tensor commands receive the
matching control wait id and must wait until the matching `CONTROL_DEP` is
filled by scalar branch resolution.

The scalar branch/control result is one logical dependency. Vector and tensor
queues may each hold their own `CONTROL_DEP` entry copy for local lookup, but
those copies use the same logical `branch_control_dep_id` and are resolved by
the same scalar/control broadcast. Do not create separate vector and tensor
branch outcomes for the same scalar branch.

The pseudo/control entry itself does not compute or consume an operand value.
It only creates the blocking dependency. When the scalar branch resolves, the
scalar/control side writes the result into the virtual control dependency:

```text
branch_control_write_valid
branch_control_dep_id
branch_control_pred_correct
branch_control_redirect_valid
branch_control_redirect_pc
```

If the prediction was correct, the dependency becomes ready and younger vector
commands may issue. If the prediction was wrong, scalar redirect/kill flushes
the younger vector/tensor commands and capture slots by epoch/seq_id.

## Scalar Operand Capture Rule

When an Edge Vector or Edge Tensor instruction needs scalar values, the
predecoder does not insert a blocking scalar operand pseudo instruction.
Instead, it allocates lightweight rename/capture slots and records which scalar
producer version will fill each slot:

```text
decode vector/tensor instruction:
  identify required scalar operands
  allocate operand_capture_id entries
  bind each capture entry to the current scalar producer version

scalar producer writeback/forwarding:
  copies the produced value into the matching capture entry
  marks operand_capture_ready
  releases the scalar-side dependency when no younger scalar use still needs it

vector/tensor issue:
  waits for every required capture entry to be ready
  consumes captured values, not live scalar register files
```

This keeps scalar execution from stalling just to feed vector operands. After
the needed value is captured, scalar code can continue computing the next loop's
index, address, or scalar parameter while the vector command waits independently.

Predecoder provides the allocation and operand specification; scalar
writeback/forwarding provides producer readiness; vector and tensor issue wait
for the captured producer payload. The current RTL no longer exposes external
lite alloc/ref-inc ports.

For the first operand of an accepted vector/tensor command:

```text
if active mapping for {domain, src_reg, producer_tag} exists:
  reuse mapping_capture_id
  increment local refcount
else:
  allocate the first free generic capture slot
  initialize local refcount to 1
```

The predecoder mirrors consumer lifetime through:

```text
consumer_release_valid
consumer_release_capture_id
```

This input represents a downstream issued or killed command accounting event.
It lets the predecoder free its local slot bookkeeping after the final consumer
has been accounted for.

The producer version comes from a lightweight predecoder dependency sampling
window. The first implementation may encode it as `{domain, src_reg,
producer_seq_id}` and may share decoded loop/update context with branch
prediction. Captured operand values are supplied later through scalar
producer/WBT sideband.

## GPR `n` Rename/Capture Rule

The simplified scalable-vector loop model binds most vector instructions to a
GPR `n` operand:

```c
for (int n = element_num; n > 0; n -= vl) {
  vld(..., n);
  valu(..., n);
  vst(..., n);
}
```

Every vector instruction in the loop uses the `n` value for the current
iteration. The predecoder/vector decode must derive which scalar GPR supplies
`n` from the vector instruction format.

The captured value is the vector command's `n_capture` value. It is distinct
from `n_next`, the scalar loop-control value computed after the decrement for
the next iteration and tested by the following scalar conditional branch.

`n` is not read by the accelerator pipe from the scalar GPR file at issue time.
Instead, `n` uses the same narrow rename/capture contract:

```text
decode vector instruction:
  derive n_src_gpr
  allocate n_capture_id for the vector command
  bind n_capture_id to the current scalar producer version of n_src_gpr

when scalar producer writes or forwards n_src_gpr:
  copy that value into the n_capture_id slot
  mark the capture slot ready
  release the scalar GPR dependency for later scalar work

vector issue:
  wait for producer sideband payload
  use the captured n value, not the live scalar GPR
```

This is intentionally similar to a very narrow register-rename path. After the
`n` value is copied into the capture slot, scalar code may continue and update
the same architectural GPR for the next loop iteration. Older vector commands
still use their captured `n` copy.

The accelerator lane clamps the captured value against `vl`:

```text
active_elems = clamp(n, 0, vl)
```

The same `n` value is also useful to scalar loop prediction. Current LLVM output
for the plain C loop updates `n_next` and then uses a scalar conditional branch
such as `bgtz n_next, loop_head`. The predictor should use that update/branch
pattern when the scalar update is available; before then it may only
optimistically speculate from the captured iteration value.

## Edge Vector Base Format

The ISA draft lives in:

```text
doc/inst_spec/edge_vector.md
```

The base 64-bit layout is:

```text
inst64[31:0]:
  scalar-like RISC-V field positions plus opcode7 length marker

inst64[63:32]:
  dtype16, rs4, reserved bits, opcode8
```

For the current Vector template:

```text
inst64[6:0]   = 7'b0111111
inst64[19:15] = rs1/base GPR for vload/vstore address generation
inst64[39:32] = opcode8, stream bit plus Vector operation class
inst64[47:43] = rs4, interpreted by Edge Vector as n_src_gpr
inst64[63:48] = dtype16
```

The predecoder uses `inst64[6:0]` for 64-bit length and high-word
`inst64[39:32]` for the Vector/Tensor stream split. It uses `inst64[47:43]` to
allocate or reuse the GPR capture slot for `n` on every Vector instruction. For
Vector load/store classes, identified by `opcode8[6:0] == LOAD/STORE`, it also
uses `inst64[19:15]` to allocate or reuse a GPR capture slot for the address
base. Full `opcode8/dtype16` legality decode belongs to `edge_accel_pipe`;
DMA/Tensor sub-op decode belongs to `edge_accel_pipe`.

For the current Tensor template:

```text
inst64[6:0]   = 7'b0111111
inst64[19:15] = rs1 scalar operand for pointer or run-count setup
inst64[39:32] = {1'b1, tensor_subop[6:0]}
```

Tensor commands with `rs1 != x0` allocate or reuse one GPR capture slot from
`inst64[19:15]`. Tensor commands with `rs1 == x0`, such as `tensor.start` and
`tensor.sync`, do not allocate a capture.

Raw Vector capture is sequenced:

```text
accept raw 64b Vector instruction
capture or ref-inc n_src_gpr from rs4
if LOAD/STORE:
  capture or ref-inc base_src_gpr from rs1
emit accel_command_* metadata
```

If `rs4` and `rs1` name the same live scalar producer, the second operand reuses
the same capture id and increments the reference count for the second logical
consumer.

## Scalar ISA Profile

The scalar stream follows:

```text
RV64IM + floating point
no compressed instructions
no atomic instructions
```

Therefore the first frontend only tracks two instruction lengths:

```text
32-bit scalar
64-bit Edge Vector or Edge Tensor
```

## Ordering Rules

- Every emitted scalar instruction or pseudo instruction receives a program-order
  sequence id.
- Every emitted vector command receives the same sequence id as its matching
  retire-visible `VEC_TOKEN`.
- Every emitted Tensor/DMA sync command receives the same sequence id as its
  matching scalar `TENSOR_SYNC_JOIN`. Non-sync commands remain accel-local and
  have no scalar retire token.
- Every emitted `VECTOR_SYNC` receives one sync id shared by the scalar retire
  entry and the vector-side sync barrier entry. The scalar side waits for the
  vector-side ack before retiring the sync and allowing subsequent scalar DTCM
  inspection code to proceed.
- A vector command that uses `n` also receives an `n_capture_id` allocated at
  predecode/rename time through the normal capture-slot mechanism.
- Scalar operand capture slots are sideband readiness state. They are not
  separate retire-visible pseudo instructions.
- Branch/control prediction state is represented by an epoch.
- Redirect/kill drops all scalar pseudo entries, vector/tensor commands, operand
  capture slots, and `n` capture entries younger than the redirect epoch/sequence
  boundary.

## First Implementation Simplification

The first RTL slice uses scalar-side speculation only. It may either stop
vector/tensor predecode after an unresolved branch or enqueue predicted-path
commands with epoch tags and a virtual control dependency id. The vector and
accelerator pipes must not issue commands waiting on that id until scalar/control
resolution fills the dependency. Tensor commands in this state may only occupy
queue/bookkeeping entries; descriptor mutation, DMA acceptance, tensor start,
WLD issue, sync completion, DTCM/DRAM movement, and tensor done reporting all
wait for scalar control resolution. Later versions can allow deeper speculative
vector or tensor execution if they add the required VR buffering, descriptor
rollback, DMA rollback, or rename machinery.

The first RTL slice does not implement architectural trap, interrupt, or debug
flows. Verification is simulation-driven: scalar `.s`/`.c` tests set up data,
run vector/tensor operations, and compare results. Unsupported internal states
should fail simulation in the detecting RTL or testbench with an assertion or
`$fatal`.

## Local Tests

```text
src/test-e3/edge_predecoder/edge_predecoder_accel_decode_tb.v
src/test-e3/edge_predecoder/edge_predecoder_window_bundle_tb.v
src/test-e3/edge_scalar_pipe/edge_scalar_vector_rename_cross_tb.v
```

The predecoder local tests prove:

- first vector user of `x3` allocates capture slot 0 from the small pool
- a second user of the same `x3` producer reuses slot 0 and increments refcount
- scalar overwrite of `x3` closes the old mapping without freeing slot 0
- a later user after overwrite allocates a different capture slot while the old
  slot is still live
- consumer release bookkeeping frees the old slot after both old users are
  accounted for
- redirect flush clears local predecoder mappings and slot ownership

The vector-decode local test proves:

- the 64-bit length marker plus low-byte `opcode8` classifies the raw 64-bit
  instruction as an Edge Vector command
- `rs4` is captured as `n_src_gpr`
- Vector load captures `rs1` as the base GPR operand
- a second command using the same scalar producer versions emits lite ref-inc
  handshakes instead of allocating duplicate capture slots
- Vector compute commands carry `n` but do not allocate a base-GPR capture

The scalar/vector rename cross test proves:

- an older live `x10` capture can keep slot 0 occupied
- a 96-bit `32+64` window containing `addi x10` followed by a vector `rs4=x10`
  can allocate a new generic capture slot for that same-window producer without
  hand-written sideband
- the following scalar-only window containing `addi x10` is accepted on the
  next scalar issue cycle while the vector queue is still holding the previous
  captured consumer
- the vector queue receives the first addi value through the captured `n` slot
  and consumes that slot explicitly

`edge_predecoder_window_bundle_tb.v` has been migrated to typed-token stimulus.
It proves:

- vector-only token setup still allocates an `rs4/n` capture
- `scalar+vector` token bundles rename same-bundle scalar producers into vector
  captures
- `vector+scalar` token bundles do not let the earlier vector consume the later
  scalar definition
- vector load tokens can capture both `rs4/n` and renamed scalar base GPR
  operands
- tensor tokens are accepted on the 64-bit accel sideband, assert
  `accel_command_is_tensor`, and capture `rs1` when it is nonzero
- tensor `rs1=x0` commands issue without allocating a scalar capture
- scalar downstream backpressure accepts scalar tokens into the scalar issue
  window instead of blocking tokenizer acceptance
- `alu+alu` uses consume feedback: low-water windows may buffer token 1, while
  high-water windows consume only token 0 so token 1 remains tokenizer head
- `load+load` can present the second scalar as a lane-1 candidate and consume
  both scalars in one cycle

The maintained frontend target is a 128-bit fetch packet with tokenizer typed
tokens feeding this predecoder boundary. The next frontend target is moving
vector and mixed scalar/vector bundles through the same tokenized issue window
specified in `edge_token_issue_window.md`.
