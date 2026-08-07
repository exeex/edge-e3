# edge_dma_read_fifo.v

## Purpose

Elastic AXI-read response storage between the DMA R channel and the rotating
DTCM write scheduler. It prevents temporary DTCM bank conflicts from directly
stopping read-address issue or losing returned data.

## Organization

The default FIFO contains 16 128-bit beats. Four 64-bit fixed-port banks form
two logical 128-bit halves:

```text
even beat -> bank0 + bank1
odd beat  -> bank2 + bank3
```

An input holding register absorbs an AXI response before an SRAM write. A
separate output holding register retains one SRAM result until DTCM accepts the
write. SRAM reads and writes proceed together when they select opposite bank
halves. A same-half conflict delays the read; the input holding register keeps
the AXI side decoupled during that cycle.

`occupancy` includes the input register, SRAM-resident beats, and the output
register. DMA read issue must reserve capacity for outstanding AXI responses in
addition to this occupancy.

## Handshakes

- Push occurs on `push_valid && push_ready`.
- Pop occurs on `pop_valid && pop_ready`.
- `pop_data` and `pop_wstrb` remain stable while `pop_valid && !pop_ready`.
- FIFO order is preserved across arbitrary output stalls and bank conflicts.

## Integration Rule

A circular entry becomes visible to Tensor WLD only after its final beat is
popped and the corresponding DTCM write is accepted. Enqueueing an AXI response
is not entry completion.
