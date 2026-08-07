# edge_fpu_complete_queue

## Purpose

`edge_fpu_complete_queue` absorbs up to five same-cycle completion packets from
misc/cvt, the unified FMAC arithmetic pipe, slow DIV/SQRT, FP-load, and one
reserved integration lane, then presents one ordered-by-arrival
packet per cycle to the scalar GPR/FPR writeback boundary. Architectural retire
ordering remains owned by `edge_retire_sync` and is keyed by sequence and epoch.

The queue stores destination domain, register, bank, value, and `fflags` with
the original sequence metadata. `flush` discards buffered wrong-path results.
`MAX_PUSH` defines how many same-cycle packets `ingress_ready` must reserve;
the standalone queue defaults to all five lanes. Execution slots use this
admission signal before accepting new work. The scalar-pipe instance has four
live completion lanes because input lane 1 is tied off.

## Handshake

Inputs are pulse-style completion lanes and cannot be backpressured after an
operation has started. The queue therefore accepts every asserted input in
lane order 0 through 4. `out_valid/out_ready` is the only draining handshake.
Overflow is a design error and terminates Icarus simulation.

Simulation builds also retain the highest occupancy observed since reset and
print `EDGE_FPU_COMPLETE_QUEUE_MAX_OCCUPANCY <count>` whenever a new peak is
reached. Redirect flushes empty the live queue but do not erase the historical
peak. The observation register is excluded from synthesis.

## Validation

The scalar-pipe FPU integration test drives consecutive mixed-mode FMAC work
and checks that queued completions preserve their metadata, writeback, producer
publication, and in-order architectural retirement. It also makes a younger
misc operation complete before an older multiply and proves that the composed
`edge_retire_sync` holds the younger token until the older one is done.
The same integration test applies a full-epoch redirect with FMAC, misc, slow,
and FP-load work in flight. It proves `flush` prevents buffered results from
reaching writeback/producer/retire and that the following epoch can reuse the
released FPR destinations.
