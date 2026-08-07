# edge_fetch_packet_fifo.v

## Purpose

`edge_fetch_packet_fifo` is the width adapter and L0 queue between the 128-bit
I-cache response path and the 64-bit tokenizer refill path.

```text
I-cache / edge_ifu_fetch: 128-bit line response
edge_fetch_packet_fifo: split into ordered 64-bit chunks
edge_ifu_predecode_frontend: accept two 32-bit words per refill
edge_predecoder: build one 64-bit issue window
```

The cache line remains 128 bits. The frontend queue and tokenizer observation
boundary no longer retain a 128-bit issue-oriented packet.

## Interface and storage

The input carries the original 128-bit fetch response, its aligned block PC,
the first valid 32-bit word, and epoch. Each non-empty 64-bit half becomes one
queue entry containing 64 instruction bits, chunk PC, one `first_word` bit,
and epoch. `first_word=1` means the low 32-bit word of that chunk is the stale
prefix from a redirect and the tokenizer starts at its upper word.

The production instance has four 64-bit entries, equivalent to two complete
cache responses. Redirect starts at words 0/1 create two chunks, while starts
at words 2/3 create only the high chunk. Empty halves are never queued.

The queue supports one dequeue and up to two input chunks in one cycle. Input
readiness uses registered free capacity; space released by a dequeue becomes
available on the following cycle. This keeps downstream decode backpressure
out of the fetch-response ready path. When the queue is empty, its first input
chunk falls through to the output; if that
chunk is consumed immediately, only a second unconsumed chunk is stored. A
stalled output still captures every input chunk normally. This removes an
otherwise fixed redirect-refill cycle without reducing the four-entry elastic
capacity.

## Redirect

`flush_valid` has priority over enqueue and dequeue and clears every queued
chunk. The I-cache itself is not invalidated; `edge_ifu_fetch` discards a stale
outstanding response and restarts at the redirect PC/new epoch.

## Focused test

`test/edge_fetch_packet_fifo_tb.v` proves empty fall-through for one- and
two-chunk packets, retained-second-chunk behavior, 128-to-64 ordering, word-1
and word-3 prefix handling, full capacity, and redirect cleanup.
