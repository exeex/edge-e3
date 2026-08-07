# edge_accel_pipe.v

## Current Implementation

`edge_accel_pipe.v` currently implements the direct-issue Tensor/DMA/ACTU/CMPU control
slice. The production core selects `COMPACT_CMD_INPUT=1` and supplies canonical
`cmd_opcode8` plus `cmd_imm8`; the full 64-bit instruction is not transported
through the production pipe control path. A legacy `cmd_inst64` mode remains
temporarily for module tests. The pipe waits for a scalar snapshot when needed
them, and drives either the command pins used by `edge_tensor_unit` or
the core DTCM DMA start/sync sideband.

Implemented commands:

- `dma.start`
- `dma.sync`
- `dma.setn`
- `dma.setx`
- `dma.sety`
- `dma.setentry`
- `dma.setsrc`
- `dma.settar`
- `tensor.setcsr`
- `tensor.wld`
- `tensor.wld_t`
- `tensor.wld_circular`
- `tensor.wld_t_circular`
- `tensor.sld`
- `tensor.wsld_circular`
- `tensor.setin`
- `tensor.setout`
- `tensor.setpsum`
- `tensor.setn`
- `tensor.start`
- `tensor.start_scale`
- `tensor.sync`
- `actu.setcsr`, `actu.setin`, `actu.setout`, `actu.setn`,
  `actu.setscalar`, `actu.start`, and `actu.sync`
- `cmpu.setcsr`, `cmpu.setlhs`, `cmpu.setrhs`, `cmpu.setmask`,
  `cmpu.setout`, `cmpu.setn`, `cmpu.start`, and `cmpu.sync`
- `accel.getcsr`

Pointer commands compare the captured scalar payload against the configured
40-bit DTCM base/mask window. A hit is converted to an internal 128-bit word
offset by subtracting `edge_dtcm_base`; a non-hit retains the legacy low-bit
test behavior. This keeps Tensor, ACTU, and CMPU pointer setup relocatable with the
same window used by scalar LSU and DMA.
`tensor.setn`, `actu.setn`, and `cmpu.setn` always use the captured GPR payload low 16 bits;
there is no immediate form. `tensor.setcsr` decodes
`dtype` and `wtype` from canonical `imm8[3:0]` and `imm8[7:4]`.

CMPU uses subops `0x27` through `0x2e`. Its pointer/count setup commands each
consume one scalar snapshot, while setcsr/start/sync consume none. Mode is
carried in canonical `imm8[3:0]`. Subop `0x2f` is `accel.getcsr`:
canonical `imm8[3:0]` selects the accelerator CSR and `imm8[4]` carries the
depth-2 reverse-snapshot ID. CSR IDs 0..3 return CMPU max, argmax, min, and
argmin; ID 4 returns ACTU's retained FP32 exp sum. The pipe waits for the owner
to become idle and for the slot to be writable, then writes the zero-extended
value atomically with command acceptance. Other CSR IDs decode illegal.

DMA setup and launch use only single-GPR snapshots:

```text
dma.setsrc low rs1 = source pointer GPR
dma.settar low rs1 = target pointer GPR
dma.start  low rd  = len_bytes or circular ring-capacity GPR
```

`dma.setsrc`, `dma.settar`, `dma.setn`, `dma.setx`, `dma.sety`, and
`dma.setentry` each consume one scalar snapshot and update the local descriptor.
`setx` and `sety` pack axis maximum in bits `[63:32]` and source stride in
bits `[31:0]`. `dma.start` canonical `imm8[1:0]` selects `circular` and
`use_xy`. When `use_xy=1`, the 2D shape comes from the descriptor CSRs instead
of low-parcel `rd`. In circular XY mode, `setn` is one fragment's byte length,
`setentry` is the completed-byte threshold for publishing one ring entry, and
low-parcel `rd` is the ring capacity in entries. `dma.start` waits for its single snapshot payload and
the selected DMA target readiness before pulsing its sideband. `dma.sync`
waits for direct, strided, and circular DMA work to become idle.

The split descriptor setup deliberately keeps every accelerator command at no
more than one GPR snapshot so command and snapshot queues can deepen without a
DMA-only three-value entry.

Readiness is target-driven: setup, pointer, weight-load, and start commands
wait for `tensor_cmd_ready`; `tensor.sync` waits for `tensor_sync_stall` to
clear. ACTU and CMPU use their corresponding command/start readiness and shared
busy-backed sync stall inputs. DMA commands wait for the DMA sideband
readiness/idle inputs. Accepted
commands other than `tensor.start` pulse `tensor_done_valid` with the input
sequence and epoch. A start carries its sequence and epoch into the tensor unit
and completes through the dedicated start-retire path at actual launch. Captured
commands also pulse `capture_consume_valid`. The pipe exposes only one snapshot
valid/value input; no command consumes a base or rd sideband operand.

This slice is intentionally not the final queue implementation described below:
it has no multi-entry tensor stream queue, no redirect kill, and no control
dependency table yet. Those pieces should be added on top of this command
boundary instead of changing the software encoding again.

