# edge_dma_a2d_stream.v

## Purpose

Credit-controlled, multi-outstanding single-beat AXI read engine for strided
and circular XY DMA. It separates address issue, ordered response capture, and
DTCM write acceptance.

Each accepted command emits one 16-byte AXI read burst. Commands use one fixed
AXI ID at integration, so responses are consumed in issue order. A shallow
descriptor FIFO retains the corresponding DTCM destination until the response
arrives. Returned data and destination metadata then enter
`edge_dma_read_fifo` and may wait independently for the rotating DTCM scheduler.

## Credits

The engine reserves one FIFO slot for every accepted AR:

```text
reserved = outstanding descriptors + buffered responses
```

New AR requests stop before `reserved` reaches `FIFO_DEPTH`; therefore every
outstanding response always has storage even if DTCM is temporarily blocked.

`beat_done` pulses only when the response beat is accepted by DTCM. Circular
entry accounting must use this pulse, not AR or R-channel acceptance.
