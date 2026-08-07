# edge_dcache_banked_data_array.v

## Purpose

Macro-friendly data-array leaf for the Edge D-cache throughput slice. This file
replaces the original single-array `edge_dcache_data_array.v` implementation
inside `edge_dcache`.

The block proves the SRAM composition and conflict contract before replacing
the first-slice data array.

## Organization

The array uses four 64-bit fixed-port banks:

```text
bank0 bank1 bank2 bank3
```

Two banks form one logical 128-bit cache beat:

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

`line_index` selects the 64-byte line. `beat_index[1]` selects the row within
the half-bank pair, and `beat_index[0]` selects banks `0/1` versus `2/3`.

## Phase Ownership

The owner provides `phase`:

```text
phase = 0:
  LSU owns banks 0/1
  MEM owns banks 2/3

phase = 1:
  LSU owns banks 2/3
  MEM owns banks 0/1
```

When `mem_valid=0`, `lsu0_ready` / `lsu1_ready` may use either half-bank because
no refill/writeback/clean access needs the reserved half. When `mem_valid=1`,
they are asserted only when the corresponding 64-bit LSU lane targets the
phase-owned half-bank. `lsu1_ready` is additionally deasserted
when both LSU lanes target the same physical 64-bit bank in the same cycle. Lane0
wins that fixed conflict; lane1 waits until the physical bank is free. With an
idle MEM port it may replay on the next cycle regardless of phase. With active
MEM traffic it waits until that half is LSU-owned under the alternating phase.
`mem_ready` is asserted only when refill/writeback/clean traffic targets the
opposite half. This idle-MEM release does not create a second port or permit an
LSU/MEM same-bank collision.

In the integrated D-cache controller, these ready outputs are treated as the
leaf's local slot-eligibility proof, not as a dynamic arbitration result to feed
back through LSU queues. The controller recomputes the same phase/address-half
predicate locally so request ready does not depend on tag lookup or load-queue
completion feedback.

## Interface

The LSU side carries two independent 64-bit lane accesses:

```text
lsu0_valid / lsu1_valid
lsu0_ready / lsu1_ready
lsu0_write / lsu1_write
lsu0_line_index / lsu1_line_index
lsu0_beat_index / lsu1_beat_index
lsu0_word_hi / lsu1_word_hi
lsu0_wdata[63:0] / lsu1_wdata[63:0]
lsu0_wstrb[7:0] / lsu1_wstrb[7:0]
lsu0_rvalid / lsu1_rvalid
lsu0_rdata[63:0] / lsu1_rdata[63:0]
```

The MEM side still carries one 128-bit logical beat access for refill and
writeback:

```text
mem_valid
mem_ready
mem_write
mem_line_index
mem_beat_index
mem_wdata[127:0]
mem_wstrb[15:0]
mem_rvalid
mem_rdata[127:0]
```

LSU reads return one cycle after each accepted lane read. Writes update byte
lanes at the accepted clock edge. Simultaneous LSU and MEM accesses can proceed
when they target opposite phase-owned halves. Two LSU lanes can proceed in the
same cycle when both target the LSU-owned half and different physical banks;
their row addresses do not need to match.

## Non-Goals

- no tag/valid/dirty metadata
- no miss/refill controller
- no store-to-load forwarding
- no redirect handling
- no replacement policy or associativity

Those behaviors remain owned by `edge_dcache`.

## Tests

`edge_dcache_banked_data_array_tb.v` proves:

- simultaneous LSU half0 and MEM half1 writes in phase 0
- simultaneous LSU half0 and MEM half1 reads in phase 0
- simultaneous LSU lane0/lane1 accesses to different banks in the owned half
- fixed lane0 win when both LSU lanes target the same physical bank, with lane1
  held through the intervening MEM-owned phase and accepted on the next
  LSU-owned phase
- phase mismatch stalls until the owner flips phase
- byte-lane masked 64-bit writes preserve untouched lanes
