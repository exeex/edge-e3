# edge_dtcm_subsys.v

## Purpose

`edge_dtcm_subsys` is the Edge-owned wrapper around the maintained StarEdge
DTCM SRAM fabric. The current implementation splits the SRAM-door traffic into
an upper scalar/DMA path and a lower tensor-native path while exposing a stable
Edge boundary for:

- scalar LSU DTCM requests
- software/CSR-style DMA start requests
- tensor native bank requests
- one DMA AXI master toward `edge_biu_top`

The wrapper also exports `actu_last_sum_bits` and CMPU's four completed
reduction values as read-only sources for the core reverse-snapshot/get-CSR
path. DTCM does not own scalar retirement or reverse-snapshot allocation.

Tensor DTCM clients are handled inside `edge_dtcm_subsys_core` through native
bank16 channels owned by the tensor-side client logic. ACTU and CMPU share one
`edge_accel_io` beat client behind the existing lower-path bank16 adapter; the
legacy ACTU command frontend selects owner 0 until CMPU instruction decode is
connected. Edge Vector DTCM clients are still outside this slice and should be
added at this wrapper boundary instead of wiring new clients directly into the
core DTCM fabric.

The wrapper also preserves tensor-start retirement identity across the bank16
unit boundary. `cmd_start_seq_id/epoch` enter with each accepted start
descriptor, and `tensor_start_retire_valid/seq_id/epoch` return only when that
descriptor reaches the unit's actual `engine_start` event.

## Reference RTL And Docs

Edge-owned sources:

```text
src/edge-e3/edge_dtcm_subsys/edge_dtcm_subsys.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_subsys_core.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_arb.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_bank16_raw_fabric.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_other_bank16_adapter.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_bank_arb.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_bank_pair_slice.v
src/edge-e3/edge_dtcm_dma/edge_dtcm_dma.v
src/edge-e3/edge_dtcm_dma/edge_dma_read_fifo.v
src/edge-e3/edge_dtcm_dma/edge_dma_a2d_stream.v
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_addr_hit.v
doc/microarch/dtcm.md
doc/microarch/dtcm_schedule.md
```

## Client Ports

The dual-stream target should expose distinct DTCM clients:

```text
scalar_lsu_dtcm_client
edge_vector_dtcm_client
dma_dtcm_client
tensor_io_dtcm_client
tensor_wld_dtcm_client
```

The current RTL implements `scalar_lsu_dtcm_client`, DMA, Tensor IO lanes, and
Tensor WLD. Edge Vector clients are still tied inactive inside the wrapper.

## Physical Model

Follow the existing StarEdge DTCM model:

```text
16 logical 64-bit banks
1 x 1024x64 SRAM macro per bank
128 KiB default physical capacity
8 logical 128-bit channels
2 banks per channel per cycle
channel-to-bank mapping rotates every cycle
```

The DTCM address window is a fixed SoC memory-map input in the maintained Edge
slice. The integration supplies `edge_dtcm_base`, `edge_dtcm_mask`, and
`edge_dtcm_enable` to all DTCM hit/routing users. All DTCM clients use the same
decoded hit decision:

```text
dtcm_hit = edge_dtcm_enable
        && ((pa[39:0] & edge_dtcm_mask[39:0]) == edge_dtcm_base[39:0])
```

The current Edge SoC integration supplies reset defaults:

```text
edge_dtcm_base = 0x40000000
edge_dtcm_mask = 0xfffffe0000
edge_dtcm_enable = 1
```

Bare-metal images define matching `__edge_dtcm_base`, `__edge_dtcm_size`, and
`__edge_dtcm_mask` absolute linker symbols. Shared crt0 programs CSRs
`0x7d8..0x7da` before calling testcase or application code. C++ uses the linker
symbols instead of duplicating address constants.

`edge_dtcm_base` is therefore the already-aligned masked compare value, not an
arbitrary unmasked base address. SoC integration must keep `edge_dtcm_base`
consistent with the mask, because the hit rule compares
`pa & mask` directly against `base`; it does not compute `base & mask` again.

