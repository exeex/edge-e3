# edge_lsu_top.v

## Purpose

Maintained Edge scalar LSU subsystem boundary. This block is the scalar pipe's
only memory-execution dependency. It replaces the earlier direct coupling from
`edge_scalar_pipe` to the narrow `edge_scalar_lsu` address-generation leaf.

The design direction is:

```text
distributed load/store execution units
+ centralized memory-ordering core
+ shared store buffer
+ shared D-cache/DTCM backend arbiter
```

The current RTL keeps the scalar pipe's observable placeholder behavior while
starting to allocate explicit LSU resources: it accepts a normal lane0 scalar
memory packet and a memory-only lane1 packet, delegates address/size/alignment
formatting to `edge_scalar_lsu`, formats store data and byte strobes for the
STB, enqueues aligned stores into `edge_store_buffer`, enqueues aligned loads
into `edge_load_queue`, exposes ready/valid backend request channels for the
future D-cache/DTCM boundary, reports misaligned load/store attempts before they
reach the backend, returns the transitional lane0 memory request packet, and
owns the load response metadata used for GPR completion. It also reports
lane0/lane1 load-accept events only after the matching queue allocation really
succeeds; those events are the factual boundary used by the default-off split
load-retire experiment.

`LOADQ_COUNT_WIDTH` defaults to `$clog2(LOADQ_DEPTH + 1)` and should stay paired
with the configured load queue depth. A wider count can wrap the queue's
free-space arithmetic after the physical entries are full and corrupt outstanding
load ownership.

## Ownership

`edge_lsu_top` owns the long-term scalar memory boundary:

- load/store issue acceptance from `edge_scalar_pipe`
- future LU/SU dispatch
- future store buffer allocation, forwarding, and drain permission
- future load ordering against older stores
- future DTCM-window selection and D-cache/cache-maintenance backend routing
- future memory-side completion, exception, and fence/cache-op ordering

The first slices own the wrapper boundary, store-buffer allocation point, load
queue allocation point, and store formatter. They delegate address/size
formatting to `edge_scalar_lsu`.

It does not own:

- scalar GPR/FPR register files
- GPR/FPR WBT reserve/release
- scalar instruction decode
- architectural retire order outside memory completion metadata
- D-cache implementation
- DTCM SRAM subsystem

## Issue Interface

```text
forever_cpuclk
cpurst_b
lsu_issue_valid
lsu_issue_ready
lsu_issue_seq_id
lsu_issue_epoch
lsu_issue_is_store
lsu_issue_funct3
lsu_issue_rd
lsu_issue_bank
lsu_issue_domain
lsu_issue_base_value
lsu_issue_offset
lsu_issue_store_data
lsu_issue1_valid
lsu_issue1_ready
lsu_issue1_seq_id
lsu_issue1_epoch
lsu_issue1_is_store
lsu_issue1_funct3
lsu_issue1_rd
lsu_issue1_bank
lsu_issue1_domain
lsu_issue1_base_value
lsu_issue1_offset
lsu_issue1_store_data
lsu_store_commit0_valid
lsu_store_commit0_seq_id
lsu_store_commit0_epoch
lsu_store_commit1_valid
lsu_store_commit1_seq_id
lsu_store_commit1_epoch
```

`funct3[1:0]` encodes byte/halfword/word/doubleword size. For loads,
`funct3[2]` selects unsigned when set. Stores ignore signedness.

Loads are ready when their placeholder address-generation leaf is ready and
`edge_load_queue` can allocate the corresponding lane entry. Stores are ready
when `edge_store_buffer` can allocate the corresponding lane entry. Lane0 and
lane1 share the same load queue and store buffer; when both lanes target the
same queue in the same cycle, lane1 ready reflects the second available slot.
Future slices may also deassert ready when the load-order table, backend
arbiter, or cache-maintenance pipe is full.

Lane1 is intentionally memory-only. It is the LSU-side backbone for future
scalar `load/store + load/store` pairing, not a general second scalar execute
pipe. The scalar WBT, retire allocation, and predecoder pairing rules now
connect this boundary for conservative `load+load` and `store+store` pairs.

