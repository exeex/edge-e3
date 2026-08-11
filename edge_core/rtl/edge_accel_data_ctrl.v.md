# `edge_accel_data_ctrl`

This module is the shared Tensor/DMA data-control layer used by both
`edge_core_base` and `edge_lite_accel_platform`. It deliberately excludes the
instruction owner: the normal core supplies commands through its dual-issue
queue and snapshots, while edge-rv-lite supplies one held command at a time.

The controller owns the behavior that must remain identical after issue:

- direct, XY-strided, and circular DMA selection;
- the existing `edge_core_strided_dma_ctrl` instance;
- circular producer/ring accounting and DTCM stream commands;
- Tensor circular WLD, SLD, and combined WSLD scheduling;
- Tensor unit WLD/SLD command arbitration; and
- DMA start/sync readiness for accelerator and scalar requesters.

All command inputs are pulse-style requests accepted only when the matching
ready signal is asserted. The DTCM-facing DMA command is selected in this
priority order: product edge request, Tensor direct request, strided launch,
then scalar request. Circular DMA uses the dedicated two-word stream path.

Keeping this state machine below the issue-policy boundary means a feature or
bug fix to DMA/Tensor movement is implemented once. Lite may serialize command
production, but it does not carry a second implementation of DMA or circular
Tensor behavior.
