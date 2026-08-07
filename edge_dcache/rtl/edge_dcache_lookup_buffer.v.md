# edge_dcache_lookup_buffer.v

## Purpose

Two-entry fall-through elastic boundary between the scalar LSU load request channel and
D-cache metadata/bank lookup. Each entry stores lane0 plus its optional paired
lane1 as one bundle. Upstream readiness depends only on entry capacity.

## Scheduling and state

Entries preserve arrival order. The controller may mark the oldest candidate
parked when it is a miss and the primary refill slot is busy. A non-parked
younger entry is then exposed on `lookup_*`, allowing a resident hit to bypass
that stopped miss. `retry_parked` makes parked entries eligible again after the
primary miss state drains. `lookup_pop` removes the exposed bundle and compacts the
two-entry array. At most two candidates exist and only one metadata candidate
is exposed in a cycle.

Redirect compares each lane's `(seq_id, epoch)` against the kill boundary.
Killing lane0 removes the bundle because a paired lane1 is necessarily
younger; killing only lane1 clears that lane while retaining lane0. Redirect
also qualifies a push accepted in the same cycle: a killed fall-through lane
is never exposed on `lookup_valid` and is not captured, while an older lane0
may still pass or buffer with a killed younger lane1 removed.

## Handshake

If lane0 launches without its paired lane1, the entry is retained and lane1 is
promoted in place to become the next lane0 candidate.

When empty, the buffer is transparent so a launchable resident hit does not
gain a cycle of dependency latency. A request that cannot launch is captured
at the clock edge. `push_ready` remains independent of the lookup result.

`push_ready` is independent of metadata hit/miss, bank phase, hit-queue space,
and refill state. `lookup_park` and `lookup_pop` are mutually exclusive
controller decisions. Cache maintenance is owned by `edge_dcache` and must not
start until `empty` is asserted along with its other drain conditions.

## First-slice non-goals

The buffer does not own tag comparison, bank arbitration, hit completion, or
refill state. The integrated `edge_dcache_mshr` owns the primary miss/refill
lifecycle; same-line waiter merge remains a separate follow-up change.