## Resource Model

The LSU resource model is split into three independent questions:

```text
issue resource:
  Can the scalar pipe hand this memory operation to the LSU this cycle?

in-flight resource:
  After acceptance, which LSU queue/table owns the operation until completion?

completion/retire resource:
  Which event releases WBT, produces load data, permits store visibility, or
  allows architectural retire?
```

The target first non-placeholder scalar model is:

```text
single-issue scalar pipe
  accepts at most one scalar instruction per cycle

edge_lsu_top
  accepts one lane0 memory operation per cycle when resources are available
  may also accept one memory-only lane1 operation in the same cycle
  allocates loads into an edge_load_queue
  allocates stores into edge_store_buffer
  lets independent younger scalar instructions continue while older memory ops
  remain in flight
```

For four independent loads with available load-queue entries, the current
single-issue scalar pipe should issue them in four cycles:

```text
cycle N+0: accept ld x10, 0(a0)
cycle N+1: accept ld x11, 8(a0)
cycle N+2: accept ld x12, 16(a0)
cycle N+3: accept ld x13, 24(a0)
cycle N+4: accept an independent ALU/control/store instruction if its own
           operands and destination resources are ready
```

After the memory-only lane1 scalar boundary is connected, two independent
memory operations in the same scalar bundle may allocate in one cycle:

```text
cycle N+0: accept ld x10, 0(a0) and ld x11, 8(a0)
cycle N+1: accept ld x12, 16(a0) and ld x13, 24(a0)
```

The LSU must not require the first load's data to return before accepting the
second load. Backpressure should come from explicit resources, not from the fact
that an older load is outstanding:

- load queue full
- destination WBT cannot reserve
- older store with unknown address blocks a younger load
- backend request queue full
- fence/cache-op ordering point
- redirect/flush in progress

## WBT And Retire Contract

The scalar pipe owns GPR/FPR WBT reserve checks because it sees decoded
destination registers before LSU issue. The LSU owns memory-operation
completion once an operation has been accepted.

The maintained default uses response-coupled load retirement:

For loads:

```text
load accepted:
  scalar pipe reserves GPR WBT for rd
  LSU allocates a load-queue entry with seq_id/epoch/rd/addr/size/signedness
  scalar pipe may accept younger independent instructions

load completes:
  LSU returns seq_id/epoch/rd/value or an exception
  scalar pipe writes the GPR, releases WBT, emits producer_valid, and retires
  the matching scalar token
```

For stores:

```text
store accepted:
  scalar pipe verifies source operands are ready
  LSU allocates an STB entry
  store completes execution after allocation and waits in ordered retire

store drains:
  ordered-retire feedback commits the matching FIFO prefix
  STB writes DTCM/D-cache/backend only after that commit
```

Dependent younger instructions should stall through WBT, not through a global
LSU busy bit. Independent younger instructions should continue unless one of
their own resources is unavailable.

## Experimental LSU-Owned Split Completion

The first split-completion RTL separates ordered-retire completion from
load-data completion for integer loads when `ENABLE_EARLY_LOAD_RETIRE=1`.
This direction follows the useful C906 division of
responsibility without copying the legacy implementation: C906 reports normal
LSU completion from address generation after a request is accepted, retains a
missed load's destination metadata in its eight-entry line-fill buffer, and
writes the register later when data returns. Its four-entry store buffer also
provides merge and store-to-load forwarding. Late bus errors use an asynchronous
exception path, while pipeline-empty checks still include LSU and writeback
state.

The Edge target contract is:

```text
load acceptance completion:
  effective address and immediate alignment checks are complete
  an edge_load_queue entry has been allocated successfully
  no same-cycle redirect kills the operation
  LSU sends seq_id/epoch completion to edge_retire_sync
  ordered retire may now pass this token when it reaches the head

load data completion:
  load queue remains the owner while cache/DTCM data is pending
  LSU returns seq_id/epoch/rd/domain/value
  scalar pipe writes the GPR, releases WBT, and publishes producer data
  no second retire completion is generated
```

