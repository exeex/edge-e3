# edge_accel_core_mux

This leaf adapts the normalized `edge_accel_io` stream to one of two mutually
exclusive fixed-latency cores. Owner zero selects ACTU; owner one selects CMPU.

For ACTU it forwards raw BF16 source zero and the low three mode bits without
any format conversion. A parameterized shift register aligns `last` with the
current nine-cycle ACTU output latency. ACTU has no job-start or output-ready
handshake. Any compatibility wiring required by an older internal ACTU port is
owned by an ACTU-local wrapper and is not part of this shared interface.

For CMPU it forwards job start, all three sources, linear index and last.
Source two is narrowed to the byte mask. Vector output and the four-field
reduction result packet route back to the normalized boundary unchanged.

The owner is descriptor metadata held stable by `edge_accel_io` until job
completion. This module has no owner arbitration, queues, DTCM ports,
descriptor registers, result CSRs, redirect, or flush behavior.
