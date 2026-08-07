# edge_actu_io

`edge_actu_io` is the first standalone DTCM stream adapter for ACTU. It is not
connected to `edge_core_top` yet.

## Purpose

The module converts a wide 128-bit DTCM beat stream into a stable
lane-vector ACTU element stream, and packs ACTU output elements back into
128-bit DTCM write beats.

The compute side is parameterized by `LANES` so the first hardware can run
`LANES=1` while preserving a clean boundary for a later dual-lane ACTU.

## Address Contract

`in_base_addr`, `out_base_addr`, `dtcm_rd_addr`, and `dtcm_wr_addr` are local
DTCM 64-bit word offsets, matching the tensor pointer decode convention.
The adapter aligns start addresses down to an even 64-bit word and increments
beat addresses by two words per 128-bit beat.

First-slice simplification: unaligned sub-beat starts are not supported. The
product stream path is BF16-only; BF16 elements are packed from the low bits of
each 128-bit beat.

## Data Modes

- BF16 elements are 16 bits per element, and the low 16 bits of each 32-bit
  lane payload are used. A 128-bit DTCM beat contains eight elements.

The core-side data bus remains `LANES*32` bits so the compute lane can keep its
FP32-container boundary. The first area target has no stream dtype select.

## Handshake

`start_valid/start_ready` snapshots input/output base addresses and
`n_elements`. `start_ready` is high only while idle.

The DTCM read side is a one-outstanding request interface:

```text
dtcm_rd_req && dtcm_rd_ready -> request accepted
dtcm_rd_rvalid              -> matching 128-bit response
```

The read response is unpacked into an element FIFO. The FIFO hides normal DTCM
latency and lets the ACTU core consume one or more elements per cycle according
to `LANES`.

The first product default uses a 16-entry element FIFO. A 128-bit BF16 beat
contains eight elements, so 16 entries allow the adapter to request the next
beat while the current beat is being drained. An 8-entry FIFO is area-smaller
but can bubble with the current one-outstanding read contract.

The core input stream uses per-lane valid and ready masks. Elements are ordered
from lane 0 upward; the adapter only pops a contiguous accepted lane prefix.

The core output stream uses the same contiguous-prefix rule. Output elements
are packed into 128-bit write beats. Full beats use all byte strobes; the final
tail beat emits only the valid element bytes.

`done_valid` pulses when all reads have returned, all input elements have been
offered/accepted, all output elements have been accepted, and all packed DTCM
writes have committed.

## First-Slice Non-Goals

- No multi-outstanding read tag FIFO yet.
- No direct bank16 native lower-path scheduler wiring yet.
- No tensor/ACTU lower-path arbitration yet.
- No unaligned sub-beat pointer support.
- No command descriptor register file; this is the IO leaf below the future
  command unit.

## Tests

- `src/test-e3/edge_actu/edge_actu_io_tb.v`
  proves BF16 packing/tail strobes and a `LANES=2` BF16 stream boundary.
