# edge_dtcm_dma.v

## Purpose

`edge_dtcm_dma` is the maintained Edge DMA transfer engine for explicit
movement between external AXI memory and the Edge DTCM fabric.

It is a leaf engine used by the DTCM subsystem. It is not itself the
programming-model wrapper; software-visible control, DTCM hit rules, and AXI
metadata normalization remain owned by `edge_dtcm_subsys` and
`edge_dtcm_subsys_core`.

## Ownership

Implemented RTL:

```text
src/edge-e3/edge_dtcm_dma/edge_dtcm_dma.v
```

Primary integration sites:

```text
src/edge-e3/edge_dtcm_subsys/rtl/edge_dtcm_subsys_core.v
src/edge-e3/edge_dtcm_subsys/edge_dtcm_subsys.v
doc/inst_spec/dtcm_dma.md
doc/microarch/dtcm.md
```

## Interface

Inputs:

- AXI ready/response channels for one DMA master
- DTCM read data / ready / rvalid handshake
- `start`, `start_axi_addr`, `start_dir`, `start_dtcm_addr`, `start_len`
- `clk`, `cpurst_b`

Outputs:

- AXI address / write / read issue signals
- DTCM request / writeback signals
- `dma_busy`, `dma_done`
- DTCM scheduler lease hints:
  `dma_lease_channel`, `dma_lease_cycles`, `dma_lease_delay`, `dma_lease_valid`

## Behavioral Contract

- Exactly one transfer may be active at a time.
- `start` is sampled in `S_IDLE`.
- `start_dir == 0` means AXI-to-DTCM.
- `start_dir == 1` means DTCM-to-AXI.
- `dma_busy` stays high whenever the internal state is not `S_IDLE`.
- `dma_done` is a pulse-like idle-visible completion condition after the final
  beat drains and no new `start` is present.

## Internal Model

The engine currently uses:

- one transfer state machine
- beat-granular AXI burst issuance
- a small internal FIFO for AXI-to-DTCM receive buffering
- a four-beat FIFO for DTCM-to-AXI write bursts
- consecutive rotating-channel DTCM read requests, with read responses captured
  independently before the AXI write burst starts
- rotating lease-phase hints derived from the starting DTCM pair

DTCM-to-AXI transfers fill one chunk with consecutive 128-bit DTCM reads, emit
one AXI `AW` whose `AWLEN` describes the chunk, stream the buffered `W` beats,
and wait for one `B` response per chunk. Keeping DTCM requests consecutive is
part of the correctness/performance contract: the DTCM address advances by one
bank pair on the same cadence as the rotating scheduler phase.

Key implementation states:

```text
S_IDLE
S_RD_REQ
S_RD_WAIT
S_WR_DTCM
S_DTCM_REQ
S_DTCM_WAIT
S_WR_REQ
S_WR_DATA
S_WR_RESP
```

## First-Slice Simplifications

- Single outstanding DMA command only.
- No exception or error reporting path.
- No reorder buffer or multi-transfer queue.
- AXI metadata such as burst type, cache/prot fields, size, and ID are not
  owned here; those are normalized by the wrapper.
- Invalid software direction policy is handled above this module.

## Focused Tests

Current focused consumers that must track this file path:

```text
src/test-e3/edge_dtcm_subsys/dtcm_test_tb.v
src/test-e3/edge_core/CMakeLists.txt
src/soc/logical/tb/CMakeLists.txt
```
