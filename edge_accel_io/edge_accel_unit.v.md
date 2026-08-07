# edge_accel_unit

`edge_accel_unit` owns the pending ACTU and CMPU descriptors above the shared
`edge_accel_io_unit`. It is the production command-to-stream boundary; only one
owner may launch at a time.

ACTU keeps its existing mode/input/output/count/scalar descriptor. CMPU owns
mode, lhs, rhs, mask, output, and count. An accepted start selects immutable
source/destination metadata as follows:

```text
ACTU:          lhs/src0 BF16 -> BF16 destination
CMPU reduce:   lhs/src0 BF16 -> no destination
CMPU min/max:  lhs/src0 + rhs/src1 BF16 -> BF16 destination
CMPU select:   lhs/src0 + rhs/src1 BF16 + mask/src2 byte -> BF16 destination
CMPU compare:  lhs/src0 + rhs/src1 BF16 -> byte destination
```

Descriptor writes are always accepted and may prepare the next job while the
shared unit is busy. Starts are serialized by the shared `start_ready`; if both
start requests are asserted illegally in one cycle, CMPU has priority and ACTU
does not report ready. Both sync-stall outputs reflect shared busy because an
operation from either owner occupies the same physical IO engine.

The unit tracks the accepted owner to demultiplex done. CMPU reduction results
are copied atomically into the four completed-result outputs and accompanied by
`cmpu_result_update`. They are stable until a later reduction completes. The
future reverse-snapshot/get-CSR path consumes this completed bank, never the
running accumulator.

There is no FP32 stream mode. ACTU and CMPU memory data remain raw BF16, with a
byte stream used only for SELECT masks and compare outputs.
