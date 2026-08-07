# edge_scalar_alu.v

## Fast/Fast and Fast/M dual issue

The second request port can drive a second independent `edge_scalar_fast_alu`
for a Fast+Fast pair, or share a cycle with RV64M for Fast+M/M+Fast. Separate
`fast_complete_*`, `fast1_complete_*`, and `m_complete_*_o` channels preserve
coincident results. Lane1 Fast completion has the same one-cycle registered
latency as lane0 Fast completion.

## Purpose

Scalar ALU wrapper for the Edge scalar pipe. This block owns the public ALU
issue/complete contract and splits the datapath into fast integer ALU,
branch/jump fact calculation, and RV64M multiply/divide submodules.

Implemented file:

```text
edge_scalar_alu/edge_scalar_alu.v
```

## Ownership

`edge_scalar_alu` owns:

- per-class issue acceptance and legacy completion packet muxing
- one-cycle fast-path completion registers
- RV64M complete arbitration against fast-path completion
- the public scalar pipe ALU interface

The datapath is split into:

- two `edge_scalar_fast_alu` instances for same-cycle ordinary RV64I/Zba pairs
- `edge_scalar_branch` for branch/JAL/JALR taken and target calculation
- `edge_scalar_muldiv` for RV64M multiply/divide/remainder calculation

The wrapper still emits the same complete packet shape as the previous
monolithic implementation, including registered control completion for branch,
`jal`, and `jalr`.
It does not own:

- instruction stream classification
- scalar GPR/FPR files
- WBT reserve or release
- lite-rename producer fills or capture refcounts
- architectural retire
- LSU, system, fence, fatal, or FPR placeholders
- IFU redirect, prediction comparison, epoch allocation, or kill broadcast

The owning pipe, currently `edge_scalar_pipe`, reads operands, checks WBT,
issues this unit, writes back the complete packet, releases WBT, publishes
`producer_valid`, and emits scalar done/retire events.

## Parameters

```text
PC_WIDTH
SEQ_ID_WIDTH
EPOCH_WIDTH
REG_INDEX_WIDTH
VALUE_WIDTH
OP_WIDTH
MUL_LATENCY
DIV_LATENCY
```

`OP_WIDTH` is currently 4 bits. Local operation encodings are module-local and
are not an ISA encoding.
`MUL_LATENCY` is passed to `edge_scalar_muldiv` for the current multiply path.
`DIV_LATENCY` is retained for interface compatibility, but the divider now uses
its internal radix-4 round count.

## Issue Interface

```text
alu_issue_valid
alu_issue_ready
alu_issue_seq_id
alu_issue_epoch
alu_issue_op
alu_issue_pc
alu_issue_rd
alu_issue_rd_bank
alu_issue_rd_valid
alu_issue_src0_value
alu_issue_src1_value
alu_issue_imm
alu_issue_branch_imm
alu_issue_jal_imm
alu_issue_funct3
alu_issue_funct7_bit5
alu_issue_funct7_is_m
alu_issue_shamt
alu_issue_shamt32
alu_issue_fast_result
alu_issue_control_valid
alu_issue_control_taken
alu_issue_control_target
```

For an accepted branch, `jal`, or `jalr`, the `alu_issue_control_*` packet is
combinational and fire-qualified in the issue cycle. It carries the resolved
taken bit and target directly to the owning pipe; this is resolved-result
forwarding, not prediction. The registered `alu_complete_control_*` packet is
retained as part of the ordinary one-cycle completion contract.

Ready is class-aware on both request ports:

```text
fast request:  ready = 1
RV64M request: ready = !m_busy
```

`mul_issue_ready_o` and `div_issue_ready_o` expose the two raw RV64M resource
capacities. The scalar pipe uses its already-decoded lane class and funct3 with
these signals before selecting which lane drives the wrapper's primary port.
The compatibility `m_issue_ready_o` remains request-class dependent and must
not be used as raw capacity. This keeps ready independent of the fire-qualified
port-selection mux and avoids a combinational issue loop.

The owning pipe must only assert `alu_issue_valid` after it has performed
instruction legality checks, WBT dependency checks, and destination reservation.
RV64M instructions are accepted into `edge_scalar_muldiv`; while it is busy,
only another RV64M request is backpressured. Either Fast datapath can continue
accepting one request per cycle. Fast and M completion pulses may coincide and
are preserved on the independent `fast_complete_*`, `fast1_complete_*`, and
`m_complete_*_o` channels. The legacy `alu_complete_*` mux remains for
compatibility and gives M priority, so new consumers must use the independent
channels when simultaneous completion matters. Fast ALU instructions calculate
their result and any control metadata in the accepted cycle, latch the complete
packet, and emit it on the next cycle.
`alu_issue_fast_result` exposes that same combinational result for a narrowly
gated lane0-fast-ALU to lane1-LSU forwarding path. It is not valid for RV64M;
the owning pipe must qualify it with decode and the lane0 issue handshake.

## Complete Interface

```text
alu_complete_valid
alu_complete_seq_id
alu_complete_epoch
alu_complete_rd
alu_complete_rd_bank
alu_complete_rd_valid
alu_complete_value
alu_complete_control_valid
alu_complete_control_taken
alu_complete_control_target
```

Fast ALU completion is a registered one-cycle-after-accept pulse. RV64M
operations complete after their configured multi-cycle latency and carry the
accepted sequence, epoch, destination register, bank, and value metadata.
Control completion remains fast-only: `alu_complete_control_valid` is asserted
for branch, `jal`, and `jalr` operations. For jumps,
`alu_complete_control_taken` is asserted.
The second Fast lane is restricted by the owning scalar pipe to non-control
integer ALU operations and reports through `fast1_complete_*`. Fast no-writeback
and control metadata use the lane0 Fast sequence/epoch directly; they do not use
the legacy Fast/M completion mux.

## Supported Operations

The owning pipe maps decoded instruction classes into local op values:

```text
OP-IMM
OP
OP-IMM-32
OP-32
LUI
AUIPC
JAL
JALR
BRANCH
ZBA
ZBA_UW
```

Unsupported or illegal instructions are rejected before entering this unit.
When `alu_issue_funct7_is_m` is set for OP/OP-32 classes, the wrapper routes
the operation to `edge_scalar_muldiv`. Divide-by-zero and signed-overflow corner
cases follow the architectural RV64M results. The current M submodule keeps the
existing short-latency multiply behavior, while divide/remainder use a radix-4
iterative divider: 32 rounds for RV64 and 16 rounds for RV64W.

`ZBA` covers XLEN `sh1add`, `sh2add`, and `sh3add`. `ZBA_UW` covers RV64
`add.uw`, `sh1add.uw`, `sh2add.uw`, `sh3add.uw`, and `slli.uw`; these
operations zero-extend `rs1[31:0]` before the shift/add operation inside
`edge_scalar_fast_alu`. They remain ordinary scalar ALU completions and do not
change the LSU memory addressing contract.

## Tests

Module-local tests:

```text
src/test-e3/edge_scalar_alu/edge_scalar_alu_rv64i_tb.v
```

The local test proves issue/complete handshake, representative RV64I/RV64M/Zba
integer results, word sign-extension, RV64M divide corner cases, branch/jump
control metadata, and the absence of WBT/lite-rename/retire coupling.
