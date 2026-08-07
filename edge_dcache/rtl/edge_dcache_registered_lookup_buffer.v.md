# edge_dcache_registered_lookup_buffer.v

## Purpose

Experimental two-entry fully registered D-cache lookup storage. It is separate
from the maintained fall-through buffer so both paths can use identical LSU and
cache-controller surroundings for A/B validation.

Each entry owns a lane0 plus optional lane1 bundle and short-lived
classification bits (`classified`, `hit`, and `dirty_conflict`). The controller
must invalidate both classifications on any metadata write; this conservative
rule prevents a stored tag result from surviving store, refill, writeback, or
cache-maintenance metadata changes.

## Operations

- `push_*` appends one bundle when capacity exists.
- `push_classified` optionally preserves a metadata result already obtained by
  a hybrid direct lookup. Fully registered users drive it low; a blocked
  hybrid request avoids repeating the same tag lookup on the next cycle.
- `classify_*` records one metadata result per cycle.
- `pop_*` removes either candidate. If lane1 did not launch, it is promoted in
  place and must be classified again.
- redirect removes a killed lane0 bundle or clears only a killed lane1.
- payload slots are stationary. `candidate0` and `candidate1` expose physical
  slots, while the one-bit `oldest_index` tells the scheduler which valid slot
  is logically older. Removing either slot or redirect cleanup changes only
  narrow control state.

The wide bundle registers have no general combinational next-state mux. They
are written only by a successful push, lane1 promotion, or lane1-valid clear.
In particular, pop and hole removal never copy one physical payload slot into
the other. This prevents hit-queue/scheduler control from fanning through every
payload D input during compaction.
Keeping the candidate bundles physical also prevents `oldest_index` from
driving two wide reorder muxes; only the selected launch bundle is muxed by the
controller.

The leaf does not choose which candidate to classify or launch. That policy is
owned by `edge_dcache_lookup_scheduler` and the D-cache controller.
