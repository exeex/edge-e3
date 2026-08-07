# edge_tensor_unit.v

## Purpose

Tensor unit wrapper for the dual-stream target. Tensor remains a DTCM client and
may coexist with Edge Vector as another data-plane engine.

This file documents how the current tensor bring-up path should be referenced by
the new target; it does not require the tensor unit to be integrated into the
first Edge Vector smoke.

`edge_tensor_unit` is behind `edge_accel_pipe`. The accelerator pipe owns queueing,
scalar capture readiness, control-dependency waits, DMA routing, descriptor
visibility, and `TENSOR_TOKEN` done reporting. This file focuses on the tensor
datapath wrapper and descriptor behavior once commands are allowed to reach the
unit.

## Reference RTL And Docs

Edge-owned source files:

```text
src/edge-e3/edge_tensor_unit/rtl/edge_bf16_int8_dot8.v
src/edge-e3/edge_tensor_unit/rtl/edge_bf16_int8_dot8_tree.v
src/edge-e3/edge_tensor_unit/rtl/edge_bf16_add_comb.v
src/edge-e3/edge_tensor_unit/rtl/edge_bf16_int8_dot8x8_psum.v
src/edge-e3/edge_tensor_unit/rtl/edge_bf16_int8_mul.v
src/edge-e3/edge_tensor_unit/rtl/edge_tensor_iopsum_remux.v
src/edge-e3/edge_tensor_unit/rtl/edge_tensor_wld_reg.v
src/edge-e3/edge_tensor_unit/edge_tensor_unit.v
doc/inst_spec/edge_tensor.md
doc/microarch/dtcm.md
doc/microarch/dtcm_schedule.md
```

## Relationship To Dual-Stream Vector

Tensor and Edge Vector are both data-plane engines, but they are not the same
instruction stream:

```text
Edge Vector:
  64-bit custom vector instruction stream from edge_predecoder
  uses inst[6:0] = 7'b0111111 and the Vector opcode8 stream select
  owns VR and Edge Vector fused ALU/DTCM commands

Tensor:
  64-bit Edge Tensor command stream from edge_predecoder
  uses inst[6:0] = 7'b0111111 and the Tensor/DMA opcode8 stream select,
  shared with DMA but separated by tensor subop fields
  owns tensor-local buffers/datapath
  owns pending/job descriptor state for tensor.start
  uses DTCM leases for IO/psum and WLD
```

The second-parcel instruction byte is `opcode8 = inst64[39:32]`; `opcode8[7]`
prevents the predecoder from confusing Tensor or DMA commands with Edge Vector
commands.
Tensor remains a datapath unit behind the accelerator command pipe.

## Command Interface

Initial behavior mirrors the current tensor instruction surface, but the target
encoding is 64-bit Edge Tensor:

```text
tensor.setcsr
tensor.wld
tensor.wld_t
tensor.sld
tensor.setin
tensor.setout
tensor.setpsum
tensor.setn
tensor.wld_wait_dma
tensor.start
tensor.start_scale
tensor.sync
```

The C++ software-facing surface is the Edge custom helper API. These controls
are tensor commands, not full CP0 CSR semantics. The current helper
implementation may still use provisional custom0 inline asm during bring-up,
but `.cpp` call sites should continue to see the same helper names and
arguments. When the new assembler support lands, the helper implementation
should change its inline asm to emit the 64-bit Tensor/DMA `opcode8` stream
encoding while preserving the C++ helper API.

## Descriptor Model

Tensor configuration commands build a pending descriptor for the next
`tensor.start`:

```text
pending_descriptor:
  dtype / wtype / tensor mode fields
  input / output / psum base pointers
  weight load pointer and WLD mode
  run count n
  quantization fields such as per-vector scale
  future convolution shape/stride/padding/tile/scheduler fields
```

`tensor.setcsr`, `tensor.setin`, `tensor.setout`, `tensor.setpsum`,
`tensor.setn`, and WLD-related setup commands update fields in this pending
descriptor. Pointer/run-count fields are one-way parameter writes. If a field
is not rewritten before the next `tensor.start`, the previous pending value is
reused. A WLD command is different: acceptance snapshots its pointer,
transpose bit, and current `wtype`, so a younger `tensor.setcsr` cannot alter an
in-flight or queued WLD's format and fetch length.

Set-style descriptor writes consume their scalar capture when the set command
is accepted by the accelerator pipe. They do not wait for a later `tensor.start` or
for the current tensor job to finish. The tensor unit therefore keeps separate
pending and active copies of the IO descriptor fields:

