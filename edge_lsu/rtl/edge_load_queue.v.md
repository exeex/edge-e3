# edge_load_queue.v

## Purpose

First-slice FIFO for accepted scalar loads inside `edge_lsu_top`. This block
separates load issue acceptance from the future D-cache/DTCM backend request and
response path.

Implemented file:

```text
edge_lsu/rtl/edge_load_queue.v
```

## Contract

The load queue owns in-flight load request metadata after the scalar pipe has
reserved the destination GPR or FPR WBT and `edge_scalar_lsu` has produced the effective
address, size, and signedness.

Each entry stores:

```text
seq_id
epoch
rd
bank
domain
addr
size
load_signed
request_sent
```

`rd`, `bank`, and the one-bit GPR/FPR `domain` are retained until response completion so `edge_lsu_top`, not
the memory testbench, owns scalar load-completion metadata.

## Planned Post-Retire Ownership

The decided next LSU slice will allow an eligible normal-memory load to complete
its `edge_retire_sync` token when this queue successfully allocates the entry,
before cache/DTCM data returns. This queue then remains the sole owner of the
pending operation metadata through backend issue and response matching.

Queue allocation completion and load-data completion are distinct events:

```text
allocation completion -> ordered-retire token may advance
data completion       -> register writeback, producer publish, WBT release
```

An allocated load must retain `seq_id`, `epoch`, destination domain/register,
address, size, and response eligibility even after its retire token leaves the
retire queue. A successful response must not generate a second retire
completion. Redirect cleanup still removes accepted but unretired younger
entries; entries older than the redirect boundary remain live. Fence, cache-op,
interrupt/debug observation, and other serializing operations must treat any
live post-retire load entry as pending architectural state.

This mode will first be guarded by a default-off experiment switch. MMIO,
atomics, and accesses with unresolved precise faults are outside the initial
eligible set. Late bus errors in the proof slice are asynchronous/fatal until a
recoverable architectural policy is implemented.

## Handshake

```text
enqueue_valid / enqueue_ready
enqueue1_valid / enqueue1_ready
request_valid / request_ready
request1_valid / request1_ready
complete_valid / complete_ready
```

`enqueue_ready` is high when the queue has at least one free entry, including
same-cycle response completion space. `enqueue1_ready` is high when lane1 can
allocate after accounting for lane0's same-cycle enqueue and the same-cycle
head completion. If both enqueue lanes fire, lane0 is written first and lane1
is written immediately after it in FIFO order.

`request_valid` presents the oldest unsent queued load to the backend.
`request1_valid` presents the next queued load as a paired lane only while the
oldest entry is also being offered. When `request_ready` accepts lane0, the
head entry is marked sent but stays at the head. When `request1_ready` also
accepts the paired lane in the same cycle, the second entry is marked sent too.
A `complete_valid` is matched by `seq_id/epoch` against every live, sent entry.
`complete_rd/bank/domain/size` come from the matched slot, so a younger response
cannot inherit head metadata. A younger completed slot is marked done but held
until all older entries complete; contiguous done entries are then reclaimed
from the head one per cycle.

Each slot distinguishes `queued` from `backend_issued`. A request/FIFO
handshake sets `queued`, preventing duplicate request selection.
Separate `backend_issue0/1` reports match `seq_id/epoch` and set the response-
eligible state. A response for a queued but not backend-issued entry is
rejected.

The paired request is intentionally conservative: lane1 does not bypass an
outstanding lane0 request.

## Flush

Redirect flush keeps the oldest prefix of entries through `flush_seq_id` in the
matching epoch and drops the younger suffix. Entries from a different epoch are
not killed by sequence number alone. This matters for calls/branches: an older
load may still be outstanding when a younger control instruction redirects
fetch, and that older load must still complete to release its GPR WBT entry.

Sequence zero is a normal redirect boundary after epoch rollover; it is not a
global-clear sentinel. In particular, an epoch-zero, sequence-zero return or
jump must preserve an outstanding load from epoch 15. Reset is the only
unconditional queue clear.

The younger comparison uses modulo `SEQ_ID_WIDTH` subtraction, so a post-wrap
sequence such as `00` is correctly younger than a nearby `ff` boundary. This
requires the live instruction span to remain below half the sequence space,
well above this queue's bounded depth.

If a matching load response and redirect flush arrive in the same cycle, the
queue first consumes the response for the head entry, then applies the selective
flush to the remaining entries.

Backend request acceptance also remains effective during a flush cycle. Lane0
and lane1 entries retained by a selective flush keep their `request_sent` bits,
so an older accepted request cannot be reissued after younger entries are
dropped. A same-cycle head completion takes precedence over retaining the
head's sent bit because that entry leaves the queue.

## Non-Goals

- No load data formatting.
- No store-to-load forwarding.
- No D-cache/DTCM selection.
- No alignment exception reporting.

## Tests

```text
src/test-e3/edge_lsu/edge_load_queue_tb.v
src/test-e3/edge_lsu/edge_load_queue_epoch_wrap_redirect_tb.v
src/test-e3/edge_lsu/edge_lsu_ordering_random_tb.v
```

The test proves dual enqueue ordering, paired backend request presentation,
lane1 paired acceptance, lane1 stall without bypass, FIFO ordering,
sent-entry retention, response-only release, full backpressure, same-cycle
completion/enqueue space reuse, `rd/bank` metadata retention, full flush
cleanup, domain metadata retention, and same-cycle completion plus selective
redirect flush.

The epoch-wrap redirect test proves that an epoch-zero, sequence-zero redirect
preserves an older backend-issued load from epoch 15 and that the later response
still returns its destination metadata exactly once.

The deterministic random scoreboard runs 2,000 replayable cycles against an
independent logical FIFO model. It stresses dual enqueue/request, randomized
backend backpressure, request-sent retention, same-cycle request/completion,
selective and full flush, queue-full reuse, and repeated pointer wraparound.

The random stimulus permits backend request acceptance, paired acceptance,
completion, and selective flush to coincide. The directed queue test separately
proves that a flush-preserved accepted lane0/lane1 pair does not reissue and
completes exactly once.