Retiring the token does not make the destination register ready. The GPR WBT
remains busy until the matching data response, so RAW and WAW dependencies
stay blocked while unrelated instructions continue. The load queue therefore
becomes the bounded post-retire ownership structure instead of the eight-entry
retire queue.

The implementation is parameter gated as `ENABLE_EARLY_LOAD_RETIRE`, with the
maintained default disabled until the correctness rules below are covered.
Both lane0 and lane1 integer load acceptance paths are implemented. Lane0 uses
retire completion port 1 and lane1 uses port 4. A lane1 load is held for replay
while a prior lane1 Fast ALU completion occupies port 4, so neither completion
is lost. FP loads remain response-coupled because the current shared FP
completion queue does not retain a source-kind bit.

Early completion is initially eligible only for ordinary cacheable RAM and
DTCM accesses whose synchronous address/alignment checks are resolved before
queue allocation. MMIO, atomics, cache operations, and any future translated
access that can still raise a precise fault remain response-coupled or
serializing. Until a recoverable late-fault mechanism exists, a bus error after
early retire is an asynchronous/fatal machine error, not a precise load-access
fault.

Architectural observation points must still wait for pending LSU ownership to
drain. Fence, cache-maintenance, interrupt/trap entry, debug halt, and any state
snapshot that requires a complete register file must not observe a retired load
whose WBT entry is still busy. A redirect continues to remove unretired younger
queue entries by sequence/epoch; an older load that has already retired remains
owned by the LSU until writeback.

Store ownership uses a related but stricter rule:

```text
store accepted:
  allocate STB entry, but do not make it externally visible

store ordered-retire event:
  mark the matching STB entry committed/drainable

store drain:
  only committed entries may update D-cache, DTCM, or the external backend
```

The core now enables commit-gated store drain. The STB represents per-entry
commit state as a committed-prefix count, using store FIFO order to avoid an
all-entry tag-comparator bank. Early-load-retire remains default-off because a
recoverable late-error policy is not implemented.

Implementation and validation status/order:

1. Done: lane0/lane1 integer load-accept completion events and the default-off
   switch; load response keeps register writeback and WBT release ownership.
2. Done: directed early-retire, independent/dependent ALU, lane1, completion-
   port collision, redirect cleanup, and stale-response tests.
3. Done: ordered-retire feedback advances committed STB state and prevents
   uncommitted backend drain in the maintained core.
4. Done: fence, cache-op, DMA, and host-completion system operations wait for
   pending load writeback and store drain. Directed early-load tests prove that
   fence/cache-op remain blocked after load retire until data writeback. This
   slice has no architectural interrupt/debug-halt; `core_force_stop` remains
   an explicit imprecise host abort rather than a register-file snapshot.
5. Done: current-branch SoC A/B showed CoreMark internal `rdcycle` improve from
   751,253 to 746,201 (0.67%) and retire-queue-full cycles fall from 7,638 to
   zero. The 80-cycle hit-under-miss case remained 2,571 internal cycles even
   though maximum retire occupancy fell from eight to four. Early retire
   therefore relieves general retire pressure, but does not move that
   benchmark's final load-data dependency/serialization critical path.
6. Done: repair the software DMA wrapper so the inline `.insn` directly
   references its source, destination, and length operands. This prevents
   optimized compilation from deleting the length-register materialization;
   the seven full-core DMA software cases now pass.
7. Done: a pending younger Tensor WLD can replace an unused loaded tile. The
   idle Tensor wrapper rotates the old pending tile active, freeing the other
   physical buffer, while blocking replacement if compute or a start owns it.
8. Done: the maintained harness excludes stress, benchmark, and C906 labels;
   165 tests pass, one intentional fatal-path test is disabled, and none fail.
   Keep early load retire default-off until recoverable late-load-error
   handling is defined.
