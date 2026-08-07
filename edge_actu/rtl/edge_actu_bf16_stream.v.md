# edge_actu_bf16_stream

This ACTU-local wrapper is the only compatibility boundary between the shared
accelerator's raw-BF16 element stream and the existing internal ACTU core
port. Input BF16 bits are placed in the internal container and final BF16 bits
are extracted with wiring only; there is no numeric conversion, FP32 stream
mode, additional rounding, storage, or latency.

The 32-bit scalar and softmax-sum ports are ACTU-local control/accumulator
state used by SOFTMAX_EXP and SOFTMAX_NORMALIZE. They do not describe DTCM
element format. All shared input and output elements remain raw BF16.

The wrapper inherits the configured ACTU fixed latency and one-element-per-
cycle acceptance contract. Its focused test checks exact BF16 values, latency,
and consecutive output without bubbles.