The core initializes the CSR-backed window from the integration defaults at
reset, then accepts machine startup writes to base, mask, and enable.

## Scheduling Contract

Circular XY A2D traffic uses a dedicated multi-outstanding reader beside the
legacy command-at-a-time DMA.  It issues ordered one-beat 128-bit AXI reads,
keeps one DTCM destination descriptor per outstanding response, and buffers
returned data in a shallow four-bank SRAM FIFO.  The two engines share the DMA
AXI read and DTCM write ports; legacy direct and D2A operations retain the
original engine.  Circular entry completion is reported only after the final
buffered beat is accepted by the DTCM scheduler.

The wrapper keeps the existing scalar, DMA, tensor IO, and tensor WLD port
shape for integration compatibility, but the live fabric is no longer a single
centralized tensor/DMA/LSU bus. At the SRAM doorstep, tensor uses native bank16
commands on the lower path. Scalar LSU, DMA, and Tensor SLD use the upper
fixed-phase path.

The compatibility bank arbiter assigns fixed rotating barrels:

```text
Scalar LSU: 1
DMA: 3
Compatibility tensor lanes: 0, 2, 4, 6
Compatibility Tensor WLD: 5
Tensor SLD: 7
```

At DTCM phase `phase`, barrel `b` reaches `(phase + b) & 7`. Upper-path LSU,
DMA, and SLD requests do not arbitrate with each other when they target their
fixed barrels. SLD is a read-only 128-bit client. A stream may wait 0-7 cycles
to phase-lock its first request; once the
request address pair advances with the DTCM phase, later aligned beats remain
full-rate.

Tensor lower-path scheduling is client-local. Tensor input, output, psum, and
WLD each own their own buffer/control path and generate raw bank16 requests near
the SRAM, so the live tensor route does not depend on the compatibility
128-bit central bus or the old lease-table winner selection.

## Dual-Layer DTCM

The live DTCM path is split into a raw storage layer and per-client adapters.
`edge_dtcm_bank16_raw_fabric.v` models the storage layer as 16 independent
64-bit SRAM banks and exports a 4-bit phase that advances by two banks each
cycle. This keeps the same conceptual stride as the old 8 x 128-bit channel
view, but the raw fabric has no 128-bit channel abstraction, client priority,
lease table, tensor/DMA/vector semantic knowledge, or latency compensation.

`edge_dtcm_arb.v` is now a composition wrapper, not the central scheduler. It
instantiates:

- native Tensor bank16 command muxing from the tensor unit.
- `edge_dtcm_other_bank16_adapter.v` for scalar LSU and DMA.
- `edge_dtcm_bank16_raw_fabric.v` for the actual SRAM macros.

The tensor unit computes its own 16-bank active mask and raw bank commands. The
scalar/DMA adapter does the same for non-tensor clients, tracks the one-cycle
SRAM response latency, and rebuilds the 64-bit LSU or 128-bit DMA payload
expected by its clients. The wrapper only prevents tensor/other bank-command
overlap by feeding the other adapter the tensor active mask and by muxing the
final SRAM-door command wires; it does not choose among clients by priority or
repair timing centrally. If a unit wants looser physical timing, it should add
pipeline/skid/FIFO compensation inside its own bank16 client logic.

The upper-path rotating bank scheduler uses a fixed-phase matcher rather than a
dynamic channel allocator:

```text
grant = request_valid && (((phase + fixed_barrel) & 7) == request_pair)
```

There is no per-cycle global winner selection, pending-channel latch, release
handshake, or priority reservation repair path in the upper bank arbiter. Timed
lease inputs remain accepted for bring-up compatibility, but they do not block
fixed-phase current requests. This materially reduces scheduler logic: the
large lease-table/allocator cone is removed from the live upper grant path, and
the remaining timing problem belongs to the clients that already hold stream
state.

## Test Coverage