9. Done: every resident D-cache load hit now uses the four-entry tagged hit
   queue, leaving the primary pending slot miss/refill-only. Exact `0af7791`
   A/B improved CoreMark by 1.08%, Top-K by 4.54%, and beam search by 6.54%; the
   five maintained hot-L1 control cases and deterministic CoreMark checks pass.
10. Next: place a registered D-cache lookup request stage between the LSU
    selector and tag/data policy, then move refill ownership into the existing
    MSHR side module. This should remove metadata-hit decisions from the long
    upstream ready path, park a miss independently, and let the load queue feed a
    truly pipelined lookup boundary without an LSU/D-cache combinational loop.

## Memory Packet Interface

```text
lsu_complete_valid
lsu_complete_seq_id
lsu_complete_epoch
lsu_complete_is_store
lsu_complete_size
lsu_complete_load_signed
lsu_complete_addr
lsu_complete_store_data
lsu_misaligned_valid
lsu_misaligned_lane1
lsu_misaligned_seq_id
lsu_misaligned_epoch
lsu_misaligned_is_store
lsu_misaligned_size
lsu_misaligned_addr
lsu_complete1_valid
lsu_complete1_seq_id
lsu_complete1_epoch
lsu_complete1_is_store
lsu_complete1_size
lsu_complete1_load_signed
lsu_complete1_addr
lsu_complete1_store_data
lsu_load_accept_valid
lsu_load_accept_seq_id
lsu_load_accept_epoch
lsu_load_accept_domain
lsu_load_accept1_valid
lsu_load_accept1_seq_id
lsu_load_accept1_epoch
lsu_load_accept1_domain
lsu_flush_valid
lsu_flush_seq_id
lsu_flush_epoch
lsu_debug_stb_count
```

Completion currently means only that an aligned placeholder memory packet is
formatted. Loads also allocate an `edge_load_queue` entry. Stores complete after
their placeholder packet has allocated a store-buffer entry. Lane0 retains the
transitional externally visible `lsu_complete_*` packet used by existing scalar
pipe tests; lane1 exposes matching `lsu_complete1_*` fields that the scalar
pipe forwards as `mem_placeholder1_*`. The `lsu_load_accept*` pulses are more
specific: they assert only for a non-flushed, aligned load whose queue enqueue
is accepted. They carry sequence, epoch, and destination domain but no data.

## Backend Request Interface

`edge_lsu_top` now exposes both queue heads to the maintained backend boundary:

```text
lsu_load_req_valid / lsu_load_req_ready
lsu_load_req1_valid / lsu_load_req1_ready
lsu_store_req_valid / lsu_store_req_ready
lsu_store_req1_valid / lsu_store_req1_ready
```

Lane0 is the ordered primary request. Lane1 is a paired request from the same
load queue or store buffer drain step. Loads pass through a two-entry,
dual-allocation/dual-dequeue request FIFO:

- lane1 load can be offered only with the current lane0 load head
- lane1 store can be offered only with the current lane0 store drain head
- backend acceptance of lane1 is optional; if lane1 is not accepted, it remains
  queued and is replayed later in order
- an empty FIFO has a combinational fall-through path, preserving the baseline
  request latency
- request FIFO acceptance and backend issue are separate tagged events
- load responses may return out of order and are matched by `seq_id/epoch`
- a redirect/flush cycle suppresses both FIFO allocation and backend request
  handshakes; preserved entries retry on the following cycle

This keeps the scalar pipe and retire path precise while allowing the D-cache
to consume same-cycle `load+load` / `store+store` pairs when its bank and tag
state can sustain them.

Misaligned operations suppress the normal completion packet, do not allocate
load queue or store-buffer state, do not drive backend request channels, and
instead report `lsu_misaligned_*`. Precise RISC-V exception retirement is not
implemented yet; the first scalar-pipe consumer treats the sideband as a fatal
simulation/report path.

For compatibility with existing placeholder pipe tests, `lsu_complete_store_data`
still carries raw `rs2` store data. The STB entry receives formatted data and
byte strobes:

