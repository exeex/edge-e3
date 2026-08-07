# edge_token_issue_window

## Purpose

This document defines the replacement boundary for the current one-entry
`scalar_hold` path in `edge_predecoder`.

The current proof slice accepts typed tokens assembled inside `edge_ifu_predecode_frontend` and
can present an opportunistic `scalar1_*` lane. It is correct, but it couples
token acceptance, bundle decoding, scalar replay, vector capture analysis, and
issue arbitration in one combinational decision. When lane1 refuses the second
scalar, the predecoder stores it in a one-entry hold and blocks the tokenizer
while that held scalar replays.

The next boundary should instead be:

```text
fetch 128b packet
  -> tokenizer / 64b carry assembly
  -> predecode entries
  -> scalar32 window and accel64 window
  -> ordered issue gate
  -> scalar lane0/lane1, accelerator command queue, or tensor command queue
```

The windows are storage partitions, not independent reorder queues. The ordered
issue gate is responsible for consuming zero, one, or two scalar entries per
cycle, or one 64-bit vector/tensor entry per cycle, while preserving global
program order.

## Slot Normalization

The tokenizer owns raw 128-bit fetch-slot splitting and all 64-bit carry across
packet boundaries. The predecoder should not reason about a dangling half vector
as an executable entry.

Instruction fetch slots are 32-bit aligned. A 32-bit scalar consumes one slot.
A 64-bit vector/tensor instruction consumes two adjacent 32-bit slots, but those
two slots are not guaranteed to arrive in the same 128-bit fetch packet. A 64-bit
instruction may be cut at a packet boundary.

Raw 32-bit slots are normalized into typed entries:

```text
S = one 32-bit scalar entry
V = one complete 64-bit vector entry, spanning two adjacent 32-bit slots
T = one complete 64-bit tensor entry, spanning two adjacent 32-bit slots
H = half of a 64-bit entry, held inside tokenizer carry state only
```

For a complete 128-bit packet, legal normalized entry patterns are:

```text
S
S S
S S S
S S S S
V
V S
V S S
S V
S V S
S S V
V V
```

Packet-edge cases such as `H S S S`, `S S S H`, or `S H S` are tokenizer carry
states, not issue-window states. The tokenizer must complete the 64-bit entry
using carry from the adjacent packet before presenting it as `V` or `T`.

The issue window must never enqueue a half entry. It only sees complete ordered
entries:

```text
packet N ends with low half of V64:
  tokenizer holds H, does not enqueue it

packet N+1 starts with high half of V64:
  tokenizer emits one complete V entry with the original low-half PC/seq
```

The 64-bit entry's architectural PC and `seq_id` belong to the first 32-bit slot
of the instruction. The second half does not become an independent issue-window
entry.

The next tokenizer/packer slice should make this carry state explicit:

```text
pending64_valid
pending64_low32
pending64_pc
pending64_seq_id
pending64_epoch
pending64_kind        // vector or tensor
```

If a 128-bit packet ends with the low half of a 64-bit entry, the packer records
that state and does not enqueue the half. The next accepted packet must supply
the high half before any younger entry from that packet can be enqueued. Redirect
flush clears the pending half because the stored low word belongs to the killed
path.

This handles both useful cut cases:

```text
packet N:   ... S H64_low
packet N+1: H64_high ...

packet N:   H64_low S S S
packet N+1: H64_high ...
```

Only the completed 64-bit entry reaches the downstream windows.

## Predecode Entry

Each normalized entry should be converted before it reaches the issue selector:

```text
valid
kind              // scalar, vector, tensor, illegal
pc
inst32 / inst64
seq_id
epoch
slot_span         // 1 for scalar, 2 for vector/tensor

scalar_class      // alu, load, store, branch, system, fence, fatal
scalar_rd
scalar_rs1
scalar_rs2
scalar_writes_gpr
scalar_reads_rs1
scalar_reads_rs2

vector_needs_base_gpr
vector_n_src_gpr
vector_base_src_gpr
```

Early classification is the important change. The issue selector should not
wait until the cycle of `token_ready` to discover whether a scalar pair is
`load+load`, `store+store`, ALU, branch, or unsupported.

## Split Storage Windows

The next RTL shape should split storage by physical issue width:

```text
scalar32_window:
  stores only S entries
  enqueue 0..4 entries from one 128-bit packet
  pop 0..2 entries per cycle

accel64_window:
  stores complete V/T entries before stream dispatch
  enqueue 0..2 entries from one 128-bit packet
  pop 0..1 entry per cycle
```

Both windows carry `seq_id`, `epoch`, `pc`, and decoded sideband. The packer
assigns one global program-order sequence to every complete entry before it
chooses the destination window. The storage split is purely physical: it keeps
the scalar `32+32` fast path simple and gives vector/tensor one natural 64-bit
head, but it does not permit a younger scalar to bypass an older accelerator
entry.

The ordered issue gate compares the heads:

```text
oldest = min(scalar32_head.seq_id, accel64_head.seq_id)
```

