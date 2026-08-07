# edge_dcache_mshr.v

## Purpose and ownership

`edge_dcache_mshr` is the authoritative one-entry primary miss controller for
`edge_dcache`. It owns the active request identity, redirect-stale state,
dirty-victim wait, refill request handshake, refill beat index, accumulated
error, requested 64-bit word, and completion pulse.

The parent D-cache still owns tag/dirty/data arrays, dirty-victim writeback,
load-value formatting, and arbitration between miss and hit-queue responses.
The MSHR presents each accepted refill beat to the parent through
`refill_store_*`; the parent supplies `refill_store_ready` from the banked data
array and commits tag metadata on a successful `complete` pulse.

This integration slice intentionally supports one primary waiter and one
outstanding cache line. Same-line merge, multiple MSHRs, and critical-word-first
completion are later changes.

## Miss allocation

- `miss_ready` is asserted only when the entry is inactive.
- `miss_valid && miss_ready` captures address, seq, epoch, size, and signedness.
- A clean victim raises `refill_req_valid` immediately.
- `miss_wait_writeback` holds the refill request until
  `victim_writeback_complete`; the already captured miss payload remains
  stable while the parent drains the dirty victim.
- Different-line and same-line secondary misses are both backpressured in this
  first integrated version. The lookup buffer may park one while younger
  resident hits continue.

## Refill

`refill_req_addr` is the captured address aligned to the configured cache-line
size. After its handshake, `refill_active` is set and `active_beat` starts at
zero. Each `refill_resp_valid && refill_resp_ready` beat advances the index.

`refill_store_valid`, beat, and 128-bit data expose a valid error-free beat to
the parent data array. Backpressure deasserts `refill_resp_ready` without
advancing state. Once any response reports an error, later beats are consumed
but no longer written into the cache line.

The requested 64-bit half is selected from the matching 128-bit beat using the
captured address. Completion still waits for `refill_resp_last`, preserving
the pre-integration behavior.

## Completion and redirect

`complete` is a one-cycle refill-finalization pulse regardless of redirect. It
lets the parent commit successful tag metadata and release cache-array state.
`complete_valid` is the response-qualified form: it is suppressed when the
captured request was killed by a same-epoch redirect, including a redirect in
the allocation or completion cycle. Refill/writeback cleanup still runs, and
an issued refill is never cancelled solely because its waiter became stale. A
same-cycle older request remains live. The comparison uses modulo sequence
ordering across wrap.

The entry remains `active` during the completion pulse and releases on the
next edge. This preserves cache-op drain, same-index hit blocking, and the old
primary response timing.

## Directed coverage

`edge_dcache_mshr_tb` proves clean allocation, dirty-victim wait, request
alignment, refill-store backpressure, beat progression, selected-word capture,
successful completion payload, accumulated error, and redirect response
suppression while the refill continues to completion.