Covered by:

- `hw_edge_accel_pipe_decode_verilator`
- `edge_soc_software_cmpu_smoke_verilator`, which covers CMPU instruction
  decode, scalar pointer snapshots, shared IO, DTCM output, and sync end to end.
- `hw_edge_accel_pipe_actu_unit_verilator`, which proves ACTU descriptor decode,
  sync stalling, shared DTCM streaming, and BF16 output packing end to end.
- `hw_edge_accel_pipe_stream_shell_verilator`, which drives
  `edge_tensor_unit` and its mock DTCM lanes through legacy 64-bit test
  commands issued into `edge_accel_pipe`.
- `hw_edge_accel_queue_bridge_verilator`, which carries a compacted Tensor
  command through `edge_accel_cmd_queue`, obtains the scalar operand
  from producer/WBT sideband, and issues it into `edge_accel_pipe`.

## Purpose

Command queue and control wrapper for the Edge Tensor stream.

`edge_accel_pipe` is the accelerator command boundary that sits between
`edge_predecoder`, `edge_dma_engine`, `edge_tensor_unit`, and scalar snapshot
sideband. It is not the tensor arithmetic datapath itself. The
datapath and tensor-local buffers live behind `edge_tensor_unit`; explicit
DRAM/DTCM movement lives behind `edge_dma_engine`.

The pipe owns tensor-stream ordering, scalar operand readiness, control
dependency waits, descriptor-write visibility, DMA start/sync issue, Tensor
start/sync issue, accel-local done reporting, and sync acknowledgement to the
scalar join path.

## Inputs From Predecoder

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

The predecoder gives every tensor-stream command a program-order `seq_id`. For
sync commands it gives the scalar join pseudo the same sequence and epoch. A
command may be queued before scalar operands or scalar control dependencies are
ready, but visible tensor or DMA side effects must wait for the readiness rules
below.

Before the scalar side has resolved how a protecting branch/jump actually
redirects, the tensor side may only fill command queues and bookkeeping state.
It must behave like the accelerator lane: queued tensor entries can exist, but no
tensor or DMA work may run ahead of scalar control resolution.

## Inputs From Scalar Producer/WBT Sideband

```text
producer_valid
producer_reg
producer_tag
producer_value
producer_epoch
```

Tensor commands that name scalar GPR/FPR operands consume those values only
through captured producer payloads. The accelerator pipe must not read live scalar
GPR/FPR files or scalar bypass buses directly.

## Control Dependency Entries

The accelerator pipe tracks queue pseudo entries allocated by the predecoder:

```text
CONTROL_DEP
  seq_id
  epoch
  dep_id
  resolved
  pred_correct
```

`CONTROL_DEP` is not a tensor instruction and is not retire-visible. It is a
virtual control dependency for a scalar branch, jump, or other scalar-control
boundary that can redirect younger tensor work. Younger tensor commands may be
queued with `tensor_control_wait_dep_id`, but they are not issue-eligible until
the matching dependency is resolved and predicted-correct.

Scalar/control resolution writes:

```text
branch_control_write_valid
branch_control_dep_id
branch_control_pred_correct
branch_control_redirect_valid
branch_control_redirect_pc
```

The scalar branch/control result is one logical dependency. The predecoder may
place a copy of that dependency entry in both the vector and tensor queues, but
the scalar/control side broadcasts the same `branch_control_dep_id` result to
all queues that hold a matching copy. This keeps vector and tensor waiting on
the same scalar decision without inventing separate branch outcomes.

If prediction was correct, waiting tensor commands may become issue-eligible.
If prediction was wrong, global redirect/kill removes younger tensor commands,
pending descriptor updates, DMA starts, tensor starts, and capture references by
epoch/sequence id.

Until the scalar branch/control result is known, tensor queue filling is the only
allowed tensor-side progress. The following are not queue filling and must wait:

- Applying `tensor.set*` updates to the pending descriptor.
- Accepting `dma.start` into `edge_dma_engine`.
- Completing `dma.sync`.
- Recording or satisfying `tensor.wld_wait_dma`.
- Issuing `tensor.wld` / `tensor.wld_t`.
- Snapshotting or accepting `tensor.start`.
- Completing `tensor.sync`.
- Sending DTCM requests or external-memory side effects.
- Reporting `tensor_done_valid` for the protected command.

## Issue Eligibility

A tensor-stream command may issue to DMA or tensor-unit side effects only when:

- Required scalar capture payloads are ready.
- Required control dependency is resolved and predicted-correct.
- The command epoch is still current and not younger than an active redirect
  kill boundary.
- The selected target, `edge_dma_engine` or `edge_tensor_unit`, can accept it.
- Earlier tensor-stream commands that must be observed before this command have
  either issued or updated the required local state.

The first slice is locally single-issue for the tensor side:

```text
at most one Edge Tensor DMA/Tensor command issue per cycle
```

This local single-issue rule does not block scalar or vector issue in the same
cycle when those sides are independently ready.