`src/test-e3/edge_dtcm_subsys/dtcm_test_tb.v` now treats the monolithic tensor
placeholder path as obsolete. Its DTCM coverage focuses on:

- bank-pair SRAM behavior and byte masks
- fixed-phase bank arbiter behavior
- upper LSU/DMA/SLD fixed-lane phase lock and parallel issue
- direct LSU and DMA reads/writes through `edge_dtcm_arb`
- DMA AXI transfers, tails, bursts, and contention

Tensor lower-path correctness is covered by tensor-unit, tensor-pipe, and
software tensor tests that exercise the native bank16 path from the tensor side.

## Edge Vector DTCM Rule

Edge Vector load/store instructions must hit DTCM. A vector memory command that
does not hit the DTCM window is outside the first-slice contract and should fail
simulation in the vector DTCM path or testbench.

Vector DTCM stores are DTCM data movement. Software observes vector-produced
DTCM data only after an explicit ordering point such as `vector.sync` and a
scalar/DMA read path chosen by the test or debug code.

The first slice still does not issue vector DTCM traffic on an unresolved
predicted path. That rule is about wrong-path command issue and completion
bookkeeping, not about DTCM write visibility. Only scalar-side
fetch/decode/bookkeeping may speculate; vector DTCM traffic starts after the
protecting scalar control boundary has resolved.

## Scalar DTCM Rule

Scalar LSU DTCM hits are supported through the scalar client port. The first
implementation treats scalar DTCM access after `vector.sync` as the simple
debug/inspection path for reading vector-produced DTCM data back through scalar
code.

The DTCM subsystem does not infer this ordering from the scalar address hit by
itself. Software/compiler code must issue `vector.sync`; the predecoder turns
that instruction into a scalar/vector handshake before scalar DTCM inspection
proceeds.

## DMA And Coherence

DTCM and D-cache are not coherent. DMA is the explicit DRAM/DTCM mover and
software must perform D-cache clean/invalidate for external cached buffers.
DMA writes to DRAM are not enough for scalar software to observe new data
through D-cache. Software must use `dma.sync`, then perform the required D-cache
invalidate before consuming DMA-produced DRAM data.

Partial DMA progress for Tensor WLD is not a scalar CSR polling contract. It is
a tensor-stream dependency, for example:

```text
dma.start(weight_src, dtcm_weight_buf, weight_bytes) -> dma_tag
tensor.wld_wait_dma(dma_tag, required_bytes)
tensor.wld(dtcm_weight_buf)
```

The internal byte-progress signal used by the tensor/DMA pipeline must be
conservative: it may report late, but it must not release WLD before the bytes
are destination-visible to the intended DTCM-side consumer.

The first-slice environment may be ideal enough to omit a DMA smoothing buffer.
A product implementation can still add buffering to smooth burst gaps from
4 KiB boundary crossings or external bus congestion before data reaches DTCM
clients such as Tensor WLD. In either case, the progress counter reports factual
completed movement to the tensor pipeline; it is not derived from cycle-count or
bandwidth estimation and is not software-visible.

For first-slice software, the intended cache maintenance surface is the inherited
C906 D-cache control instruction set wrapped by
`tests/software/include/edge_intrinsic.hpp`:

```text
DRAM -> DTCM:
  clean DRAM source range
  dma.start
  dma.sync, or tensor.wld_wait_dma for tensor-side WLD overlap

DTCM -> DRAM:
  dma.start
  dma.sync
  invalidate DRAM destination range
```

## First Implemented Slice

`edge_dtcm_subsys.v` currently instantiates the Edge-owned copy of
`edge_dtcm_subsys` directly. It
normalizes the DMA AXI metadata that `edge_dtcm_dma` does not own:

- INCR burst
- 128-bit beat size
- ID zero
- non-cacheable/default protection fields

`edge_core_top` arbitrates this internal DMA AXI master against temporary
bring-up DMA injection ports before forwarding a single DMA master to
`edge_biu_top`.

The wrapper does not yet:

- provide a scalar-readable DMA completion CSR
- expose Edge Vector DTCM clients
