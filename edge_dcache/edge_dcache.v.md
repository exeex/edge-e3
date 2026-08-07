# edge_dcache.v

## Purpose

D-cache wrapper for scalar memory traffic in the dual-stream target. D-cache is
owned by the scalar side and remains independent from vector DTCM bandwidth.

The first implemented RTL is a small SoC scalar memory backend adapter behind
`edge_lsu_top`, not the final inherited C906 D-cache wrapper. It consumes the
maintained LSU load/store request channels, applies store byte masks into a
simple SRAM-like model, returns formatted load data after a configurable
latency, and exposes external pause inputs that model future D-cache/BIU/DTCM
arbiter backpressure.

Every resident load hit allocates the four-entry `edge_dcache_hit_queue`;
synchronous data-array results return through slot tokens and the queue emits
one ordered completion per cycle. This removes ordinary hit latency from the
primary pending state, so phase-compatible resident hits can enter on
consecutive cycles. A same-line, different-bank lane1 resident hit may share
the lookup and allocates a second hit-queue slot; it is suppressed unless two
slots are available.

The hit-under-miss slice keeps one refill miss in `edge_dcache_mshr` while
admitting independently tagged hits to different resident cache indices.
Completed hits may respond before the older miss. Requests to the refill index,
another different-line miss, and a full hit queue remain blocked. This is
intentionally a one-entry, one-waiter MSHR; same-line merge is a later slice.
The MSHR owns request identity, redirect stale state, dirty-victim wait, refill
request/beat/error state, selected word, and completion. The D-cache parent
retains arrays, dirty writeback, formatting, and hit/miss response arbitration.
`debug_load_miss_pending` exposes MSHR activity to the LSU. The broader
`debug_load_pending` remains asserted for either the miss or any queued
resident hit so downstream response arbitration stays safe.

Stores that miss in a resident index with another valid tag use the same
one-entry MSHR to refill the target line before the store buffer is allowed to
merge bytes into the data array. Partial stores also refill on invalid clean
misses. The refill installs the target tag as a clean line and does not emit an
LSU load response; the held store request then replays as an ordinary resident
hit and marks the line dirty. This prevents store misses from allocating over
stale data-array bytes from a previous tag. Full 64-bit stores to invalid
clean indices remain the legacy first-slice allocate path.

VA invalidation updates tag and dirty metadata only when both the direct-map
index and resident tag match the requested address. An invalidate miss still
completes immediately, but it must not discard a different-tag dirty resident
that happens to share the same cache index.

A two-entry fall-through `edge_dcache_lookup_buffer` forms the LSU load
acceptance boundary. An empty buffer lets a launchable lane0 plus optional
lane1 bundle proceed without adding resident-hit dependency latency; a request
that cannot launch is captured before metadata and bank-phase retry. In both
cases `lsu_load_req_ready` depends only on buffer capacity, not tag hit, refill
state, hit-queue space, or SRAM phase. The controller parks an oldest miss while
the primary refill slot is busy and examines the younger entry on the following
cycle. Parked misses retry when the primary state drains, and an unpaired lane1
is promoted in place for replay as lane0.

Defining `EDGE_DCACHE_REGISTERED_LOOKUP` selects an experimental fully
registered boundary built from `edge_dcache_registered_lookup_buffer` and
`edge_dcache_lookup_scheduler`. It stores two bundles, classifies one stored
candidate per cycle, and allows a younger classified resident hit to pass an
older miss only while the single refill slot is busy. Metadata writes
conservatively invalidate stored classifications. A phase-blocked older hit is
kept ordered because the current hit queue reserves its slot only when the
data-array read launches; safely bypassing that hit needs a future ordered
hit-slot reservation interface.

The registered implementation is retained for directed A/B testing rather
than selected by default. Its extra capture/classify boundary removes the
fall-through load-hit path, but it also adds a cycle to dependent loads even
when no request is parked. CoreMark shows that latency is currently more
important than the remaining combinational-path reduction.

Defining both `EDGE_DCACHE_REGISTERED_LOOKUP` and
`EDGE_DCACHE_HYBRID_LOOKUP` selects the hybrid proof slice. When registered
storage is empty, the incoming bundle drives the existing metadata and bank
predictor path directly. A launchable resident hit therefore allocates the hit
queue without being captured. If that direct request cannot launch, it is
captured at the clock edge and subsequently uses registered classification and
the two-candidate scheduler. While any buffered entry exists, newer requests
append behind it rather than bypassing ordering at the LSU boundary.

