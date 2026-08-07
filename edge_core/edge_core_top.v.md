# edge_core_top.v

`edge_core_top`, `edge_core_base`, and the host-facing `edge_core_debug`
propagate the default-off `ENABLE_EARLY_LOAD_RETIRE` experiment parameter.
When enabled, successful integer load-queue allocation completes ordered
retire before data response; GPR WBT/writeback remains response-owned. FP loads
are unchanged.

The core also enables committed store drain. Always-visible retire0/retire1
metadata from `edge_retire_sync` feeds the scalar LSU; scalar retire tags commit
only the next one or two uncommitted STB entries, and the D-cache/DTCM store
request stays invalid before that point.

The scalar RV64M completion has a dedicated connection to retire-sync input 6,
so a coincident fast-ALU completion is not lost before age-ordered retirement.

The production frontend now instantiates `edge_ifu_predecode_frontend` after
the 64-bit fetch FIFO. Token assembly and predecode share one maintained owner;
the standalone tokenizer and its compile-time legacy path have been removed.

## Purpose

`edge_core_top` is the maintained production Edge core composition boundary. It
is the Edge NPU core: everything inside the external bus boundary belongs here,
including scalar/vector/tensor execution, local memories, DMA, and BIU.
`edge_soc_top` is only the placeholder shell outside the core boundary.

The historical wrapper is split out as `edge_core_debug`. Despite the name, it
is now the host-control wrapper used by both debug and production-like Verilator
builds: without `EDGE_DEBUG` it exposes production control/status pins such as
`core_start`, `core_force_stop`, `core_running`, `core_halted`,
`core_done_irq`, and `core_done_code`; with `EDGE_DEBUG` it additionally exposes
retire trace, fatal report, scoreboard bitmap, cache, token, and BIU debug
signals. FPGA/Yosys/PnR production flows include `edge_core_debug.v` but should
not define `EDGE_DEBUG`.
The `edge_core_base` retire/fatal/debug output ports are present only when
`EDGE_DEBUG` is defined. EBREAK and CSR-break completion status stay available
in production because the host-control wrapper converts those events into the
external done/interrupt contract.

This block exists so `edge_scalar_pipe` remains a scalar execute pipeline, not a
container for the whole core.

## First-Slice Composition

The first implemented core path is scalar bring-up:

```text
edge_ifu_fetch
  -> edge_ifu_icache
  -> edge_fetch_packet_fifo
  -> edge_ifu_predecode_frontend
     -> edge_predecoder
     -> edge_scalar_idu_shim for lane0 scalar decode
        plus predecoder-selected lane1 memory-pair decode for adjacent
        load+load/store+store
     -> edge_accel_cmd_queue tensor-command subset
        -> scalar GPR fallback operand reads
        -> edge_accel_pipe accel-lane command/completion shell
  -> edge_scalar_pipe
  -> edge_lsu_mem_selector
     -> edge_dtcm_subsys scalar LSU port
     -> edge_dcache

edge_scalar_pipe retire allocate/complete
  -> edge_retire_sync

edge_scalar_pipe control placeholder
  -> edge_pc_redirect_ctrl
  -> immediate edge_ifu_fetch / fetch packet FIFO / fused frontend kill
  -> one-cycle-delayed scalar pipe / retire kill

edge_dtcm_subsys
  -> edge_biu_top DMA master

edge_dtcm_subsys DMA / internal cache refill
  -> edge_biu_top
  -> biu_pad_* / pad_biu_*
```

## External Interfaces

- Instruction fetch goes through `edge_ifu_fetch` into `edge_ifu_icache`. I-cache
  misses now refill through the core BIU read path instead of the legacy
  `imem_req_*`/`imem_resp_*` sideband. The first I-cache slice is a direct-mapped
  16-byte / 128-bit packet cache. Accepted fetch packets pass through
  `edge_fetch_packet_fifo`, which splits them into 64-bit chunks before
  tokenization, so I-cache/fetch latency and
  tokenizer backpressure are separated from the predecoder's token-shape
  sampling window.
