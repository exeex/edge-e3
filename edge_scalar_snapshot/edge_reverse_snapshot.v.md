# edge_reverse_snapshot

`edge_reverse_snapshot` is the accelerator-to-scalar value boundary used by
`accel.getcsr`. It contains two independently addressed entries by default.
The predecoder must reserve an entry before it emits the paired scalar pseudo
and accelerator command.

Allocation returns the lowest free ID and records the command sequence/epoch.
The accelerator side later writes a completed CSR value by ID. The scalar side
may read only after that value is valid; consuming the value releases the entry.
Thus a scalar get-CSR instruction cannot retire before its matching accelerator
command has supplied the value.

When both entries are owned, `alloc_ready` is low and the predecoder must keep
the whole 64-bit instruction bundle blocked. Redirect kills release only younger
entries from the killed epoch. Writes to unowned/stale IDs are rejected through
`write_ready`, preventing a killed command from reviving a reused entry.

The table deliberately stores only completed 64-bit scalar payloads. CSR
selection and zero extension remain owned by `edge_accel_pipe`; GPR reservation,
writeback, and retirement remain owned by `edge_scalar_pipe`.

The focused `edge_reverse_snapshot` Verilator test covers full-table blocking,
out-of-order writes, read/consume, ID reuse, redirect release, and stale writes.
