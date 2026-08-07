# edge_scalar_snapshot

`edge_scalar_snapshot` is the scalar-side holder for tensor GPR operands.
It executes a predecoder-inserted pseudo instruction in scalar issue order,
reads one architectural GPR selected by the pseudo payload, writes that value
into a tensor snapshot target, and then retires the pseudo.

Tensor commands that require GPR operands must consume the captured snapshot
fields from their tensor queue entry. They must not read the scalar GPR file
directly and must not fall back to producer-history lookup for this path.

## Ownership

The predecoder owns pseudo insertion and target assignment. The scalar pipe owns
GPR dependency checks and supplies ready/value bits to this block. The tensor
command queue owns the snapshot storage associated with each tensor command
entry.

## Parameters

- `SEQ_ID_WIDTH`: retire/order id width.
- `EPOCH_WIDTH`: redirect epoch width.
- `REG_INDEX_WIDTH`: architectural GPR index width.
- `VALUE_WIDTH`: GPR value width.
- `SNAPSHOT_TARGET_WIDTH`: tensor snapshot target width. Production overrides
  this to 3 for the eight-entry tensor queue.

## Pseudo Payload

The pseudo carries the original low 32-bit instruction word so the standard
RISC-V register fields remain the source selectors:

- `inst[19:15]`: `rs1`
- `inst[24:20]`: `rs2`
- `inst[11:7]`: `rd`

`source_mask` selects one field to capture:

- `source_mask[0]`: capture `rs1`
- `source_mask[1]`: capture `rs2`
- `source_mask[2]`: capture `rd`

The active accelerator ABI permits `000` for a join with no operand and the
three one-hot selections above. Multi-bit masks are invalid and stall.

`snapshot_target` is assigned by the predecoder when it forks the tensor command
and holder pseudo. The same target is stored in the tensor command queue entry.
The target is the low target-width bits of the paired tensor command's `seq_id`. It is a
circular snapshot slot id, not a queue pointer observed after enqueue.

## Handshake

Inputs:

- `issue_valid`: holder pseudo is at scalar issue.
- `issue_inst`: low 32-bit instruction word containing `rd/rs1/rs2`.
- `issue_seq_id`, `issue_epoch`: retire identity for the pseudo.
- `source_mask`: selected GPR fields to snapshot.
- `snapshot_target`: tensor snapshot slot id.
- `rs1_ready`, `rs2_ready`, `rd_ready`: scalar pipe dependency result for each
  selected source.
- `rs1_value`, `rs2_value`, `rd_value`: scalar GPR values.
- `snapshot_ready`: tensor snapshot sink can accept a write.
- `redirect_kill_valid`: redirect flush kills the current issue attempt.

Outputs:

- `issue_ready`: asserted when the selected source is ready and the snapshot
  sink is ready.
- `snapshot_valid`: one-cycle snapshot write pulse on successful issue.
- `snapshot_target_o`: target copied from the pseudo.
- `snapshot_operand_valid`: the holder carries one captured GPR.
- `snapshot_operand_reg`, `snapshot_operand_value`: selected register identity
  and captured value.
- `retire_valid`, `retire_seq_id`, `retire_epoch`: pseudo retirement pulse.

`snapshot_valid` and `retire_valid` fire together. A holder pseudo is complete
only after the snapshot sink accepts the write.

## Rules

- Unselected sources do not block issue. Multi-source masks do not issue.
- `x0` may be selected; the scalar pipe supplies the architecturally correct
  zero value and readiness.
- Redirect kill suppresses `issue_ready`, `snapshot_valid`, and `retire_valid`.
- The block is stateless in the first implementation. Backpressure is represented
  by `snapshot_ready`.
- Tensor setup join pseudos can share this block when their source mask and
  retire semantics are represented explicitly by the scalar pipe.

## Tests

Module-local tests live in `src/test-e3/edge_scalar_snapshot`:

- `edge_scalar_snapshot_basic`: verifies each one-hot source, target pass-through,
  source stalls, sink backpressure, and redirect kill suppression.
