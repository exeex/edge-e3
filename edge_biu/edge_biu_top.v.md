# edge_biu_top.v

## Purpose

`edge_biu_top` is the first Edge external bus boundary. It gives the future
`edge_core_top` a C906-BIU-like place to connect core I/D cache miss traffic and
reserves a parallel DMA AXI master path before the final SoC shell is built.

The module is intentionally a small arbiter, not a full replacement for the
legacy C906 `aq_biu_top`. It exposes one AXI-like core master, one AXI-like DMA
master, and one AXI-like pad master.

## Parameters

- `ADDR_WIDTH`: address width, default 40 bits to match the inherited C906 pad
  address width.
- `DATA_WIDTH`: data width, default 128 bits to match the C906 BIU and planned
  DTCM/DMA beat width.
- `ID_WIDTH`: AXI ID width, default 8 bits.
- `LEN_WIDTH`: AXI burst length width, default 8 bits.

`DATA_WIDTH` must be byte aligned.

## Ports

The core master ports are named `core_*`. They are the placeholder target for
future Edge I-cache refill, D-cache miss, writeback, and uncached access paths.

The DMA master ports are named `dma_*`. They are reserved for the DTCM DMA
engine and are present from this first slice so the external bus boundary does
not need to be reshaped when DMA is connected.

The external pad ports are named `pad_*` and carry the selected request and
response traffic toward the eventual SoC shell or pad-level AXI fabric.

Debug owner outputs expose whether the read or write response path is currently
owned by DMA or by the core.

## Arbitration

Read address and write address channels arbitrate independently. Each side
allows one outstanding burst:

- DMA has fixed priority over core when both masters request an idle channel.
- A read owner is held from accepted AR until the `R` beat with `rlast` is
  accepted.
- A write owner is held from accepted AW until the matching `B` response is
  accepted.
- W data is forwarded only from the current write owner.
- R and B responses are routed only to the recorded owner.

The first slice does not support interleaved read responses, multiple
outstanding writes per master, write-data-before-address, or QoS/lock policy.
Those belong in the later product BIU once cache refill and DMA burst behavior
are measured.

## DMA Reservation

The DMA path is fully wired as an AXI master interface even before the Edge DMA
engine is connected. This keeps the planned DTCM DMA path compatible with the
existing non-coherent software contract:

- D-cache and DTCM DMA are not coherent.
- Software must clean cached DRAM sources before DRAM-to-DTCM DMA.
- Software must invalidate cached DRAM destinations after DTCM-to-DRAM DMA.

## Focused Test

`test/edge_biu_top_arb_tb.v` proves:

- core read pass-through and response routing
- DMA read priority when core and DMA request together
- read-channel busy backpressure
- core write data and B response routing
- DMA write priority and DMA B response routing