The hybrid handshake deliberately distinguishes acceptance from storage:
`lsu_load_req_ready` continues to report buffer capacity, while the registered
buffer's push is suppressed when the direct bundle launches. Redirect,
metadata invalidation, cache-op drain, lane1 promotion, and miss parking then
reuse the registered-buffer rules.

A blocked direct request captures the metadata hit/dirty result together with
the request. It therefore becomes scheduler-ready on the next cycle instead
of spending another cycle repeating classification. If lane0 launches but a
non-pairable lane1 was accepted, lane1 is promoted into the captured bundle.
A pairable lane1 waits with lane0 when the second ordered hit-queue slot is not
yet available, preserving atomic pair launch.

Buffered hit admission uses `hit_queue_buffered_alloc*_ready`, a count-only
capacity view that excludes same-cycle completed-head pop lookahead. The
direct empty-buffer path retains the normal lookahead. This removes hit
completion state from the registered lookup-buffer pop path without changing
resident-hit throughput; only a buffered hit presented while the four-entry
hit queue is exactly full may wait for the registered count update.

The SoC bring-up cache capacity contract starts at:

```text
I-cache: 16KB
D-cache: 16KB
line:    64B
```

The same module contract allows the next capacity point without interface
changes:

```text
I-cache: 32KB
D-cache: 32KB
line:    64B
```

Under `IVERILOG_SIM`, unsupported capacity values fail simulation so accidental
test configurations do not drift away from the SoC target.

## Reference RTL

Existing sources to study before implementation:

```text
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_dcache_top.v
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_dcache_data_array.v
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_dcache_tag_array.v
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_dcache_dirty_array.v
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_lsu_lfb.v
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_lsu_stb.v
EDGE_RTL_FACTORY/gen_rtl/lsu/rtl/aq_lsu_pfb_top.v
```

## Interface

Parameters:

```text
SEQ_ID_WIDTH
EPOCH_WIDTH
VALUE_WIDTH = 64
ICACHE_BYTES = 16384
DCACHE_BYTES = 16384
LINE_BYTES = 64
LOAD_LATENCY
```

`ICACHE_BYTES` is carried by this first backend as part of the shared SoC cache
configuration contract even though instruction fetch is owned by
`edge_ifu_icache`.

From scalar LSU:

```text
dcache_req_valid
dcache_req_ready
dcache_req_cmd
dcache_req_addr
dcache_req_wdata
dcache_req_wstrb
dcache_req_size
dcache_req_seq_id
```

To scalar LSU:

```text
dcache_resp_valid
dcache_resp_seq_id
dcache_resp_rdata
```

Implemented first-backend ports map directly to `edge_lsu_top`:

```text
lsu_load_req_valid
lsu_load_req_ready
lsu_load_req_seq_id
lsu_load_req_epoch
lsu_load_req_addr
lsu_load_req_size
lsu_load_req_signed
lsu_load_req1_valid
lsu_load_req1_ready
lsu_load_req1_seq_id
lsu_load_req1_epoch
lsu_load_req1_addr
lsu_load_req1_size
lsu_load_req1_signed
lsu_load_resp_valid
lsu_load_resp_seq_id
lsu_load_resp_epoch
lsu_load_resp_error
lsu_load_resp_value
lsu_store_req_valid
lsu_store_req_ready
lsu_store_req_seq_id
lsu_store_req_epoch
lsu_store_req_addr
lsu_store_req_size
lsu_store_req_data
lsu_store_req_wstrb
lsu_store_req1_valid
lsu_store_req1_ready
lsu_store_req1_seq_id
lsu_store_req1_epoch
lsu_store_req1_addr
lsu_store_req1_size
lsu_store_req1_data
lsu_store_req1_wstrb
cache_op_valid
cache_op_ready
cache_op_is_va
cache_op_kind
cache_op_addr
cache_op_seq_id
cache_op_epoch
cache_op_complete_valid
cache_op_complete_seq_id
cache_op_complete_epoch
clean_wb_valid
clean_wb_ready
clean_wb_addr
clean_wb_data
clean_wb_last
refill_req_valid
refill_req_ready
refill_req_addr
refill_resp_valid
refill_resp_ready
refill_resp_data
refill_resp_last
refill_resp_error
store_predict_phase
store_predict_mem_active
store_predict_backend_blocked
```

