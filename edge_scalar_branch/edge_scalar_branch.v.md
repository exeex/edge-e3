# edge_scalar_branch.v

## Purpose

Scalar branch/jump fact unit for the Edge scalar pipe. This block owns only
control-flow fact calculation:

```text
given decoded branch/jump operands, what is the actual taken bit, target PC,
and optional JAL/JALR link value?
```

Implemented file:

```text
edge_scalar_branch/edge_scalar_branch.v
```

`edge_scalar_alu` instantiates this block and registers its outputs into the
existing ALU complete/control path. The owning scalar pipe still issues
branch/jump operations through the public `edge_scalar_alu` wrapper.

## Ownership

`edge_scalar_branch` owns:

- `BRANCH` compare for `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, and `BGEU`
- `BRANCH` target calculation: `pc + branch_imm`
- `JAL` target calculation: `pc + jal_imm`
- `JALR` target calculation: `(rs1 + imm) & ~1`
- `JAL`/`JALR` link value calculation: `pc + 4`
- combinational actual control-flow facts for the accepted issue packet

It does not own:

- instruction stream classification
- scalar GPR/FPR files
- GPR source-read readiness or WBT dependency checks
- destination WBT reserve or release for JAL/JALR link writes
- producer fills for lite rename
- prediction lookup, predicted target generation, or BTB/BHT update
- IFU redirect, epoch allocation, or kill broadcast
- architectural retire ordering

The owning pipe, currently `edge_scalar_pipe`, reads operands, checks source
readiness, reserves the optional link destination, and issues the public
`edge_scalar_alu` wrapper. The wrapper uses this unit for actual control-flow
facts, writes the optional link value through its fast ALU result path, and
emits the scalar control complete packet.

`edge_pc_redirect_ctrl` consumes resolved scalar redirect requests after the
owning control layer compares actual branch results against the frontend's
predicted path.

## Parameters

```text
PC_WIDTH
SEQ_ID_WIDTH
EPOCH_WIDTH
REG_INDEX_WIDTH
VALUE_WIDTH
OP_WIDTH
```

`OP_WIDTH` is module-local and is not an ISA encoding.

Recommended local operations:

```text
BRANCH
JAL
JALR
```

## Issue Interface

```text
branch_issue_seq_id
branch_issue_epoch
branch_issue_op
branch_issue_pc
branch_issue_funct3
branch_issue_src0_value
branch_issue_src1_value
branch_issue_imm
branch_issue_branch_imm
branch_issue_jal_imm
branch_issue_rd
branch_issue_rd_valid
```

The block is purely combinational. The public wrapper owns valid/ready and
completion registers.

Source usage:

```text
BRANCH:
  src0 = rs1 value
  src1 = rs2 value
  branch_imm = sign-extended B-immediate
  rd_valid = 0

JAL:
  no GPR source is required
  jal_imm = sign-extended J-immediate
  rd_valid = rd != x0

JALR:
  src0 = rs1 value
  imm = sign-extended I-immediate
  rd_valid = rd != x0
```

## Complete Interface

```text
branch_taken
branch_target
```

`branch_taken` meaning:

```text
BRANCH:
  compare result from funct3

JAL/JALR:
  always 1
```

`branch_target` meaning:

```text
BRANCH:
  pc + branch_imm

JAL:
  pc + jal_imm

JALR:
  (src0 + imm) with bit 0 cleared
```

The optional `JAL`/`JALR` link value is calculated by `edge_scalar_fast_alu` as
`pc + 4` in the current no-compressed dualstream scalar ISA slice.

## Prediction And Redirect Split

The branch unit does not decide whether prediction was right or wrong. It only
reports actual control-flow facts.

The control layer compares the actual result against frontend prediction
metadata:

```text
actual_taken
actual_target
predicted_taken
predicted_target
```

If the predicted path was wrong, the control layer requests redirect:

```text
scalar_redirect_valid
scalar_redirect_pc
scalar_redirect_reason
scalar_redirect_seq_id
scalar_redirect_epoch
```

`edge_pc_redirect_ctrl` then chooses redirect priority, redirects IFU fetch, and
broadcasts the common kill boundary:

```text
redirect_kill_valid
redirect_kill_seq_id
redirect_kill_epoch
redirect_new_epoch
```

Younger scalar, vector, tensor, WBT, and lite-rename bookkeeping must consume
that common redirect/kill boundary. The branch unit itself does not broadcast
kill.

## Retire And WBT Rules

Branch/jump instructions still issue and retire.

`BRANCH`:

- checks GPR source readiness for `rs1` and `rs2`
- does not reserve a destination WBT entry
- completes when the actual taken/target result is available
- retires after the owning pipe has accepted the complete packet and emitted any
  needed redirect request

`JAL`:

- does not need a GPR source
- reserves GPR WBT only if `rd != x0`
- completes with both control result and optional link writeback
- retires after optional link writeback/release and redirect/control result
  emission

`JALR`:

- checks GPR source readiness for `rs1`
- reserves GPR WBT only if `rd != x0`
- completes with both control result and optional link writeback
- retires after optional link writeback/release and redirect/control result
  emission

Do not infer retire from WBT state. WBT only tracks register dependency
resources; branch retire is driven by execute completion plus the owning
control/retire ordering.

## Extraction Status

The first extraction keeps the public scalar pipe interface unchanged:
`edge_scalar_pipe` still issues branch/jump operations through
`edge_scalar_alu`. Inside that wrapper, this module owns branch/JAL/JALR taken
and target facts so Yosys can report it separately from fast ALU and RV64M
logic.

## Tests

Covered through:

```text
src/test-e3/edge_scalar_alu/edge_scalar_alu_rv64i_tb.v
src/test-e3/edge_scalar_pipe/edge_scalar_pipe_rv64i_alu_control_tb.v
```
- `JALR` clears target bit 0
- `rd = x0` suppresses link writeback
- the unit has no WBT, rename, IFU redirect, or retire coupling