```text
pending config: updated by tensor.setin/setout/setpsum/setn
active config:  snapshotted from pending config by tensor.start
queued start:   one next job descriptor accepted while active is still running
```

While one active job is running, younger set commands may continue to update
the pending config for the next start. DTCM stream address generation must use
only the active copy that was captured by the accepted start.

The tensor unit also has a one-entry queued start descriptor. If a weight tile
has completed WLD and the queued slot is empty, `tensor.start` may be accepted
while the current tensor stream is still active. That accepted start snapshots
the current pending IO pointers, run count, tile mode, and the loaded weight
buffer into the queued descriptor. When the active stream drains, the queued
descriptor launches immediately on the next stream handoff; phase-lock channel
selection is still computed at the real launch phase, not at the earlier command
accept phase.

The pending and queued start descriptors also store the command sequence id and
epoch. `tensor_start_retire_valid` is asserted only on the corresponding
`engine_start`, whether launch is direct, pending, or a queued handoff. This
allows the command to enter unit-owned storage early without retiring before it
can actually launch, and keeps start completion separate from ordinary tensor
pipe completion events.

The queued start consumes the loaded weight buffer. Because the current tensor
core has only two physical weight buffers, `tensor.wld` is blocked while both
one active job and one queued job own the A/B buffers. After the queued job
launches, the non-active weight buffer is available for the next WLD.

`tensor.wld<EDGE_TENSOR_LOAD_OPT_REUSE>` creates an explicit token for the
current active weight slot without issuing DTCM traffic or switching the
ping-pong selector. A normal WLD creates a token for the newly filled slot.
Every start consumes one of those tokens, and queued descriptors snapshot the
chosen slot. The legacy start reuse bit is ignored. Llama uses explicit reuse
WLDs in elementwise loops, RMSNorm reduction blocks, and for RoPE K after Q.

Multiple WLD commands before a start use last-write-wins descriptor semantics.
The dot8x8 fill boundary protects a completed pending buffer from direct
overwrite, so the bank16 wrapper first rotates an unused pending tile active
when the engine is idle and no pending or queued start owns it. The following
WLD then fills the other physical buffer. This replacement rotation is never
allowed while compute is active or while an accepted start is waiting for the
loaded tile.

Scale state is separate from weight state and is also double buffered.
`tensor.sld` reads one 128-bit vector of eight BF16 values into the inactive
scale buffer. `tensor.sld<EDGE_TENSOR_LOAD_OPT_REUSE>` snapshots the active
scale slot without a read or selector switch. Either form produces a pending
scale token consumed by the next scale-enabled start.
The scale vector and enable bit are snapshotted into pending/queued start state,
so a younger SLD cannot change a job that has already launched. Scale-disabled
starts keep the original bypass latency; scale-enabled starts use the extra
multiply stage without inserting bubbles between vectors.

`tensor.sld_circular` feeds a small FIFO from 16-byte circular-DMA entries.
Start mode bit 3 selects that FIFO, gates compute when it is empty, and pops
exactly one distinct scale vector for each vector compute fire.

`tensor.sld_stream(ptr)` configures the direct DTCM producer. At the next
scale-stream start it autonomously issues `vector_count` sequential 128-bit SLD
reads, advancing the DTCM word address by two for each vector.

For every output lane, the scaled path computes
`scale * dot(W, x) + psum`. SLD state is independent of weight state. The Llama
elementwise multiply and RMSNorm implement square/scale phases by loading an
identity W tile and supplying the lane multiplier through SLD; their C++
sequences synchronize after normal SLD and use explicit SLD reuse tokens where
the same vector serves multiple starts.

The core-level `tensor.wsld_circular` sequencer keeps the SLD and WLD modules
physically independent. For each 272-byte group it waits for SLD completion,
then submits four WLDs one at a time. The next WLD is not submitted until the
previous weight's `tensor.start` reaches actual engine launch, preventing the
existing last-write-wins WLD replacement rule from discarding a tile.

The bank16 engine uses a four-entry ordered input window. Within an active
descriptor it may fetch a younger vector whose bank pair is visible on the
current lower-path phase, but dot8 consumes the returned vectors strictly by
absolute vector index. A matching four-entry next-input window can prefetch
from the one-entry queued start while the active descriptor finishes. PSUM
reads start at the earliest fixed offset that selects a tensor channel
different from input. An eight-entry ordered PSUM FIFO holds responses until
the corresponding dot8 result reaches the add stage.

