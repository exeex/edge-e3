# edge_dcache_lookup_scheduler.v

## Purpose

Combinational launch policy for two already-classified D-cache lookup
candidates. Storage and metadata ownership remain outside this leaf.

## Policy

- Candidate 0 and candidate 1 are physical slots. `oldest_index` identifies
  the logically oldest valid slot, which launches whenever its classified hit
  or miss is ready.
- A hit also requires its data-bank phase to match.
- A miss is independent of data-bank phase and requires the primary miss/MSHR
  allocation boundary to be ready.
- The physical younger slot may bypass the physical older slot only when the
  older slot is a miss blocked by a busy MSHR. A phase-blocked hit retains
  ordering because the current hit
  queue allocates entries at data-bank launch; safe hit-over-hit phase bypass
  requires a future ordered slot-reservation boundary.
- Only a classified resident hit may bypass an occupied older slot. A second
  miss remains parked.
- An unclassified older slot blocks bypass, preventing speculative reordering
  before its hit/miss state is known.

`park_candidate0` marks the precise oldest-classified-miss/MSHR-busy case.
Redirect,
metadata invalidation, classification capture, and entry removal are owned by
the surrounding lookup buffer/controller.

## Test

`test/edge_dcache_lookup_scheduler_tb.v` covers oldest hit/miss selection,
phase wait bypass, busy-MSHR hit bypass, second-miss blocking, unclassified
blocking, and empty-slot candidate1 recovery.
It also covers the reverse physical order where slot1 is oldest and a slot0
resident hit bypasses its blocked miss.
