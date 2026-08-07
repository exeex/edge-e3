# edge_predecode_order_gate.v

## Purpose

`edge_predecode_order_gate` is the standalone issue selector for the planned
split predecoder windows:

```text
scalar32_window head0/head1
accel64_window head0
  -> edge_predecode_order_gate
  -> scalar lane0/lane1 or vector/tensor command queue
```

It is purely combinational. It does not store entries, enqueue packets, allocate
capture ids, or decode vector/tensor operands.

## Ordering Rule

Every scalar32 and accel64 entry carries a global program-order `seq_id`.
The gate compares the scalar head and accelerator head:

```text
if scalar0.seq_id < accel.seq_id:
  scalar head is oldest
else if accel.seq_id < scalar0.seq_id:
  accel head is oldest
```

Unsigned comparison is used in this first slice. Wrap-safe sequence comparison
remains deferred, matching the current predecoder proof limits.

No younger entry may bypass the oldest head. If scalar head0 is oldest but
`scalar0_ready` is low, the accelerator head waits even when its destination
queue is ready. If accel head is oldest but its vector/tensor destination is not
ready, scalar entries behind it wait.

## Scalar Pair Rule

Scalar lane1 may issue only when all of these are true:

- scalar head0 issued in the same cycle
- scalar head1 is valid
- scalar head1 is still older than the accel64 head, or no accel64 head exists
- the pair is a supported same-class pair:
  - `load + load`
  - `store + store`
  - `ALU + ALU`; the scalar pipe performs the final opcode, dependency,
    writeback, and control-flow eligibility checks
- `scalar1_ready` is high

This proves the important split-window example:

```text
S0 S1 A2 -> issue S0+S1, leave A2
S0 A1 S2 -> issue S0 only; S2 waits behind A1
```

## Accelerator Rule

The accel64 head may issue when it is globally oldest and its destination is
ready:

```text
vector entry: tensor bit clear, requires vector_ready
tensor entry: tensor bit set, requires tensor_ready
```

The gate emits one `accel_issue_valid` plus `accel_issue_is_tensor`; downstream
wiring decides whether the entry goes to the accelerator command queue or the tensor
command queue.

## Flush And Redirect

Flush is owned by the storage windows and token packer. This gate has no state
to clear. During redirect, the windows clear their entries and the gate simply
sees no valid heads.

## Tests

`edge_predecode_order_gate_tb.v` proves:

- `S0 S1 A2` issues a supported scalar pair.
- `S0 A1 S2` issues only `S0`, preventing `S2` from crossing `A1`.
- An older vector/tensor accel entry issues only to its matching ready
  destination.
- A blocked oldest head prevents younger ready work from bypassing.
