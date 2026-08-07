# edge_predecode_token_packer.v

## Purpose

`edge_predecode_token_packer` is the 64-bit observation-window classifier for
the scalar/vector/tensor issue path. The I-cache may still return a 128-bit
line, but the predecoder consumes only two ordered 32-bit parcels at this
boundary.

The legal complete issue shapes are:

```text
scalar32 + scalar32
vector64 or tensor64
completed vector/tensor high32 + scalar32
```

The third shape uses the low 32-bit half retained from the preceding window.
The packer can therefore emit one completed accelerator entry and the younger
scalar entry from the same accepted 64-bit observation window.

## Interface and classification

The input has two contiguous parcel slots:

```text
packet_slot_valid[1:0]
packet_slot0_*
packet_slot1_*
```

An instruction-start parcel whose low seven bits equal
`EDGE64_LENGTH_MARKER` is a vector/tensor low half. Its following parcel is the
high half; high-word bit 7 distinguishes tensor from vector. A normal parcel is
a scalar32 instruction.

The output has at most two scalar candidates and one accelerator candidate:

```text
scalar0, scalar1
accel0
```

No second accelerator can be emitted from one 64-bit window.

## Half carry and transition cases

The packer owns one `pending64` low-half register. Legal transitions include:

```text
S + S       -> emit scalar0, scalar1
low + high  -> emit accel0
S + low     -> emit S, retain low
low only    -> retain low
pending + high + S
            -> emit completed accel0 and scalar0
pending + high + low
            -> emit completed accel0 and retain the younger low
```

The retained entry carries the low-half PC, sequence id, and epoch. The high
half does not receive an architectural sequence id. `flush_valid` clears the
carry so a wrong-path half can never combine with a new-epoch parcel.

## Handshake

`packet_ready` requires a legal slot-0-present shape and ready capacity on both
destination sides. Outputs are qualified by `packet_valid && packet_ready`.
If either destination stalls, the complete observation window is retried
unchanged.

## Tests

`edge_predecode_token_packer_tb.v` directly proves all 64-bit shapes, carry
completion, and redirect flush. `edge_predecode_split_window_random_tb.v`
drives 160 randomized scalar/vector/tensor tokens through 64-bit observation
windows, including cross-window halves and randomized issue backpressure, and
checks global issue order.
