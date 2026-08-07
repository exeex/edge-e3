# edge_ifu_predecode_frontend.v

The wrapper forwards the depth-2 reverse-snapshot allocator handshake to the
predecoder. `accel.getcsr` dispatch is therefore blocked before token
consumption when no ID is free, and the accepted allocation's sequence/epoch
are returned to the core-owned reverse snapshot table.

## Purpose

Maintained post-fetch IFU boundary that accepts 64-bit chunks from
`edge_fetch_packet_fifo` and owns token assembly plus predecode/dispatch.
External users do not observe the former tokenizer token metadata interface.

The fused block implements the former tokenizer parcel queue directly beside
the predecoder owner. There is no tokenizer instance or external typed-token
interface in the new path. The existing predecoder dispatch engine remains an
internal instance for the first migration slice; its token signals are local
implementation wires that can now be collapsed without changing core wiring.

## Fetch input

`fetch_block_pc`, `fetch_first_word`, `fetch_bits[63:0]`, and `fetch_epoch`
use ready/valid flow control. `fetch_first_word=1` means only the upper 32-bit
parcel is valid. A low half of a 64-bit instruction remains pending until the
next chunk supplies its high half.

Fetch readiness uses registered parcel-queue capacity. Parcels consumed by
decode release their slots for the following cycle, keeping downstream Tensor
command backpressure out of a combinational round trip through the fetch path.

## Redirect

`redirect_flush_valid` has priority in both ingress assembly and predecode
state. It clears pending parcels, scalar holds, issue windows, and capture
mapping state. `redirect_new_epoch` seeds the next frontend sequence-id epoch.

## Focused contract

The focused test drives scalar pairs, complete and cross-chunk 64-bit
instructions, downstream backpressure, redirects, and deterministic refill
pressure directly into this block. It checks that both scalar and vector
dispatch continue to make progress without retaining a legacy reference path.