If the oldest entry is scalar, scalar lane0 may issue it. Scalar lane1 may issue
the next scalar only when the second scalar is the next global entry as well.
For example, `S0 A1 S2` may issue `S0` alone; `S2` waits until `A1` has issued.
For `S0 S1 A2`, scalar lane0/lane1 may issue `S0+S1`, leaving `A2` as the next
head.

If the oldest entry is vector/tensor, the accelerator entry issues when its
destination queue and capture/control dependencies are ready. A vector entry
dispatches to the accelerator command queue and then `edge_accel_pipe`, which owns
VR and VR WBT state. A tensor entry dispatches to the tensor command queue/pipe,
which does not own VR state. Scalars behind the accelerator entry wait.

This rule gives the desired "64 sinks to the end and then fires" behavior
without adding a bypass path. A 64-bit entry that is older than later scalar
entries fires as soon as it reaches the global head; a 64-bit entry behind two
older scalars waits until those scalars are consumed.

## In-Order Issue Rule

The logical issue window is ordered even though the next storage is split. The
oldest complete entry determines what can issue. No younger entry may bypass an
older entry.

Per cycle, the selector computes:

```text
scalar_consume = 0, 1, or 2
accel_consume = 0 or 1
```

For the current scalar hardware:

```text
scalar_consume = 2 only for supported scalar lane1 pairs:
  load + load
  store + store

scalar_consume = 1 for any lane0-supported scalar when lane0 is ready.
scalar_consume = 0 when the head scalar is blocked by dependencies/resources.
```

When the head is vector/tensor, scalar entries behind it wait. This keeps
scalar/vector/tensor side effects in program order until a future policy
explicitly permits safe lookahead.

## Queue Update Table

The queue update is independent from raw packet shape. It depends only on the
ordered head entries and consume counts.

```text
head pattern   consume                 result
S ...          scalar_consume = 0       keep all entries
S ...          scalar_consume = 1       pop S
S S ...        scalar_consume = 2       pop S, S
S V ...        scalar_consume = 1       pop S; V becomes head
S S V ...      scalar_consume = 1       pop first S; queue becomes S, V
S S V ...      scalar_consume = 2       pop both S entries; V becomes head
V ...          vector_consume = 0       keep all entries
V ...          vector_consume = 1       pop V
V S ...        vector_consume = 1       pop V; S becomes head next
V S S ...      vector_consume = 1       pop V; S, S can pair next cycle
```

This covers the examples:

```text
S S V
S V S
V S S
S S S S
V S
S V
V V
```

The same table also covers packet-edge source forms after tokenizer carry has
normalized them into complete entries.

## Ready/Backpressure

The tokenizer may advance when the issue window has enough free entries for the
complete normalized entries being offered.

Lane1 refusal must not block tokenizer acceptance by itself. It only changes
`scalar_consume` from `2` to `1`, leaving the second scalar in the issue window.

Backpressure should come from explicit resources:

```text
issue window full
head scalar lane0 blocked
head vector/tensor queue blocked
rename/capture allocation unavailable for the head entry
redirect flush cleanup
```

## Migration Plan

1. Add an `edge_predecode_issue_window` block with entry enqueue, head/head1
   visibility, and pop0/pop1 controls. Done for the scalar-only integration
   slice.
2. Feed scalar-only normalized token entries into the window and prove that
   scalar backpressure can enqueue instead of blocking tokenizer acceptance.
   Done for scalar-only typed tokens.
3. Move current `scalar+scalar` lane1 candidate generation from token-fire time
   to issue-window head/head1 selection. Done for `load+load` and
   `store+store` pairs; ALU dual issue remains intentionally disabled.
4. Feed issue consume counts back to the tokenizer so `consume=1` keeps token 1
   as the next tokenizer head instead of forcing whole-bundle acceptance. Done
   for scalar-only typed tokens with a low-water scalar issue-window buffer.
5. Reconnect vector patterns through the window without permitting scalar
   bypass across a head vector.
6. Remove the one-entry `scalar_hold` path.

The split-window migration has started with `edge_predecode_token_packer`. It
does not yet replace the integrated `edge_predecoder` path. It proves the
standalone packet-to-enqueue boundary for scalar32 entries, complete vector or
tensor accel64 entries, and packet-tail pending64 carry state.

The first integrated use of the packer is now in `edge_predecoder`'s typed
mixed/vector token path. It normalizes `token0/token1` back into local 32-bit
slots and selects the first accel entry for the current direct vector command
handoff. Scalar-only token bundles and the legacy 96-bit `window_valid` path are
still on the earlier implementation.

`edge_predecode_order_gate` is the next standalone proof slice. It compares the
scalar32 and accel64 heads by global `seq_id`, permits lane1 only for supported
same-class scalar memory pairs that are still older than the accel64 head, and
prevents younger ready work from bypassing a blocked oldest head.

The first implementation slice should preserve current behavior when the issue
window depth is effectively one. The second slice should enable depth greater
than one and prove tokenizer acceptance continues while scalar lane0 drains
older entries.
