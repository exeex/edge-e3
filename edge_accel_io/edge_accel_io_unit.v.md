# edge_accel_io_unit

This integration boundary composes the shared three-source `edge_accel_io`,
the owner mux, the fixed-latency CMPU core, and the ACTU-local raw-BF16 wrapper.
The shared hierarchy contains no FP32 stream boundary or FP32 mode.

The unit accepts one normalized immutable descriptor and owns the only DTCM
beat interface. The ACTU scalar control is snapshotted atomically with an ACTU
start, so later pending-descriptor writes cannot affect an active job. For CMPU
reduction, the core result handshake simultaneously
completes IO and atomically updates four stable completed-result registers;
`cmpu_result_update` pulses for one cycle. A future get-CSR path reads those
registers without reaching into the running accumulator.

`actu_last_sum_bits` exposes the stable ACTU-local retained softmax sum for
integration/debug observation; it is not part of the BF16 memory stream.

This module does not yet contain pending software descriptor registers,
instruction decode, scalar writeback/get-CSR, DTCM bank adaptation, or
arbitration against tensor traffic.
