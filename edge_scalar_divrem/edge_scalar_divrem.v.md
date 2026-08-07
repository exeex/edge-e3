# edge_scalar_divrem.v

## Purpose

Independent radix-4 RV64 divide/remainder execute domain extracted from
`edge_scalar_muldiv`. It owns divide state, accepted destination metadata, and
a one-entry held completion packet. It does not own multiply, WBT, producer
publication, or architectural retirement.

## Handshake

`issue_valid && issue_ready` accepts one `div`, `divu`, `rem`, `remu`, or word
variant. `issue_ready` is low while an operation is active or while a prior
completion is held without `complete_ready`. Normal RV64 operations take 32
radix-4 rounds; word operations take 16. Divide-by-zero and signed-overflow
results use the same held-completion boundary.

`complete_valid` remains asserted with stable sequence, epoch, destination,
bank, valid, and value fields until `complete_ready`. This lets the owning
mul/div wrapper arbitrate simultaneous multiply and divide completions without
losing either result. New work may accept in the same cycle that a held
completion is consumed.

## Ordering

The block does not communicate directly with RTU or WBT. The scalar pipe
allocates those resources only on issue fire and completes them from the
arbitrated M completion. Redirect cleanup remains owned by the tagged scalar
pipe boundary in this slice.

## Tests

The arithmetic and integration paths must cover signed/unsigned 64-bit and
word results, divide-by-zero, signed overflow, held-completion stability, a
multiply accepted while divide remains busy, and simultaneous completion
arbitration.