Each accepted input also pushes `{out_addr, scale_mode}` into a narrow
16-entry in-flight metadata FIFO. Dot8 completion moves the saved address and
result into an eight-entry output FIFO, which drains independently of the
active descriptor. Once all input and PSUM responses for a descriptor have
arrived, the next descriptor may launch while older results and output writes
remain in flight. Queued input prefetch never displaces a conflicting active
PSUM read or older output write; it uses only another visible lower-path bank
pair. Once the descriptor becomes active, its input stream has priority. A new
bypass stream also waits for older scaled results so its shorter output path
cannot overtake them. The former wide compute-address FIFO is not present;
output addresses are regenerated from the ordered consume index.

Descriptor address fields should be budgeted for a 1 MiB tensor-local address
window. The current demo integration instantiates a 128 KiB DTCM, so the wider
1 MiB address reservation is a descriptor/ISA constraint before the physical
DTCM port is widened.

This is important for per-vector quantization. Software may refresh scale
fields frequently for per-vector quant, but it does not need to refresh every
descriptor field for every weight tile. It can update only the fields that
change and keep using the previously written values for fields that stay valid.

`tensor.start` is the batch boundary:

```text
tensor.start:
  snapshot pending_descriptor into an immutable job_descriptor
  enqueue or launch one tensor job, up to one queued job behind active compute
  following tensor.set* commands update the next pending_descriptor
```

`tensor.start` is non-blocking after launch: its retiring `TENSOR_TOKEN` waits
only until the tensor unit can assert `engine_start`, not until tensor compute
finishes. If an older job prevents launch, the token remains incomplete while
the descriptor waits in unit-owned pending or queued state. After launch,
tensor execution continues independently and scalar retirement may progress.
`tensor.sync` is the tensor-stream ordering point whose `TENSOR_TOKEN` waits for
tensor completion.

## WLD And DMA Progress Dependency

Tensor WLD can depend on an older DMA transfer without exposing a scalar
`dma_byte_count` CSR. The dependency is described in the tensor stream:

```text
dma.start(weight_src, dtcm_weight_buf, weight_bytes) -> dma_tag
tensor.wld_wait_dma(dma_tag, required_bytes)
tensor.wld(dtcm_weight_buf)
```

`tensor.wld_wait_dma` is a tensor-pipeline ordering command. It records that the
following or associated WLD must not issue until the DMA engine reports at least
`required_bytes` visible for the matching `dma_tag`. The tensor/DMA pipeline is
responsible for tracking the DMA progress and releasing WLD. Scalar software
does not poll a DMA byte-count CSR for this path.

This keeps WLD overlap local to the tensor/DMA scheduler. `dma.sync` remains the
full-transfer ordering instruction when software needs global DMA completion.

Tensor configuration commands may be queued, renamed, coalesced, or reordered
before `tensor.start` as long as the snapshot observed by `tensor.start` matches
program order for each descriptor field. `tensor.start` itself must not cross
older descriptor writes, and younger descriptor writes must not modify an
already snapshotted `job_descriptor`.

Tensor commands on an unresolved predicted scalar path may be queued as
bookkeeping, but the tensor queue must not apply descriptor writes or accept
`tensor.start` until the protecting `CONTROL_DEP` resolves correct. Wrong-path
descriptor writes and starts are killed by epoch/sequence id.

The same rule applies to all tensor-visible work: before scalar branch/control
resolution, tensor may not start WLD, start compute, update pending descriptor
state, consume DTCM bandwidth, or report completion. Only queue/bookkeeping fill
is allowed.

## DTCM Client Ports

Tensor should keep separate DTCM scheduling classes:

```text
tensor_io_dtcm_client
tensor_wld_dtcm_client
```

The existing priority places Tensor IO/psum ahead of DMA and Tensor WLD behind
DMA. In the dualstream target, Edge Vector is planned below Tensor WLD unless
measurement shows vector should take a different priority.

## Interaction With Edge Vector

The first implementation should use explicit synchronization when tensor and
vector share DTCM buffers:

```text
tensor.sync before Edge Vector consumes tensor output
vector sync before tensor consumes vector output
```

`tensor.start` alone is not a buffer-visibility point.

More precise buffer-level hazard tracking can be added later.

## First Implementation Simplification

