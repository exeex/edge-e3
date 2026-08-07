# edge_store_buffer.v

## Purpose

First-slice ordered store buffer for the Edge scalar LSU. This block is the
centralized queue that future store units, load forwarding, fences, and backend
drain logic will share.

Implemented file:

```text
edge_lsu/rtl/edge_store_buffer.v
```

## Ownership

`edge_store_buffer` owns:

- ordered store entry allocation
- FIFO head/tail/count state
- committed-prefix ownership and drain permission
- drain presentation of the oldest committed queued store
- redirect flush cleanup for younger entries
- debug count reporting

It does not yet own:

- store-to-load forwarding
- backend write handshakes
- partial-overlap merge checks
- exception reporting

Committed/drainable state is a prerequisite for enabling LSU-owned early-load
retire beyond focused tests. More independent younger
work may execute after a missed load once retire is decoupled from load data;
an uncommitted younger store must therefore never reach D-cache, DTCM, or the
external backend merely because it reached the FIFO head.

## Entry Payload

Each entry stores:

```text
seq_id
epoch
addr
size
data
wstrb
```

With `ENABLE_COMMITTED_DRAIN=1`, `committed_count_q` tracks the committed FIFO
prefix. Ordered retirement guarantees that stores commit in store FIFO order,
so a prefix count is equivalent to one committed bit per entry while avoiding
an all-entry tag-comparator bank. At most the next two uncommitted entries
compare against the two retire tags each cycle.

The current payload intentionally extends the placeholder LSU completion packet.
`data` is the formatted store-data lane for a 64-bit memory beat, and `wstrb`
selects the active byte lanes. For example, `sh` to byte offset 6 stores the
low 16 source bits in `data[63:48]` and uses `wstrb = 8'hc0`.

## Enqueue Interface

```text
enqueue_valid
enqueue_ready
enqueue_seq_id
enqueue_epoch
enqueue_addr
enqueue_size
enqueue_data
enqueue_wstrb
enqueue1_valid
enqueue1_ready
enqueue1_seq_id
enqueue1_epoch
enqueue1_addr
enqueue1_size
enqueue1_data
enqueue1_wstrb
```

`enqueue_ready` is deasserted only when the queue has no free entry after
accounting for a same-cycle drain. `enqueue1_ready` is high when lane1 can
allocate after accounting for lane0's same-cycle enqueue and the same-cycle
drain. If both enqueue lanes fire, lane0 is written first and lane1 is written
immediately after it in FIFO order.

## Commit Interface

```text
commit0_valid / commit0_seq_id / commit0_epoch
commit1_valid / commit1_seq_id / commit1_epoch
```

These are ordered-retire events, not execute-complete events. A matching event
advances the committed prefix by one; two adjacent store tags may advance it by
two. A non-store retire tag or a tag beyond the next uncommitted entry is
ignored. The core enables this mode; direct legacy leaf tests may leave
`ENABLE_COMMITTED_DRAIN=0`, preserving allocation-coupled drain behavior.

## Drain Interface

```text
drain_valid
drain_ready
drain_seq_id
drain_epoch
drain_addr
drain_size
drain_data
drain_wstrb
drain1_valid
drain1_ready
drain1_seq_id
drain1_epoch
drain1_addr
drain1_size
drain1_data
drain1_wstrb
```

The oldest entry is presented while `drain_valid` is asserted and the committed
prefix is nonempty. The next entry is presented on `drain1_*` only when at least
two entries are both queued and committed. A
`drain_valid && drain_ready` cycle pops lane0; if `drain1_valid &&
drain1_ready` is also true in that same cycle, lane1 is popped too. Lane1 never
drains without lane0, so store visibility remains ordered.

The queue leaf supports paired ordered drain for `store+store`. The maintained
`edge_lsu_top`, memory selector, and D-cache path now carry that second lane to
the bank/phase pair predictor; an unsupported bank, phase, line, or backend
state replays lane1 without allowing it to pass lane0.

The maintained core enables commit gating through `edge_lsu_top`. Allocation
creates an uncommitted entry; matching ordered retire makes it drainable; and a
same-cycle retire match bypasses the prefix register so the backend does not
pay an extra cycle. Redirect continues to discard younger entries. Committed
older entries survive a younger redirect and drain exactly once.

## Flush

```text
flush_valid
flush_seq_id
flush_epoch
```

Flush is selective. A redirect keeps queued entries up to and including
`flush_seq_id` in the matching `flush_epoch`, and drops only younger entries.
This matters because scalar stores retire immediately but may still be waiting
in the STB when a later branch redirects the frontend. Clearing the whole buffer
would lose architecturally older stores, especially after dual `store+store`
enqueue creates a larger pending-store backlog.

Younger age uses modulo sequence subtraction, so selective flush remains
correct across `ff -> 00` wrap. The bounded live span must remain below half
the sequence-number space.

If `flush_seq_id` is zero, the buffer treats the flush as a full reset of queued
entries after any same-cycle drain.

Selective flush caps the committed-prefix count to the number of entries kept.
In a legal in-order stream a redirect cannot kill an already retired store, but
the cap keeps the leaf state self-consistent under directed stimulus as well.

## Tests

The STB is covered through the LSU boundary test:

```text
src/test-e3/edge_lsu/edge_lsu_placeholder_tb.v
src/test-e3/edge_lsu/edge_lsu_ordering_random_tb.v
src/test-e3/edge_lsu/edge_store_buffer_commit_tb.v
```

That test proves single and dual store issue allocate entries with formatted
data/strobes, preserve FIFO order, and drain through the placeholder sink at one
entry per cycle.

The deterministic random scoreboard adds 2,000 replayable cycles of dual
enqueue/drain, independent lane backpressure, simultaneous enqueue/drain,
selective and full flush, queue-full reuse, and repeated pointer wraparound
against an independent logical FIFO model.

The commit test enables commit gating and proves uncommitted suppression,
wrong-tag rejection, retire-to-drain bypass, lane1-only first matching, paired
commit/drain, and selective flush preserving a committed prefix.
