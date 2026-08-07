# edge_load_request_fifo.v

## Purpose

`edge_load_request_fifo` is the decoupling boundary between LSU dependency
scheduling and the D-cache lookup pipeline. It accepts the ordered head on port
0 and its adjacent paired request on port 1. When both fire, lane0 is stored
first.

The production configuration has two entries and two backend dequeue ports. Lane1
may pop only when lane0 also handshakes, matching the existing D-cache paired
request contract. Every
entry carries `seq_id`, `epoch`, address, size, and signedness. Same-cycle
dequeue space is visible to both allocation ports.

Two entries cover one complete dual-lane allocation and are the measured peak
occupancy across the maintained workload suite. CoreMark and the control-flow
benchmarks normally use the empty-FIFO fall-through path. A deeper request
buffer is deliberately avoided because load ownership already lives in the
parameterized scalar load queue, whose production depth is two entries.

When the FIFO is empty, `edge_lsu_top` bypasses it combinationally so the
maintained oldest request keeps its original zero-added-cycle path. Requests
accepted into the FIFO are only `queued`; the load queue marks them
`backend_issued` later, when an output lane actually handshakes with D-cache.

`flush_seq_id == 0` clears the entire FIFO. Otherwise redirect handling compacts
the FIFO in age order, preserving entries through the redirect boundary and
dropping only younger entries in the matching epoch. This is required because
the load queue separately tracks the same preserved prefix. This prevents a
redirect from leaving a queued load without a corresponding FIFO request.