`backend_load_pause` and `backend_store_pause` are the first explicit SoC-side
backpressure hooks. Later D-cache tag/data refill, DTCM bypass, AXI/BIU
arbitration, and cache-maintenance flows should drive these decisions behind
the same ready/valid boundary.

`cache_op_*` is the scalar cache-maintenance command boundary from
`edge_scalar_pipe`. It accepts C906-style clean, invalidate, and
clean+invalidate placeholders decoded from `tests/software/include/edge_intrinsic.hpp`.
The current D-cache slice clears tag-valid and dirty metadata for VA invalidate
and VA clean+invalidate commands. VA clean checks the selected line's
tag-valid/dirty metadata and emits a 64B writeback stream as four 128-bit beats
on `clean_wb_*` for dirty hits. `cache_op_complete_*` returns the original
command sequence when a maintenance command is complete: non-dirty or
metadata-only operations complete one cycle after command acceptance, while a
dirty VA clean completes only after `clean_wb_complete`.
Dirty VA clean+invalidate uses the same writeback stream but retains an
invalidate-pending bit until completion, so the common writeback metadata path
cannot accidentally revalidate the line. All VA operations compare the full
resident tag: a same-index, different-tag alias completes without writeback or
metadata mutation, including clean and clean+invalidate.

The `clean_wb_*` stream is the first external writeback boundary. It carries the
64B line base plus 16B beat offsets in `clean_wb_addr`, packed little-endian
64-bit words in `clean_wb_data`, and marks the fourth beat with
`clean_wb_last`. `clean_wb_complete` acknowledges that the core-side write path
has accepted the last beat response; the D-cache keeps the line dirty until that
completion arrives.

`refill_req_*` / `refill_resp_*` is the first external read/refill boundary. A
load miss emits one 64B line-base request. The core adapter converts it to a
four-beat 128-bit BIU read burst, and each response beat refills two 64-bit
data-array words. The missed load completes after the final refill beat updates
tag-valid metadata and captures the requested word. `refill_resp_error` is
accumulated across the burst. A failed refill is drained but never installs
valid tag metadata; `lsu_load_resp_error` accompanies the original load's
sequence and epoch so LSU can finish ownership and report the asynchronous
machine error.

When a load miss targets an index holding a valid dirty line with a different
tag, the backend first emits that resident line on the same `clean_wb_*`
writeback stream. This victim writeback uses the resident tag and requested
index to form the old line base address. After `clean_wb_complete`, the backend
issues the refill for the new miss address and completes the original load.

When a store drain targets an index holding a valid dirty line with a different
tag, the backend holds `lsu_store_req_ready` low and emits the same resident-line
victim writeback before accepting the store. The store-buffer request remains
visible until `clean_wb_complete` clears the old dirty metadata; only then may
the store update the data banks and install its new dirty tag. Store-triggered
victim writebacks do not generate `cache_op_complete_*`.

To external memory/BIU:

```text
axi/ar/aw/w/r/b or inherited BIU cache bus
```

## Coherence Contract

D-cache is not coherent with DTCM or DTCM DMA. Software or explicit cache
maintenance instructions must handle external-memory buffers used by DMA.

The first dual-stream target should keep the inherited C906 D-cache maintenance
instruction behavior available to scalar/control software. Software tests use
the wrappers in `tests/software/include/edge_intrinsic.hpp` rather than spelling
the instructions at each call site:

```text
edge_dcache_clean_range(ptr, len)
edge_dcache_invalidate_range(ptr, len)
edge_dcache_clean_invalidate_range(ptr, len)
```

These wrappers are currently backed by C906-style `dcache.cva`,
`dcache.iva`, and `dcache.civa` encodings emitted with `.insn`. They are the
software-visible way to make external-memory buffers safe around DMA.

Current software-facing rules are documented in:

```text
doc/inst_spec/dtcm_dma.md
```

## Dual-Stream Rule

Edge Vector memory traffic must not consume D-cache ports. This preserves the
main architectural advantage of the dual-stream target:

```text
scalar LSU -> D-cache / external memory
vector VLSU -> DTCM
```

## First Implementation Simplification

The first target uses `edge_dcache.v` as a deterministic scalar backend model
instead of immediately wrapping the full inherited D-cache. Cache maintenance
instructions may remain scalar/control instructions. They are not issued by
Edge Vector and do not make D-cache/DTCM coherent automatically; software
chooses the maintenance point.