- The lean `edge_core_top` has no `imem_*`, `bringup_*`, retire/status, or
  `debug_*` top-level ports. The `edge_core_debug` wrapper is the current
  host-facing top for production-like Verilator builds: production elaboration
  keeps control/status and bus-facing pins, while `EDGE_DEBUG` adds the
  heavyweight trace/debug pins used by hardware tests.
- Scalar LSU backend traffic from `edge_scalar_pipe` is selected by
  `edge_lsu_mem_selector` using the configured DTCM window. DTCM hits use the
  `edge_dtcm_subsys` scalar LSU port; non-DTCM accesses continue through
  `edge_dcache`.
- 64-bit Tensor/DMA stream commands are routed through `edge_accel_cmd_queue`
  and `edge_accel_pipe`. `dma.start` from this stream now drives the same
  core-owned DTCM DMA start pins used by the legacy scalar placeholder path;
  `dma.sync` completes when the DTCM DMA engine has no start request, busy
  state, or active transfer latch.
- Tensor/ACTU pointer commands receive the same configured DTCM base, mask, and
  enable values as scalar LSU and DMA. The pipe subtracts the configured base
  before emitting its 128-bit-word offset. Circular DMA ring setup likewise
  derives its starting word offset from `dma.start.dst - edge_dtcm_base`; no
  low physical DTCM address is hard-coded in the core.
- `dma.setsrc/settar/setn/setx/sety/setentry` program the stream DMA descriptor.
  `dma.start` captures only low-parcel `rd`; source and target come from the
  preceding setup commands. Its
  immediate can enable nested `y_max`/`x_max` loops. Each transfer copies `n`
  bytes from `base + y*y_stride + x*x_stride`; `setx` and `sety` each pack a
  32-bit max and 32-bit stride. A second immediate bit routes the same traversal
  through the existing circular producer/WLD path.
- Circular XY DMA accumulates `setn`-byte fragments in the current ring entry
  and publishes one synchronization token only when `setentry` bytes complete.
  Capacity and producer/consumer accounting are in entries; DMA assigns no
  dtype or tile meaning to an entry. Legacy non-XY circular WLD derives the
  fragment and entry size from tensor wtype.
  `tensor.wsld_circular` requires 272B entries containing one 16B scale vector
  followed by four 64B weight tiles; it releases an entry only after all four
  matching tensor starts have actually launched. It fresh-loads the scale for
  tile 0 and emits explicit SLD reuse tokens for tiles 1 through 3, preserving
  the one-scale-token-per-start contract.
- Circular XY A2D issues consecutive 16-byte fragments as multiple outstanding
  single-beat AXI reads. Ordered response descriptors and a shallow SRAM-backed
  128-bit FIFO absorb DTCM scheduling stalls. A ring slot is reserved when its
  first fragment is issued, but becomes visible to WLD only after every byte of
  the entry has actually been written into DTCM.
- The Tensor/DMA stream is treated as a conservative serializing side stream in
  this slice. `edge_core_top` only accepts a new tensor command when the tensor
  queue and DMA engine are idle, only asserts the tensor-pipe command valid
  when the queue is actually allowed to pop, and stalls younger scalar issue
  while tensor/DMA work is pending. This prevents `dma.sync` from being bypassed
  by later scalar loads.
- Scalar cache-maintenance sideband commands from `edge_scalar_pipe` are routed
  into `edge_dcache`. The current D-cache boundary handles VA invalidate by
  clearing D-cache metadata and emits a four-beat VA clean writeback stream on
  dirty hits. `edge_core_top` adapts each D-cache clean beat into a single-beat
  BIU core write and returns completion to D-cache after the final write
  response. D-cache then reports `cache_op_complete_*` back to
  `edge_scalar_pipe`, so scalar cache-maintenance retire completion waits for
  the real clean writeback response. `edge_core_top` also holds Tensor/DMA issue
  behind an outstanding scalar cache operation so `dma.start` cannot read DRAM
  before a preceding clean has written back dirty cache data.