```text
SB: wstrb = 8'h01 << addr[2:0], data = rs2[7:0]   << (8 * addr[2:0])
SH: wstrb = 8'h03 << addr[2:0], data = rs2[15:0]  << (8 * addr[2:0])
SW: wstrb = 8'h0f << addr[2:0], data = rs2[31:0]  << (8 * addr[2:0])
SD: wstrb = 8'hff,                 data = rs2[63:0]
```

The alignment checker rejects misaligned halfword/word/doubleword accesses
before this formatter is used for real memory writes. Byte accesses are always
aligned.

This interface is still transitional: it is the memory request/formatting packet
used by the ROM/TCM harness, not the architectural load-completion event.

## Load Response Interface

```text
lsu_load_resp_valid
lsu_load_resp_seq_id
lsu_load_resp_epoch
lsu_load_resp_value
lsu_load_req_valid
lsu_load_req_ready
lsu_load_req_seq_id
lsu_load_req_epoch
lsu_load_req_addr
lsu_load_req_size
lsu_load_req_signed
lsu_store_req_valid
lsu_store_req_ready
lsu_store_req_seq_id
lsu_store_req_epoch
lsu_store_req_addr
lsu_store_req_size
lsu_store_req_data
lsu_store_req_wstrb

lsu_load_complete_valid
lsu_load_complete_seq_id
lsu_load_complete_epoch
lsu_load_complete_reg
lsu_load_complete_bank
lsu_load_complete_domain
lsu_load_complete_size
lsu_load_complete_error
lsu_load_complete_value
```

`lsu_load_req_*` is the load request channel toward the future backend. The load
queue first marks an entry queued when the request FIFO accepts it, and marks it
backend-issued only when a FIFO output (or empty-FIFO fall-through request)
handshakes with the backend.
The placeholder backend supplies load data with `seq_id/epoch/error/value`. The LSU
matches that response against any backend-issued load-queue entry and returns
`rd/bank` from the retained queue entry. `lsu_load_complete_error` is qualified
by that successful tag match, so a stale or unmatched backend error cannot
raise a machine error. `edge_scalar_pipe` then writes the GPR, releases WBT,
and emits `producer_valid`; it also retires the matching token in the maintained
default mode. A response that arrives before backend issue is not completed.

Under the implemented split-completion experiment, the same response path
continues to write the register, release WBT, and emit `producer_valid`, but
integer-load retire completion moves to successful load-queue allocation as
specified above.

`lsu_store_req_*` is the store drain channel toward the future backend. It
drives the store-buffer head entry and drains only when `lsu_store_req_valid &&
lsu_store_req_ready` fires. This is still an ordered in-place STB drain, but the
backend can now apply D-cache/DTCM backpressure instead of relying on the old
hardwired placeholder sink.

This is the first LSU-originated load completion slice. Refill errors use the
asynchronous/fatal bit above. A future precise or retrying LSU still needs
architectural exception fields:

```text
load_complete_exception_valid
load_complete_exception_code
```

The existing `gpr_placeholder_complete_*` inputs on `edge_scalar_pipe` remain as
a unit-test-only compatibility path. Integrated ROM/TCM tests now feed
`lsu_load_resp_*` and let `edge_lsu_top` produce the GPR load completion.

## Planned Internal Blocks

The next non-placeholder LSU should split into these blocks under this
directory:

```text
edge_load_queue.v
edge_load_unit.v
edge_store_unit.v
edge_lsu_order.v
edge_lsu_backend_arb.v
```

First target:

- implemented: parameter-gated LSU-owned split integer-load completion, with
  lane0/lane1 acceptance completing retire independently of later register
  writeback
- implemented: committed/drainable store-buffer state driven by ordered-retire
  feedback