## DMA Commands

DMA commands are selected by `tensor_kind == DMA` and tensor subop fields:

```text
dma.setn(n_bytes)
dma.setx({x_max, x_stride_bytes})
dma.sety({y_max, y_stride_bytes})
dma.setentry(entry_bytes)
dma.start(src, dst, legacy_len_or_tile_count, mode_imm)
dma.sync()
```

For `dma.start`, the accelerator pipe presents operands to `edge_dma_engine` only
after snapshot and control dependencies are ready:

```text
dma_start_valid
dma_start_ready
dma_src_addr
dma_dst_addr
dma_len_bytes
dma_start_x
dma_start_y
dma_start_use_xy
dma_start_circular
dma_seq_id
```

`dma.start` is accel-local after command acceptance; it does not allocate a
scalar RTU entry. DMA progress is independent until an explicit `dma.sync`
orders on completion.

For `dma.sync`, the accelerator pipe waits for the DMA engine completion condition:

```text
dma_sync_valid
dma_sync_done
```

The accel half of `dma.sync` acknowledges its scalar join only when DMA
completion is visible.

## Tensor Commands

Tensor commands are selected by tensor subop fields:

```text
tensor.setcsr
tensor.wld
tensor.wld_t
tensor.sld
tensor.wsld_circular
tensor.setin
tensor.setout
tensor.setpsum
tensor.setn
tensor.wld_wait_dma
tensor.start
tensor.start_scale
tensor.sync
```

The accelerator pipe owns when descriptor writes become visible to the pending
descriptor. Descriptor writes may be queued while control is unresolved, but they
must not mutate the pending descriptor until the protecting `CONTROL_DEP`
resolves correct.

`tensor.start` is the batch boundary. The pipe must not allow `tensor.start` to
cross older descriptor writes. When accepted, `tensor.start` snapshots the
pending descriptor into an immutable pending or queued job descriptor for
`edge_tensor_unit`. The pipe suppresses its normal immediate done pulse for
this command and keeps launch tracking local to the accel lane. It does not
allocate or complete a scalar RTU entry and does not wait for tensor compute
completion.

`tensor.sync` is the tensor-stream completion ordering point. Its accel half
releases the matching scalar join only when older tensor jobs are complete. The core holds younger
scalar issue after an accepted `dma.sync` or `tensor.sync` until this done event;
retire ordering alone is insufficient because a younger load could otherwise
observe memory before the asynchronous operation completes. Start commands do
not assert this fence.

## WLD Waiting On DMA Progress

The accelerator pipe owns the local dependency that lets WLD wait for partial DMA
arrival without exposing a scalar-readable byte-count CSR:

```text
dma.start(weight_src, dtcm_weight_buf, weight_bytes) -> dma_tag
tensor.wld_wait_dma(dma_tag, required_bytes)
tensor.wld(dtcm_weight_buf)
```

`edge_dma_engine` may provide:

```text
dma_byte_count
dma_busy
```

The accelerator pipe matches the WLD wait command against the intended DMA progress
and releases WLD only after the required bytes are destination-visible to the
intended DTCM-side consumer.

## Done Reporting

To the accel owner, with sync done additionally acknowledging the scalar join:

```text
tensor_done_valid
tensor_done_seq_id
```

Done means command-specific accel visibility. Ordinary command done events do
not enter the scalar RTU:

- `dma.start`: accepted by DMA engine, including invalid-direction zero-byte
  no-op acceptance.
- `dma.sync`: DMA completion visible.
- `tensor.set*`: descriptor update applied to the pending descriptor.
- `tensor.wld_wait_dma`: wait dependency recorded or satisfied.
- `tensor.wld` / `tensor.wld_t`: WLD command accepted after required wait.
- `tensor.start`: tracked locally when its stored descriptor actually launches.
- `tensor.sync`: older tensor jobs complete; acknowledge the scalar join.

## Redirect/Kill Rule

```text
redirect_kill_valid
redirect_kill_seq_id
redirect_kill_epoch
current_epoch
```

On redirect:

```text
if entry.epoch == redirect_kill_epoch
   and entry.seq_id > redirect_kill_seq_id:
  kill tensor queue entry

if entry.epoch != current_epoch after redirect:
  drop stale entry before issue
```

Killed tensor commands must not apply descriptor writes, start DMA, start tensor
work, consume DTCM bandwidth, or report done. If a killed command held capture
references, those references must be released through the predecoder capture
reference-count cleanup contract.

## First Implementation Simplification

The first implementation may issue only the tensor queue head and may keep one
outstanding DMA transfer and one tensor unit job. The important first proof is
the ordering boundary:

- No visible DMA/Tensor side effect before scalar capture readiness.
- No visible DMA/Tensor side effect before the protecting `CONTROL_DEP` resolves
  correct.
- Sync acknowledgement observes command-specific completion semantics without
  routing ordinary Tensor/DMA commands through the scalar RTU.
- Redirect kills queued wrong-path tensor work and releases snapshot
  references.