- I-cache miss refill, D-cache miss refill, and bring-up core reads share the
  core BIU read channel. I-cache requests first enter a one-entry refill buffer
  inside `edge_core_top`; this makes the I-cache miss accept point independent
  from same-cycle AXI `arready` and prevents a refill AR from being issued
  without the cache entering `miss_pending`. The arbiter locks ownership until
  `rlast`. I-cache refills are one 128-bit beat; D-cache refills remain four
  128-bit beats for a 64-byte line. When I-cache and D-cache are both pending,
  saturated starvation counters bias the next grant toward I-cache more quickly
  than D-cache so the frontend cannot be held off indefinitely by data refill
  traffic. The IFU/I-cache path also drains stale or backpressured frontend read
  responses with small skid buffers so a long-latency Tensor/DMA stream command
  cannot leave the BIU read owner stuck behind unused frontend prefetch data.
- D-cache refill beats also carry the BIU `rresp` error summary. The D-cache
  drains the burst without installing a failed line, then returns the error
  with the owning load's sequence/epoch through the memory selector and LSU.
- Retire output is exposed as two in-order retire lanes from `edge_retire_sync`
  only under `EDGE_DEBUG`.
- Ordinary Tensor/DMA commands do not allocate `edge_retire_sync` entries.
  Their command acceptance and completion stay inside the accel lane. Only
  `tensor.sync` and `dma.sync` fork a scalar join pseudo; that pseudo allocates
  the scalar RTU and completes from the matching accel sync-done event.
- Fatal scalar placeholder reports are debug-only. The registered scalar
  `EBREAK` completion event and provisional CSR-break completion event are
  production status paths because the host-control wrapper turns them into
  `core_done_irq` and `core_done_code`.
- DTCM/DMA configuration and the external AXI pad boundary are owned by this
  core top. `edge_soc_top` only forwards those pins.

## Token Policy

Scalar 32-bit tokens now pass through `edge_predecoder` before scalar issue.
Tensor/DMA/ACTU 64-bit stream tokens are consumed by the predecoder, compacted
to `opcode8 + imm8`, and routed through the command queue into
`edge_accel_pipe`. The production queue-to-pipe path carries no reconstructed
64-bit instruction. Capture-free
commands such as `tensor.start`, `actu.start`, `actu.sync`, and immediate ACTU
setup forms stay on that accel path; setup commands with GPR operands,
including `setcsr`, get their values from scalar holder snapshots.

The current production tensor/DMA/ACTU path is snapshot-only. It instantiates an
eight-entry command queue and an eight-entry GPR snapshot store, addressed by the
3-bit `seq_id[2:0]` target carried by the scalar holder pseudo. Commands consume
only scalar holder snapshots; there is no producer-history fallback. Each
production command consumes at most one GPR value. DMA source/target and shape
state are programmed by separate setters, while mode/wtype control lives in
`imm8`.

Accelerator results use a separate depth-2 reverse snapshot. The predecoder
allocates and binds an ID to both halves of `accel.getcsr`; `edge_accel_pipe`
writes CMPU max/argmax/min/argmin or ACTU exp-sum bits after the owner is idle;
the scalar pipe consumes the value and completes the destination GPR/retire
entry. Full allocation backpressures predecode, and redirects kill younger
owned and scalar-pending entries by sequence and epoch.

