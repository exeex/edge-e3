# edge_ifu_fetch.v

## Purpose

Minimal 128-bit instruction fetch block for the Edge dualstream frontend. This
block owns fetch-block PC generation, aligned instruction-memory request shape,
and redirect restart at an arbitrary 32-bit-aligned PC. Edge does not implement
RVC in this frontend slice; maintained instruction lengths are 32 and 64 bits.
The fetch block deliberately does not decode scalar/vector/tensor instruction
length.

Planned implemented file:

```text
edge_ifu_fetch/edge_ifu_fetch.v
```

The maintained first slice is no-prediction:

```text
retire/scalar redirect > sequential 128-bit fetch block
```

Branch prediction, BTB, BHT, and RAS are later users of the same redirect/input
slots, not part of the first fetch block.

## Ownership

`edge_ifu_fetch` owns:

- 128-bit aligned fetch packet request
- fetch PC restart after reset or redirect
- sequential fetch block increment by 16 bytes
- packet epoch tagging
- the first valid 32-bit word for redirect targets inside a packet

It does not own:

- 32-bit versus 64-bit token classification
- dual-issue bundle selection
- scalar/vector/tensor stream split
- branch compare, target calculation, or prediction update
- program-order `seq_id` assignment
- retire ordering or redirect kill broadcast

`edge_predecoder` owns token slicing and program-order `seq_id` assignment.
`edge_pc_redirect_ctrl` owns redirect priority, epoch bump, and the common kill
boundary.

## Packet Width

The fetch packet is always 128 bits:

```text
fetch_bits[127:0]
fetch_block_pc[PC_WIDTH-1:0]
fetch_start_word[1:0]
fetch_epoch[EPOCH_WIDTH-1:0]
```

`fetch_block_pc` is 16-byte aligned. `fetch_start_word` identifies the first
valid 32-bit word in the aligned packet. On normal sequential fetch:

```text
fetch_block_pc   = current aligned block
fetch_start_word = 0
```

On redirect to the middle of a 128-bit packet:

```text
fetch_block_pc     = redirect_pc aligned down to 16 bytes
fetch_start_word = redirect_pc[3:2]
```

Only 32-bit-aligned redirect targets are legal in the Edge ISA slice:

```text
redirect_pc[1:0] == 2'b00
```

The packet may therefore start at offsets 0, 4, 8, or 12. Bytes before
Words before `fetch_start_word` belong to the older path and must be ignored
after redirect.
No halfword/RVC start offset is supported.

## Fetch Interface

To instruction memory or I-cache:

```text
imem_req_valid
imem_req_ready
imem_req_addr       // 16-byte aligned
imem_resp_valid
imem_resp_ready
imem_resp_bits[127:0]
```

To predecoder:

```text
fetch_valid
fetch_ready
fetch_block_pc
fetch_bits[127:0]
fetch_start_word[1:0]
fetch_epoch
```

The first RTL may model instruction memory as a testbench ROM and return the
128-bit block with fixed latency. The interface shape should still preserve the
request/response split so a real I-cache wrapper can replace the ROM later.

If no registered fetch packet is waiting and the predecoder/tokenizer asserts
`fetch_ready`, a non-stale instruction-memory response may bypass directly to
the fetch output in the response cycle. When that bypass packet is accepted, the
next sequential 128-bit request is queued immediately instead of first storing
the packet in `fetch_valid_r`.

## Redirect Input

From `edge_pc_redirect_ctrl`:

```text
redirect_valid
redirect_pc
redirect_epoch
```

On redirect:

1. discard any outstanding response from the old epoch or tag it stale
2. request the 16-byte-aligned block containing `redirect_pc`
3. emit the returned packet with `fetch_start_word = redirect_pc[3:2]`
4. tag it with `redirect_epoch`

If a stale outstanding response arrives in the same cycle as `redirect_valid`,
the redirect wins. The response handshake may be accepted to drain the old
request, but the old packet must not assert `fetch_valid` or enter the
tokenizer.

Likewise, a pending sequential request must not handshake with instruction
memory in the same cycle as `redirect_valid`. When the request side is ready and
there is no live old outstanding request, or an old stale response is drained in
the same cycle, the redirect target may handshake immediately. Otherwise the
redirect target request is installed into the request register and becomes the
next visible `imem_req_valid` transaction. This avoids an avoidable one-cycle
redirect refill bubble on TCM/ROM-style instruction memory.

The predecoder separately consumes `redirect_kill_*` and must flush its local
byte queue/cursor for killed or stale epochs.

## Sequential Rule

After a packet is accepted by the predecoder, the next sequential request is:

```text
next_fetch_block_pc = fetch_block_pc + 16
next_fetch_start_word = 0
```

Fetch bandwidth is independent from issue bandwidth. The maintained frontend has
three instruction pipelines and selects at most two adjacent tokens per cycle:

```text
scalar + scalar = 32b + 32b = 64b
scalar + vector = 32b + 64b = 96b
scalar + tensor = 32b + 64b = 96b
vector + tensor = 64b + 64b = 128b
```

The fetch block does not decide which adjacent pair may issue. It only supplies
bytes. `edge_predecoder` can parse a `scalar + scalar` pair even while the first
scalar pipe consumes one scalar token per cycle; the second scalar token may be
held in a scalar frontend queue until the scalar pipe is ready. Future scalar
superscalar work can consume both scalar lanes without changing this fetch
contract.

## Packet-Middle Jump Rule

Because branch and jump targets are only 32-bit aligned, a target may land in
the middle of a 128-bit packet:

```text
block byte offsets: 0 4 8 12
redirect_pc[3:0]:   0 4 8 12
```

The fetch block must not shift `fetch_bits`. It emits the aligned 128-bit block
and marks the valid suffix with `fetch_start_word`. The width adapter/tokenizer
treats lower words as absent.

This keeps I-cache data naturally aligned to the Edge 128-bit I-cache line. C906
uses additional frontend packing because it supports RVC halfword instruction
starts; Edge intentionally keeps the boundary simpler because all maintained
instruction starts are 32-bit aligned.

## First Tests

Planned module-local tests:

```text
src/test-e3/edge_ifu_fetch/edge_ifu_fetch_128b_tb.v
```

The test should prove:

- reset fetch from aligned boot PC
- sequential `+16` block requests
- redirect to offsets 0, 4, 8, and 12
- correct `fetch_start_word` values
- stale old-epoch response is not emitted after redirect
- ready redirect target request can issue in the redirect cycle
- non-stale response can bypass directly to `fetch_*` when `fetch_ready` is high
