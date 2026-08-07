# edge_scalar_idu_shim.v

## Purpose

Minimal scalar IDU boundary shim for the Edge dual-stream frontend.

Pseudo kind 3 is `accel.getcsr`. It defines the low instruction's integer
`rd` in the GPR domain; bit 25 carries the reverse-snapshot ID. The scalar pipe
uses this definition for WBT, completion, and retire bookkeeping.

This block is not a full RV64 scalar IDU and does not execute instructions. It
creates the maintained Edge-side contract that `edge_predecoder` can target
when it routes normal 32-bit scalar instructions and retire-visible pseudo
tokens away from the vector/tensor streams.

The legacy C906 IDU reference boundary is:

```text
ifu_idu_id_inst_vld
ifu_idu_id_inst[31:0]
idu_ifu_id_stall
idu_*_ex1_* issue packets
*_idu_*_full backpressure
```

This shim keeps the useful shape from that boundary: a valid 32-bit scalar
instruction packet becomes one issued scalar packet plus lightweight decoded
metadata. It deliberately does not copy the full legacy `aq_idu_top` decode,
split FSMs, GPR/FPR register file, WBT, or execution-unit packets.

## Parameters

```text
PC_WIDTH        = 40
SEQ_ID_WIDTH    = 8
EPOCH_WIDTH     = 4
REG_INDEX_WIDTH = 5
PSEUDO_WIDTH    = 3
```

## Inputs

From `edge_predecoder`:

```text
scalar_valid
scalar_ready
scalar_pc
scalar_inst[31:0]
scalar_len
scalar_is_pseudo
scalar_pseudo_kind
scalar_seq_id
scalar_epoch
```

From the next scalar pipe stage:

```text
downstream_ready
```

## Outputs

Scalar issue packet:

```text
issue_valid
issue_pc
issue_inst
issue_len
issue_is_pseudo
issue_pseudo_kind
issue_seq_id
issue_epoch
```

Producer definition metadata back toward the predecoder/lite-rename owner:

```text
scalar_def_valid
scalar_def_domain      // 0 = GPR, 1 = FPR
scalar_def_dst_reg
scalar_def_seq_id
scalar_def_epoch
```

OP-FP compare, class, FPR-to-GPR move, and FP-to-integer conversion encodings
produce GPR definitions. Other maintained OP-FP encodings produce FPR
definitions. GPR `x0` suppresses a definition, while FPR `f0` remains a valid
destination and must not be suppressed by the integer zero-register rule.

Scalar control boundary metadata for future control-dependency allocation:

```text
scalar_control_valid
scalar_control_seq_id
scalar_control_epoch
```

Decode guardrail:

```text
decode_illegal
```

## Handshake

`scalar_ready` mirrors `downstream_ready`. On `scalar_valid && scalar_ready`,
the shim emits exactly one `issue_valid` pulse and any matching metadata pulses.

There is no internal skid buffer in this first slice. If the next scalar stage
cannot accept a packet, `scalar_ready` is low and all metadata outputs remain
inactive.

## Producer-Def Rule

The shim only classifies whether a scalar instruction creates a GPR or FPR
producer version for lite-rename bookkeeping.

GPR destination opcodes:

```text
LOAD, OP-IMM, AUIPC, OP-IMM-32, OP, LUI, OP-32, JALR, JAL,
SYSTEM CSR forms with funct3 != 0
```

FPR destination opcodes:

```text
LOAD-FP, MADD, MSUB, NMSUB, NMADD, OP-FP
```

`rd == x0` suppresses producer-def output. Stores, branches, fences, and plain
SYSTEM forms do not create producer-def metadata in this first slice.

This is intentionally less detailed than legacy `aq_idu_id_decd`: instructions
such as FP moves/converts that actually write GPRs rather than FPRs are deferred
until the maintained scalar decode grows beyond the shim.

## Control Boundary Rule

`BRANCH`, `JALR`, and `JAL` assert `scalar_control_valid` when accepted. This is
the future hook for `edge_predecoder` to allocate virtual control dependencies
that gate younger vector/tensor visible work.

## Pseudo Tokens

Pseudo entries such as `VEC_TOKEN`, `TENSOR_TOKEN`, and `VECTOR_SYNC` pass
through the scalar issue packet with `issue_is_pseudo = 1`. They do not create
producer-def or control-boundary metadata in this shim.

## First-Slice Non-Goals

- no GPR/FPR register file
- no source dependency readiness
- no execution-unit selection
- no instruction split FSMs such as C906 LSD/AMO/fence splitting
- no compressed instruction decode
- no raw Edge Vector/Tensor 64-bit opcode split
- no precise illegal/trap packet beyond `decode_illegal`

## Local Tests

```text
src/test-e3/edge_scalar_idu_shim/edge_scalar_idu_shim_decode_tb.v
```

The directed test proves:

- GPR producer-def for `addi`
- no producer-def for `rd == x0`
- FPR producer-def for `flw`
- no producer-def for store
- control-boundary metadata for branch
- pseudo token pass-through without producer-def
- downstream backpressure suppresses issue and metadata