The typed-token frontend preserves head-of-line issue between scalar and
vector/tensor tokens. Mixed scalar+tensor or tensor+scalar fetch adjacency is
accepted over successive cycles, except that tensor snapshot pseudo instructions
still travel with the tensor head when the tensor instruction itself is oldest.
Tensor and DMA starts leave the frontend when the accel command path accepts
them and then execute in the background; they do not enter the scalar RTU.
An accepted `tensor.sync` or `dma.sync` blocks younger scalar issue until its
accel half completes and releases the matching scalar join pseudo. Other
pending tensor commands do not by themselves block scalar issue.

The SoC/core path now consumes two adjacent scalar tokens in one cycle for the
currently validated same-class memory lane1 classes: `load+load` and
`store+store`. Lane0 still goes through `edge_scalar_idu_shim`; lane1 is
decoded locally from tokenizer token1 and is presented directly to
`edge_scalar_pipe.issue1_*`.
Mixed `load+store` / `store+load`, ALU lane1, branch/control lane1,
system/fence lane1, and FP lane1 remain disabled. `load+load` and
`store+store` now reach the D-cache lane1 request boundary. This is still a
conservative throughput slice: DTCM remains lane0-only, while D-cache lane1 is
accepted only for same-line hit pairs that map to different available 64-bit
banks in the current phase. Misses, different-line pairs, dirty/refill/cache-op
states, and same-bank conflicts replay through the ordered lane0 path.

This is intentional: vector/tensor issue ownership belongs in `edge_core_top`,
not inside `edge_scalar_pipe`.

## Deliberate Limits

- `edge_accel_cmd_queue` and `edge_accel_pipe` form the maintained accelerator
  path for Tensor, ACTU, and accelerator-owned DMA commands. Non-Tensor vector
  execution remains outside this core slice.
- `edge_accel_pipe` is connected to `edge_tensor_unit` inside
  `edge_core_top`. Tensor IO lanes, Tensor WLD, and Tensor/DMA stream commands
  now reach the core-owned DTCM subsystem in the SoC path. Non-Tensor vector
  execution remains outside this core slice.
- The accelerator command queue presents `valid` independently of accelerator-pipe
  `ready`. Backpressure is consumed only by the queue's issue handshake; this
  keeps circular WLD ring-empty waits out of combinational ready/valid loops.
  Normal and transposed circular WLD commands share the same ring consumer;
  the transposed form drives only the Tensor unit's transpose WLD request so
  the 8x8 transpose is performed while the gathered tile is loaded.
- Autonomous WSLD is armed once and blocks standalone WLD/SLD issue until it
  drains. It waits for a produced DMA group, completes SLD before W0, permits
  only one weight tile of lookahead, emits three ordered SLD reuse tokens for
  the remaining starts in each group, and holds `tensor.sync` while active.
  Software chooses the circular capacity; directed coverage uses depth four,
  while normal kernels may reserve four to eight 272B groups.
- Tensor command queue redirect cleanup uses the registered backend redirect,
  matching the other backend queues and keeping scalar redirect resolution out
  of the Tensor issue combinational path.
- `edge_retire_sync` is scalar-owned. Tensor/DMA completion cannot mask a
  coincident scalar lane1 completion; the only cross-lane completion entering
  it is the explicit sync join acknowledgement through the scalar placeholder
  completion port.
- The production core no longer instantiates the legacy lite-rename bridge. The
  predecoder owns local capture-id bookkeeping and emits producer tags with
  vector/tensor command metadata. `edge_accel_cmd_queue` waits for scalar
  producer/WBT sideband payloads and does not read fallback values from the live
  scalar GPR file for Tensor/DMA setup operands.
- DTCM/DMA/BIU are present. Scalar LSU DTCM hits are connected through
  `edge_lsu_mem_selector`, which preserves the current conservative
  backend request policy. The scalar pipe may issue adjacent same-class memory
  load/store pairs into the LSU load queue or STB, while the DTCM side still
  accepts one formatted memory request at a time and the D-cache side accepts
  lane1 only under the conservative hit/bank rules above. The DTCM subsystem receives 64-bit word
  addresses; scalar byte offsets stay in the selector for load-data formatting
  and store-lane generation. 64-bit stream `dma.start` now drives the
  core-owned DTCM DMA start pins through `edge_accel_pipe`; the provisional
  scalar `dma.start` placeholder is still accepted as a compatibility path
  until the software helper is fully switched to the 64-bit encoding. Both
  stream `dma.sync` and scalar placeholder `dma.sync` wait for DMA idle,
  including the active-transfer latch used to arbitrate DTCM/BIU DMA beats.