- memory-only lane1 scalar issue boundary connected to `edge_scalar_pipe`
- paired load/store WBT checks and retire allocation
- `1LU + 1SU` request scheduling behind the dual enqueue boundary
- parameterized 2-entry, 4-entry, or 8-entry load queue
- shared 8-entry or 16-entry store buffer
- store-to-load forwarding from older committed/known stores
- in-order store drain
- precise load/store misaligned trap retirement
- DTCM hit path that bypasses D-cache
- D-cache path for external memory
- blocking cache-maintenance operations for software-managed DMA coherence

Later target:

- `2LU + 1SU` or `2LU + 2SU`
- partial-overlap load overlay from memory plus store buffer bytes
- parameterized backend ports for banked DTCM and D-cache
- write-back D-cache maintenance integration

## Store Buffer Contract

The store buffer is a centralized LSU resource, not a private SU queue. The
first slice already instantiates `edge_store_buffer` and tracks:

- byte address
- size
- shifted store data
- byte mask
- `seq_id` and `epoch`

Implemented state also includes:

- committed/drainable FIFO-prefix state

Future slices should add:

- fault/kill state

Stores may allocate before they are visible externally. They must not drain to
D-cache, DTCM, or external memory until the ordering core grants drain
permission. Redirects and exceptions kill younger entries by epoch/sequence.

Loads must check older store-buffer entries before issuing to memory. Full byte
coverage may forward directly. Partial overlap may initially stall until the
older store drains; a later implementation may merge memory data with forwarded
store bytes.

## D-cache And DTCM Contract

DTCM-window hits bypass D-cache. External-memory accesses use D-cache once the
backend is connected.

D-cache is not hardware-coherent with DTCM DMA. The LSU must preserve the
software-managed cache-maintenance contract used by `tests/software/dma`:

```text
clean before DMA reads external cached memory
invalidate before CPU reads external memory written by DMA
clean-invalidate when both writeback and stale-line discard are intended
```

Cache-maintenance operations should be blocking at this boundary: they complete
only after required writeback and/or invalidation is observable to the DMA/AXI
side.

## Current Load Queue Slice

`edge_load_queue` is now instantiated by `edge_lsu_top`. It owns accepted load
metadata after address generation:

```text
seq_id
epoch
rd
bank
addr
size
load_signed
request_queued
request_sent
```

`request_queued` prevents a FIFO-owned request from being selected again.
`request_sent` means the D-cache/backend has actually accepted the tagged
request and is the prerequisite for response completion. The load-queue leaf
also has a conservative
paired `request1_*` lane for the next queued load. That lane only fires together
with the ordered head request. Both
request lanes are threaded through `edge_scalar_pipe`,
`edge_lsu_mem_selector`, and `edge_dcache`; backend bank, phase, or line
conflicts replay lane1 in order.

Load responses are matched inside `edge_load_queue` by `seq_id/epoch`, and the
matched slot supplies completion `rd`, bank, domain, and size. Queue storage is
still reclaimed in order. The maintained backend path offers the ordered head
and, when possible, its adjacent lane1 request through the two-entry request
FIFO. The former generalized checker/snapshot extra-request path was removed
after same-binary A/B showed no internal-cycle benefit in CoreMark, the five
control benchmarks, or JPEG.

Redirect flush is selective for loads: the queue preserves older outstanding
entries through the redirecting `seq_id/epoch` and drops only younger entries.
When a response and redirect arrive together, the response for the head entry is
consumed before the remaining queue is filtered. This keeps older loads from
leaking WBT busy bits across function-call redirects.

## First-Slice Simplifications

- Up to two same-class load or store instructions can be accepted together.
- Store buffer allocation exists; drain uses `lsu_store_req_*` but current
  harnesses may apply backend backpressure. The maintained core enables
  ordered-retire commit gating before the paired `drain*` lanes reach the
  selector and D-cache.
- Loads allocate a load queue entry and complete through `lsu_load_resp_*` /
  `lsu_load_complete_*`; the outgoing request uses `lsu_load_req_*`.
- No D-cache or DTCM request.
- No load data formatting.
- Alignment check exists and suppresses backend side effects, but precise
  architectural exception retirement is not implemented.
- No cache-maintenance execution.
- No memory exception reporting.

