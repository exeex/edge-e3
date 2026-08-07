# edge_actu_unit

`edge_actu_unit` is the legacy ACTU-only command facade around the production
`edge_accel_unit`. It ties off CMPU commands and preserves the existing ACTU
module-test and integration interface. It owns no descriptor storage, DTCM
streamer, compute lane, or output FIFO itself.

Descriptor commands update pending mode, input pointer, output pointer, element
count, and scalar registers. `cmd_start_req` launches owner 0 (ACTU) through
the shared three-source IO engine. The shared unit snapshots the descriptor and
ACTU scalar at the accepted start, so later setup commands may prepare the next
job while the current job is active.

The memory stream is BF16 throughout. The ACTU-local wrapper places raw BF16
bits into the internal ACTU container and extracts BF16 results; there is no
FP32 memory mode or numerical BF16/FP32 conversion stage.

`cmd_ready` remains permanently asserted for descriptor writes,
`start_ready` is the shared unit's idle/start handshake, and `sync_stall` is
exactly `busy`. The reserved dtype field and legacy output-FIFO parameters are
accepted only for interface compatibility.

Modes 5 and 7 retain the existing short-row softmax behavior: mode 5 clears and
accumulates the ACTU-local sum, and mode 7 consumes the retained sum through the
shared reciprocal path.

Focused coverage:

- `hw_edge_actu_unit_verilator` proves the legacy command contract on the
  shared IO implementation, including mode 5/7.
- `hw_edge_accel_pipe_actu_unit_verilator` proves command decode through DTCM
  output packing with the production compatibility frontend.
