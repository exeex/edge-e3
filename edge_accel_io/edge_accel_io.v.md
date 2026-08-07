# edge_accel_io

`edge_accel_io` is the shared ACTU/CMPU DTCM streaming engine.  One owner is
snapshotted per job, so the two compute units never use its storage or DTCM
port concurrently.

## Normalized Descriptor

Each of three sources independently carries enable, 8/16-bit element width,
and a base address.  The destination independently carries enable, width, and
base address.  Owner and four-bit mode are opaque metadata forwarded to the
compute mux.  All streams share one 16-bit element count.

Expected mappings are ACTU=`src0 BF16 -> dst BF16`; CMPU reduction=`src0 BF16,
no dst`; CMPU MIN/MAX/compare=`src0/src1 BF16`; and CMPU SELECT=`src0/src1
BF16 + src2 byte`.  Compare destinations are byte-wide.

## FIFOs And Read Scheduling

Three physical 16-bit element FIFOs are shared by both owners.  Byte source
elements are zero-extended.  A tagged round-robin scheduler keeps at most one
128-bit read outstanding and pushes eight BF16 or sixteen byte elements into
the selected FIFO.  Enabled FIFOs pop in lockstep only when every required
source is nonempty and the selected compute core accepts the packet.

The default depth is 32 entries, allowing two byte beats or four BF16 beats to
be buffered.  Reads overlap element dispatch; there is no stop-and-refill chunk
boundary.

## Output And Completion

A shared output FIFO absorbs fixed-latency core results independently of DTCM
write stalls.  A pack register forms eight-BF16 or sixteen-byte writes and a
pending register holds a full/tail beat under DTCM backpressure.  A vector job completes
after all outputs are accepted and committed.  A destination-disabled
reduction completes on `core_result_valid/core_result_ready`.  Zero-length jobs
complete immediately without starting a core or touching DTCM.

Before dispatch, the IO reserves one output slot for every accepted input whose
fixed-latency result has not arrived. Dispatch stops when the output FIFO count
plus those in-flight results reaches FIFO depth. ACTU and CMPU therefore never
receive output backpressure after accepting an input; each result has guaranteed
storage and core latency remains fixed.

This standalone slice does not contain ACTU/CMPU arithmetic, descriptor CSRs,
the owner mux, or the DTCM bank adapter.