These are deliberate placeholders so `edge_scalar_pipe` depends on a stable LSU
subsystem boundary before the real LU/SU/STB/backend blocks are added.

## Tests

Module-local placeholder test:

```text
src/test-e3/edge_lsu/edge_lsu_placeholder_tb.v
src/test-e3/edge_lsu/edge_lsu_ordering_random_tb.v
src/test-e3/edge_lsu/edge_lsu_memory_random_tb.v
```

The test proves the wrapper preserves the old placeholder semantics for aligned
loads and stores, and that a store allocates then drains one STB entry while
giving future work a dedicated LSU subsystem target. Store formatter coverage
includes legal boundary placements at `SB@addr[2:0]=7`, `SH@6`, `SW@4`, and
`SD@0`, proving the high-byte masks and shifted data are not truncated. It
explicitly holds
`lsu_store_req_ready` and `lsu_load_req_ready` low to prove backend
backpressure holds the request beat and prevents premature load completion. It
also proves misaligned load/store operations report `lsu_misaligned_*` without
allocating load queue, store buffer, or backend request state, including the
lane1 case where an aligned lane0 load must still enqueue and complete. A
same-cycle redirect that kills a misaligned operation suppresses the wrong-path
fault report. That kill comparison uses modulo sequence age across wrap. The
test also proves that a
`seq_id/epoch/value` load response is converted into a domain-tagged scalar
load completion using the `rd/bank/domain/size` metadata retained by
`edge_load_queue`; the scalar pipe routes it to GPR or FPR writeback. The same test also covers
redirect pressure before D-cache integration: an older delayed load response must
still complete after a redirect drops a younger outstanding load, the younger
response must not complete after the flush, and a same-cycle flushed store must
not leave a wrong-path STB entry to drain later.

The deterministic ordering scoreboard checks queue state transitions against
independent FIFO models. The deterministic memory differential runs 500
single/paired load or store batches against a 256-byte golden memory image. It
randomizes byte/half/word/dword widths, signed and unsigned loads, addresses,
payloads, lane replay, and backend backpressure; accepted store strobes update
the byte model and every load completion must match the resulting golden value
and retained `seq_id/rd/bank/size` metadata. The baseline waits for each batch
to drain, matching the current conservative store-before-load issue policy;
future no-overlap bypass work will extend this same oracle to mixed outstanding
store/load streams.

The memory differential also includes mixed outstanding ordering cases before
the randomized batches. One holds an accepted older load while selectively
flushing a younger queued store in the same cycle as the load response, proving
that the killed store has no memory side effect. Another allows a younger store
to drain to the same address while the older accepted load response is delayed;
the load must return the value captured at request acceptance and the final
memory image must contain the younger store.

Before exercising RTL traffic, the same testbench validates the future
store-to-load forwarding oracle. Directed cases cover no overlap, full cover,
partial-byte merge, signed-byte extension, and two older stores where the
youngest matching store wins each byte. Another 500 deterministic random cases
build one to four ordered pending stores, apply their byte strobes to an
independent shadow memory, and compare that image against the per-byte overlay
oracle. The run requires nonzero no-overlap, full-cover, and partial-overlap
coverage before reporting pass.

The manual scalar-FPU random differential flow additionally mixes naturally
aligned FLH/FLW/FLD and FSH/FSW/FSD with fast, FMAC, and slow FP execution. Its
one-cycle memory responder applies store byte strobes, returns FIFO load data,
waits for both LSU queues to drain, and compares final GPR, physical FP32 FPR,
and memory images against a RISCV-specialized SoftFloat oracle. Generated and
failure-replay memory images remain under the build tree.

Planned nonblocking issue model test:

```text
src/test-e3/edge_lsu/edge_lsu_issue_model_tb.v
```

The intended test is documented in
`src/test-e3/edge_lsu/edge_lsu_issue_model_tb.v.md`. The load queue now exists, so the
remaining work is to turn that model into an enabled regression that composes
scalar pipe issue, LSU queueing, and dependent-source WBT release.
