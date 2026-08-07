# edge_ifu_icache.v

## Purpose

Instruction fetch and I-cache wrapper for the dual-stream target. This block
now provides the first maintained Edge I-cache boundary between
`edge_ifu_fetch` and the external instruction-memory request/response channel.
It keeps the 128-bit fetch-packet interface defined by:

```text
edge_ifu_fetch/edge_ifu_fetch.v.md
```

The SoC bring-up cache capacity contract starts at 16KB I-cache and 16KB
D-cache. Edge I-cache line size is 128 bits / 16 bytes because the maintained
frontend packet and external instruction-memory beat are both 128 bits. The
matching D-cache capacity contract is implemented first in:

```text
edge_dcache/edge_dcache.v.md
```

## Reference RTL

Existing sources to study before implementation:

```text
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_top.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_icache.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_icache_data_array.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_icache_tag_array.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_ibuf.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_ipack.v
EDGE_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_pre_decd.v
```

## Interface To Predecoder

The wrapper exposes one naturally aligned 128-bit fetch packet:

```text
fetch_valid
fetch_ready
fetch_block_pc
fetch_bits[127:0]
fetch_start_word[1:0]
fetch_epoch
fetch_predict_info
```

Edge does not implement RVC in this frontend slice. Legal instruction starts
are 32-bit aligned, and instruction lengths are 32 or 64 bits. Therefore
`fetch_start_word` only takes word offsets 0, 1, 2, or 3 inside the 128-bit
packet. The wrapper does not shift instruction bytes; the downstream width
adapter drops the stale prefix and records a one-bit first-word marker per
64-bit chunk.

## Branch/Flush Inputs

```text
redirect_valid
redirect_pc
redirect_epoch
redirect_kill_valid
redirect_kill_seq_id
redirect_kill_epoch
```

Branches remain scalar-control decisions. The fetch wrapper consumes redirect
requests from the scalar/control side, fetches the aligned block containing the
redirect PC, and tags new fetch packets with the active epoch.

The PC redirect policy is documented in:

```text
edge_pc_redirect_ctrl/edge_pc_redirect_ctrl.v.md
```

The implemented first slice does not consume `redirect_kill_*` directly.
Redirect/stale-response suppression remains owned by `edge_ifu_fetch`, which
marks old outstanding responses stale and only emits packets tagged with the
current redirect epoch. `edge_ifu_icache` is intentionally below that policy
boundary: it caches aligned instruction blocks and may still return an old
memory response, but `edge_ifu_fetch` decides whether that response belongs to
the active fetch path.

## Invalidate Interface

The first maintenance boundary is an all-line valid clear:

```text
invalidate_valid
invalidate_ready
debug_invalidate_busy
```

Reset clears the valid sidecar vector in hardware. The tag SRAM contents are not
architecturally meaningful after reset, but every entry is invalid, so boot
fetch can begin immediately without waiting for a full-cache sweep and without
relying on simulator-only memory initialization.

Explicit invalidate uses a one-index-per-cycle sweep and blocks all fetches
until it finishes. `invalidate_ready` is asserted only when there is no active
sweep, no outstanding miss, and no pending response. The first slice therefore
treats invalidate as an idle/cache-maintenance operation, not as an asynchronous
kill of an in-flight refill. Redirect stale-response handling remains in
`edge_ifu_fetch`.

## Design Rules

- Keep I-cache bandwidth independent from scalar/vector/tensor issue bandwidth.
- Do not let the I-cache decode full Edge Vector or Edge Tensor opcode
  semantics.
- The I-cache/IFU side does not handle C906-style RVC halfword packing.
  `edge_predecoder` owns the final 32-bit/64-bit stream split and token
  generation.
- The first slice does not provide an architectural fetch trap path. Unsupported
  fetch-side states should fail simulation through the RTL/testbench.

## First Implementation Simplification

Implemented first target:

- direct-mapped I-cache
- 16KB default capacity, with 32KB accepted by the same interface contract
- one 16-byte / 128-bit fetch packet per cache line
- one outstanding miss at a time
- miss refill through the existing 128-bit external instruction-memory channel
- registered hit response to `edge_ifu_fetch`
- hardware valid-bit clearing after reset and on explicit all-line invalidate
- SRAM-style leaf array split:
  - `edge_ifu_icache_data_array.v`
  - `edge_ifu_icache_tag_array.v`
- no MMU, fetch exceptions, CP0 I-cache maintenance, prefetch, BTB, BHT, or RAS

This is deliberately different from the C906 reference where appropriate. C906
has to tolerate RVC 16-bit instruction starts and therefore keeps more IFU/IPACK
granularity. Edge keeps 32-bit alignment and a 128-bit fetch line because the
maximum same-cycle frontend demand is one 128-bit packet, for example
`scalar32 + scalar32 + vector64`. MMU/protection, predictor coupling, and
fine-grained I-cache read/maintenance operations are future increments behind
this same wrapper boundary.

The controller must not own large tag/data memories directly. C906 keeps
I-cache data and tag storage behind dedicated SRAM macro wrappers
(`aq_ifu_icache_data_array`, `aq_ifu_icache_tag_array`); Edge follows the same
separation with maintained leaf array modules. The current leaf modules infer
behavioral memory for Icarus/Yosys, and are the replacement points for later
FPGA/ASIC SRAM macros.

## Focused Test

```text
src/test-e3/edge_ifu_icache/edge_ifu_icache_basic_tb.v
```

The module-local test proves:

- initial miss sends a 16-byte-aligned external memory request
- refill data is returned and installed
- repeated fetches hit without external memory traffic
- same-index different-tag fetch replaces the old line
- explicit invalidate clears hits and forces a refetch
- response valid holds while the fetch side stalls