The current tensor unit is still a conservative proof datapath, but it is no
longer a placeholder wrapper: it owns the BF16xI8 dot8x8 block, the
double-buffered weight register path, Tensor IO lanes, the dedicated DTCM WLD
read client, and type-sized circular DMA/WLD entries. Remaining simplifications
are scheduling depth, packed setup, and broader golden coverage.

## BF16xBF16 And BF16xI8 Modes

The software-visible modes are selected with
`edge_tensor_setcsr<1, EDGE_TENSOR_WTYPE_BF16>()` and
`edge_tensor_setcsr<1, EDGE_TENSOR_WTYPE_INT8>()`. Both consume BF16 input and
psum and produce BF16 output. BF16 WLD fetches eight 128-bit beats (128 bytes);
I8 WLD fetches four beats (64 bytes) and converts signed I8 values exactly into
the unified internal BF16 weight fields. The current Llama C++ kernels select
BF16 WLD; compiler-side I8 packing exists but is not yet selected by runtime
dispatch.

`edge_bf16_int8_dot8` now has a module-local BF16 weight mode for KV-cache
matmul development. `weight_bf16_mode_i=0` preserves the original 64-bit INT8
weight input. When enabled, `bf16_weight_vec_i` supplies eight BF16 weights.
The multiplier remains one 8x8 significand multiply per lane; BF16 mode adds
weight sign/exponent handling and uses a signed 10-bit synthetic product
exponent so products ranging from subnormal through maximum finite BF16 can be
aligned before the shared adder tree.

Product alignment is a two-stage coarse/fine pipeline. The coarse stage shifts
by `8 * floor(exponent_delta / 8)` (`0/8/16/24`) and records the discarded
guard/sticky state. The fine stage shifts by `exponent_delta % 8` (`0..7`) and
performs the single final round-to-nearest-even operation. Deltas of 31 or more
produce zero, matching the previous one-stage shifter exactly. This adds one
cycle of latency while retaining one vec8 result per cycle; the 8x8 wrapper
delays psum, scale, and scale-enable by the same extra cycle.

The vec8dot primitive also provides a private reduction-sum path selected by
`tensor.start<imm8>` bit 4 (`EDGE_TENSOR_START_OPT_RSUM`). With
`rsum_enable_i`, every valid dot result is accumulated
in BF22 instead of being exposed to the psum path. `rsum_first_i` selects zero
as the accumulator input for the first row, and intermediate rows suppress
`out_valid`. `rsum_last_i` rounds the final BF22 value to BF16 and emits exactly
one result. These controls travel with their input through the dot pipeline, so
the primitive still accepts one row per cycle. In RSUM mode `tensor.setn`
defines the reduction length, all eight vec8dot lanes accumulate independently,
and the dot8x8 wrapper writes one contiguous BF16x8 vector at `tensor.setout`.
RSUM is a standalone no-psum mode: it performs no psum DTCM reads and does not
combine with scale or the other psum start options. The engine retains only one
output metadata entry and does not hand off to a younger start until the final
reduction result has left the dot8x8 pipeline.

The optional Q8 output scale uses the same synthesis-oriented BF16 product
representation as vec8dot. Eight lanes sanitize their two BF16 operands,
multiply fixed 8-bit significands, retain a signed 10-bit synthetic exponent,
and normalize with bounded fixed-width RNE logic. The scale unit remains fully
pipelined at eight products per cycle. It deliberately avoids 32-bit integer
temporaries, general barrel shifts, and dynamic masks; scaled psum metadata is
delayed alongside the two product stages. Scale mode retains its existing
one-cycle latency difference relative to the bypass output at the wrapper
interface.

## Unified BF16 Weight Buffers

`edge_bf16_int8_dot8x8_psum` internally stores both WLD formats in the same
double-buffered 8x8 BF16 weight fields. I8 fill mode retains the existing four
128-bit beats: every beat carries two signed I8 columns, and all 16 values are
converted exactly to BF16 as they are written. BF16 fill mode accepts eight
sequential 128-bit beats, one BF16 column per beat, using an internal 3-bit beat
counter rather than widening the existing external pair index.

After either fill mode, compute always uses the BF16-weight vec8dot path. The
WLD bridge now drives `weight_fill_bf16_mode_i` from the snapshotted command
format: `wtype=2` keeps the four-beat I8 conversion path, while `wtype=1` uses
eight BF16 beats. Its 8x8 staging array uses 16-bit slots so normal and
transpose drain share one element-level mapping; I8 slots carry the raw byte
to the existing fill converter, while BF16 slots carry the value directly.