The backend is now split into C906-inspired data, tag/valid, dirty-array, and
pair-predictor slices. This preserves the current SRAM-like execution model
while making metadata ownership and bank/phase policy explicit before adding
broader cache-maintenance execution, victim/writeback, and BIU arbitration
logic.

Unsupported D-cache wrapper states should fail simulation in the RTL or
testbench. Refill read errors now propagate to LSU, but the first slice still
does not define firmware-visible D-cache error CSRs or a retry protocol.

Current simplifications:

- split data, tag/valid, and dirty arrays; tag/dirty metadata is maintained on
  stores and used for load hit/miss, VA cache-maintenance lookup, and refill
  completion
- `edge_dcache_pair_predictor` owns the combinational paired-lane policy from
  `addr[4:3]`, phase, same-line hit facts, and controller blocking state. It
  does not understand ISA misalignment or split/merge; LSU must present legal
  aligned or sliced memory micro-ops.
- `store_predict_phase`, `store_predict_mem_active`, and
  `store_predict_backend_blocked` expose the store-side phase/cache-state
  summary to the upstream memory selector. The selector uses the same dynamic
  idle-MEM policy before allowing STB drain; D-cache keeps this local predictor
  as the final backend acceptance check.
- the data array is now backed by the standalone 4 x 64-bit banked leaf. The
  controller accepts a lane1 LSU request only when lane0 has already selected a
  hit/same-line bank slot that can safely pair with it. Its LSU load/store ready
  decisions are phase-slot eligibility checks from the request address, not
  dynamic arbitration through the data-array leaf.
- resident load responses use the single ordered LSU response channel. Every
  hit, including both lanes of a pair, carries its own seq/epoch metadata in
  the four-entry hit queue and returns at most one completion per cycle
- redirect marks matching-epoch pending loads and hit-queue entries younger
  than the boundary stale using modulo sequence age. Lookup/refill may finish
  normally, but stale responses are not exposed to LSU. This prevents aliasing
  when a later request reuses the same `(seq_id, epoch)` tag
- paired stores update data through independent 64-bit banks when both stores
  hit the same line and different physical banks; metadata is updated once for
  the line
- VA invalidate and VA clean+invalidate clear the selected line's tag-valid and
  dirty metadata; a later CPU load refills the line from BIU
- VA clean dirty hits emit a four-beat 128-bit writeback stream on
  `clean_wb_*`; dirty is cleared and scalar cache-op completion is reported
  only after `clean_wb_complete`
- a load miss that replaces a valid dirty line with a different tag first
  writes back the dirty victim, then refills the requested line
- a store to a different tag at a dirty resident index first writes back the
  dirty victim while holding the store-buffer drain request, then accepts the
  store as the new dirty resident line
- under `IVERILOG_SIM`, the backend can still preload from the same `+mem128` /
  `+mem128_words` image used by the Edge SoC runner for local smoke coverage,
  but load misses now use the explicit refill boundary
- the primary pending slot owns only one outstanding refill miss. All resident
  hits use four queued completion entries; phase-compatible scalar hits can
  allocate on consecutive cycles, and a paired hit can allocate two entries in
  one cycle
- a two-entry fall-through elastic lookup buffer owns load acceptance and
  redirect cleanup;
  cache operations wait for it, the hit queue, and miss/writeback state to drain
- ordered stores through the LSU store-buffer drain channel
- lane1 does not allocate a miss, replace a line, walk a dirty victim, or cross
  to a different tag/index in this slice; it waits in the LSU queue and replays
  through the ordered lane0 path
- no DTCM-window decode yet
- no all-line walk yet

## Macro-Friendly 128-Bit Data Path Direction

The next D-cache performance slice should remain SRAM-macro friendly. Do not
model bandwidth by adding arbitrary asynchronous read ports to a reg array. The
data array should be expressed as a small composition of fixed-port SRAM banks,
with the controller owning bank selection, conflict detection, and replay.

The preferred first v2 shape is:

```text
capacity: 16KB data, with the existing 32KB capacity smoke point preserved
line:     64B
beat:     128b logical external/cache beat
data:     4 x 64b single-port/1RW SRAM banks
metadata: direct-mapped tag/valid plus dirty first; associativity is deferred
```

The logical 64B line is four 128-bit beats. Each 128-bit beat is composed from
two 64-bit banks:

