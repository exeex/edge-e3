# edge_dcache_hit_queue.v

## Purpose

`edge_dcache_hit_queue` is the canonical completion path for every resident
load hit and decouples hit lookup from the single LSU response channel. It owns
four tagged completion entries, accepts up to two hits per cycle, and returns
one completed hit per cycle in allocation order.

Allocation returns a slot token. The D-cache registers that token beside the
synchronous data-array read and writes the returned 64-bit word into the same
slot through `capture0/1`. Each entry also retains `seq_id`, `epoch`, address,
size, signedness, and the configured hit latency.

Direct resident hits use `alloc0/1_ready`, including same-cycle completed-head
pop lookahead. Requests already held by the registered lookup boundary use
`alloc0/1_buffered_ready`, a narrow decode of the registered count that
deliberately excludes that lookahead. Thus a full queue may defer a buffered
hit for one cycle while keeping completion state out of the lookup-buffer pop
path; the direct empty-buffer fast path retains its original throughput.

Redirect does not discard live SRAM reads. Matching-epoch entries younger than
the redirect boundary are marked stale, including entries allocated in the
redirect cycle; once their data and latency complete, they are silently
reclaimed at the queue head. Same-cycle older entries remain visible, and
paired allocations evaluate their sequence identities independently.

This queue contains hits only. Miss allocation, line refill, dirty-victim
writeback, same-line miss merging, and load formatting remain owned by
`edge_dcache`.