- The instruction memory path now has a maintained I-cache wrapper and BIU
  demand-refill path, but it is still narrower than C906: no MMU, CP0 I-cache read,
  prefetch, predictor coupling, or RVC halfword packing. I-cache line size is
  intentionally 128 bits because Edge instruction starts are 32-bit aligned and
  the external fetch beat is 128 bits.
- `edge_dcache` is still the first scalar memory backend adapter.
- Cache-maintenance commands are connected to `edge_dcache`. VA invalidate can
  clear tag/dirty metadata, and VA clean can emit 64B line writeback beats.
  Scalar cache-maintenance retirement waits for the D-cache completion pulse.
- `csrw 0x7e0, rs1` is exposed as the provisional Edge CSR break event. The
  core reports the source register value through `scalar_csr_break_code` so
 - `csrw 0x7e1, rs1` emits `rs1[7:0]` through the non-terminating
  `scalar_csr_putchar_*` simulation-console event. It retires normally and is
  intended for debug output after measured cycle windows.
  software startup code can return `main()` directly without an `x31` marker.
- `csrw 0x7d8/0x7d9/0x7da, rs1` programs DTCM base, mask, and enable bit 0.
  Reset inherits the SoC integration defaults; shared crt0 rewrites the window
  from linker symbols before application code runs.
- Retire PC is not stored by `edge_retire_sync`; the SoC shell should keep PC
  reporting placeholder until retire entries carry PC.
- No branch prediction is connected; only resolved scalar control redirects are
  used.
- Resolved branch/JAL/JALR results reach frontend redirect in their accepted
  issue cycle. Scalar-pipe and retire cleanup use the same sequence/epoch kill
  metadata one cycle later, allowing the redirecting instruction itself to
  allocate and complete backend state while younger frontend work is flushed
  immediately.
- Redirect cleanup of the tensor-sync issue fence uses modulo sequence age, so
  a younger sync command remains killable across sequence-number wrap.

## Focused Test

`test/edge_core_top_scalar_smoke_tb.v` proves reset fetch through the real core
BIU AXI refill path, scalar instruction tokenization, scalar issue, ALU
completion, scalar DTCM store/load selection, and in-order retire through the
new core boundary. It also rejects any DTCM store request that appears before
the matching store's ordered-retire event.

`test/edge_core_top_tensor_smoke_tb.v` proves reset fetch through the same core
BIU/I-cache path, 64-bit Tensor tokenization, predecoder Tensor command issue
through `edge_accel_cmd_queue`, `edge_accel_pipe` command acceptance, and
in-order Tensor-token retire.

`src/test-e3/edge_accel_pipe/edge_accel_queue_bridge_tb.v` proves the legacy
two-capture `dma.start` bridge through lite rename, vector-command queue, and
`edge_accel_pipe` DTCM DMA sideband generation at module-integration level.
The production `edge_core_top` path bypasses that capture buffer and uses the
queue's scalar-GPR fallback path instead.

`src/test-e3/edge_lsu_mem_selector/edge_lsu_mem_selector_tb.v` proves the extracted
selector boundary for DTCM store/load routing, D-cache fallback, DTCM pending
backpressure, and scalar load response muxing.

`tests/software/cases/EDGE_LSU_MIXED/EDGE_LSU_MIXED.cpp` covers the same
selector through the SoC software runner with interleaved D-cache/DRAM and DTCM
scalar stores/loads.