```text
beat0 low64  -> bank0
beat0 high64 -> bank1
beat1 low64  -> bank2
beat1 high64 -> bank3
beat2 low64  -> bank0, next row
beat2 high64 -> bank1, next row
beat3 low64  -> bank2, next row
beat3 high64 -> bank3, next row
```

This preserves SRAM macro shapes while giving the scalar LSU a natural fast
path for the common adjacent-load case:

```text
ld rd0, 0(base)
ld rd1, 8(base)
```

When both loads target the same 128-bit beat and the tag lookup hits, the
controller reads the corresponding bank pair and returns both 64-bit values.

Use a deterministic two-phase half-bank scheduler to overlap LSU hit traffic
with refill/writeback/clean traffic without requiring dual-port banks:

```text
even cycle:
  LSU owns banks 0/1
  DRAM/refill/writeback owns banks 2/3

odd cycle:
  LSU owns banks 2/3
  DRAM/refill/writeback owns banks 0/1
```

When refill/writeback/clean traffic is active, a request targeting the
half-bank not owned by its side in the current phase waits or replays for one
cycle. When that MEM-side traffic is idle, the LSU may use either half-bank;
the fixed phase color remains available immediately when MEM traffic resumes.
Conflicts remain bounded and explicit:

- `load+load` or `store+store`: split into two independent 64-bit LSU bank
  accesses; both can issue in the same cycle when they target the LSU-owned
  half and different 64-bit banks
- same physical 64-bit bank: lane0 issues first and lane1 waits until the next
  LSU-owned phase for that half; the intervening cycle remains available to
  refill/writeback/clean traffic
- different half-bank while MEM active: wait/replay one cycle
- LSU store hit: treated as LSU-side bank ownership and conflicts with LSU load
  issue in that half
- refill/writeback/clean beat: treated as DRAM-side ownership and conflicts
  only with the same half in the same phase
- miss, victim writeback, cache maintenance, and redirect cleanup still own
  ordering; correctness beats overlap

`edge_dcache` owns the phase bit for this data path. The phase bit is a
free-running SRAM schedule color, not a request-grant state:

```text
phase 0: LSU bank0/1, MEM bank2/3
phase 1: LSU bank2/3, MEM bank0/1
```

The top-level D-cache controller computes slot eligibility directly from the
request bank bits and `phase_q` through `edge_dcache_pair_predictor`. The
banked leaf's `ready` outputs are useful for standalone proof, but the
integrated controller must not feed those outputs back into LSU request ready
decisions; doing so can recreate ready/tag/loadq combinational loops. A stage
farther from the SRAM access point may predict phase only across fixed-latency,
non-stalling segments. After any ordinary valid/ready stall boundary, recompute
slot eligibility from the current phase.

Tag/valid/dirty metadata should stay separate from data banks. The first
macro-friendly slice can keep direct-mapped metadata:

```text
tag index = addr[line_offset +: line_index_width]
tag value = addr[PA_WIDTH-1 : line_offset + line_index_width]
dirty     = one bit per line
valid     = one bit per line
```

If Edge later needs fewer conflict misses, associativity can be added by
replicating metadata per way and adding way selection/replacement. That is a
separate cache-miss-rate decision, not required for the first `64b x2` LSU bank
bandwidth slice.

## Tests

Module-local backend integration test:

```text
src/test-e3/edge_dcache/edge_dcache_backend_tb.v
```

The test composes `edge_lsu_top` with `edge_dcache`, proves the default
16KB+16KB capacity contract and a 32KB+32KB configuration smoke instance, holds
store drain under backend backpressure, holds load requests under backend
backpressure, returns formatted signed byte and doubleword load data, and proves
that dirty victim conflicts write back the resident line before refilling the
new line. It also proves that store-side dirty victim conflicts hold the
store-buffer request, write back the resident line, avoid cache-op completion,
and only then install the replacement store. It also proves that a backend
response for a flushed load does not produce an LSU load completion. It now also
covers paired same-line
different-bank `load+load` accept, same-bank lane1 load replay, paired
same-line different-bank `store+store` accept, different-line lane1 load/store
replay through the ordered lane0 path, backend-pause blocking of a paired load,
paired loads of the stored values, and four phase-compatible resident hits
accepted on consecutive cycles with ordered, uncorrupted completions. The
composed SoC Verilator benchmarks currently cover the paired lane through
recursive-DP and LSU-recursive software pressure cases.
