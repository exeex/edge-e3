# edge_accel_cmd_queue.v

## Purpose

`edge_accel_cmd_queue` is the eight-entry, in-order issue queue shared by Edge
accelerator, tensor, and DMA commands. A command entry keeps only canonical
`opcode8` and `imm8` control, sequence/epoch tags, one operand-needed bit, and
one matched scalar snapshot value. The full 64-bit instruction is not stored.

The native issue outputs are `issue_opcode8` and `issue_imm8`. The current
compatibility `issue_inst64` output reconstructs the meaningful instruction bits
for `edge_accel_pipe`: DMA mode, Tensor/ACTU SETCSR fields, WLD/SLD reuse,
Tensor START mode, and WSLD transpose. All other high-parcel bits are discarded.
For `accel.getcsr` subop `0x2f`, compact `imm8` preserves CSR ID in bits
`[3:0]` and reverse-snapshot ID in bit 4; compatibility expansion restores
instruction bits `[50:47]` and 52. It needs no forward GPR snapshot.

The queue is a snapshot consumer only. The former scalar producer cache,
producer history, tag matching, and forwarding option have been removed.

## Snapshot contract

The scalar lane issues `PSEUDO_TENSOR_GPR_HOLDER` to record the original
instruction's scalar operands. A snapshot is matched to an enqueued command by
the full `seq_id` and `epoch`, then copied into that command entry. An eight-slot
pending table selected by `snapshot_target` retains a snapshot that arrives
before its command; production uses the low three bits of the sequence id as the
pending-table index.

Each snapshot entry contains:

```text
valid
n_valid, n_value
```

The predecoder assigns the scalar holder pseudo and its command the same full
sequence/epoch identity. Because operands reside in command entries, two live
commands whose low sequence bits alias do not overwrite each other and do not
create input backpressure.

There is intentionally no same-cycle snapshot-write bypass. The snapshot is
clocked into the store first and becomes matchable on the following cycle.

The single snapshot value carries a count, pointer, packed shape, scalar, or
DMA start length/tile count according to `opcode8`. DMA source and target are
programmed by separate commands, so no entry needs multiple values.

A required operand that has no matching valid snapshot remains not-ready and
prevents head issue. Commands with `capture_count == 0` need no snapshot and
may issue as soon as they reach the live head and the downstream pipe is ready.

## Queue entry and issue

Each of the eight entries stores:

```text
valid, opcode8, imm8, seq_id, epoch
operand-needed bit
matched snapshot valid bit and value
```

Issue is strictly in order. `issue_valid` is asserted only when the head is
live and every requested operand-valid bit is present in that entry. A
successful `issue_ready` handshake pops the head. Input readiness depends only
on registered queue capacity; space released by a pop is visible on the
following cycle. It does not depend on command sequence/data or downstream
issue readiness, avoiding a combinational path through frontend bundle
selection.

Redirect handling persistently marks every resident entry whose epoch matches
`redirect_kill_epoch` and whose sequence id is younger than
`redirect_kill_seq_id`. Older entries remain live. Killed entries are removed
in order when they reach the head rather than compacting the queue, so a
one-cycle redirect remains effective while an older head is stalled. A command
accepted in the redirect cycle is marked by the same rule. Pending early
snapshots, including a snapshot accepted in that cycle, are invalidated when
their full sequence/epoch identity is killed so a reused physical slot cannot
resurrect wrong-path operands. The younger comparison uses modulo sequence
subtraction, including across sequence wrap.

## Interfaces

Command input:

```text
cmd_valid, cmd_ready
cmd_inst64, cmd_seq_id, cmd_epoch
cmd_n_capture_valid
```

Snapshot input:

```text
snapshot_valid, snapshot_target
snapshot_n_valid, snapshot_n_value
```

Issue output:

```text
issue_valid, issue_ready
issue_inst64, issue_seq_id, issue_epoch
issue_n_valid, issue_n_value
```

## Local tests

`test/edge_accel_cmd_queue_redirect_tb.v` covers persistent redirect kills,
redirect-cycle enqueue and snapshot invalidation, safe pending-slot reuse, and
modulo sequence comparison across wraparound.
