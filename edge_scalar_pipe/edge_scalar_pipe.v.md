# edge_scalar_pipe.v

`ENABLE_EARLY_LOAD_RETIRE` is a default-off experiment. When enabled, a
successful integer load-queue allocation completes the load's ordered-retire
token, while the load response remains responsible for GPR writeback, producer
publication, and WBT release. FP loads remain response-coupled.

`ENABLE_COMMITTED_STORE_DRAIN` gates backend store visibility on the
`ordered_retire0/1_*` feedback inputs. The maintained core enables it; direct
scalar-pipe unit tests default it off. Store execute completion still marks the
retire token done, but only ordered retirement commits the matching STB prefix.

## Fast ALU dual issue

The lanes may issue one ordinary non-control fast ALU instruction and one
RV64M instruction in either age order after WBT dependency/WAW checks. Fast and
M writeback and completion are independent; retire-sync restores age order.
The two request-ready paths are also class-aware: an occupied RV64M unit blocks
only an M candidate, while independent Fast candidates may continue through
either Fast datapath. Fast control/no-writeback retirement is tagged from the
lane0 Fast completion channel so a coincident M completion cannot replace its
sequence or epoch.
The pipe selects readiness from its decoded lane classes and the ALU wrapper's
raw `mul_issue_ready_o` / `div_issue_ready_o` capacities; it does not feed a
fire-qualified ALU port-select mux back into the issue-ready equation.
Tensor/DMA snapshot issue is unchanged and cannot enter this pair path.
Two ordinary non-control Fast ALU instructions may also issue together. The
second instruction uses a distinct Fast ALU datapath and completion channel;
lane0-to-lane1 RAW uses the existing qualified combinational Fast result
forward, while WAW remains blocked by the dual-port GPR WBT.
Simulation may pass `+disable_scalar_fast_fast_pair` to suppress only the
Fast+Fast policy while retaining the second datapath and all other lane1 pair
classes. This provides a same-binary CoreMark A/B measurement.
Because lane1 Fast completion and lane1 no-writeback store/pseudo completion
share retire completion port 4 in this slice, a lane1 store/pseudo candidate
waits one cycle when a prior lane1 Fast result completes. Lane0 may still issue;
the predecoder retains lane1 for replay rather than losing either completion.

## Purpose

Canonical lane0 scalar pipeline for 32-bit RV64IM/Zba/floating-point
instructions plus dual-stream pseudo instructions, with a first memory-only
lane1 issue shell. This block owns scalar architectural state and scalar memory
access.

Implemented file:

```text
edge_scalar_pipe/edge_scalar_pipe.v
```

The current RTL is the first proof slice. It contains real GPR/FPR register
arrays, real GPR/FPR `edge_wbt` instances, `edge_scalar_alu`, `edge_lsu_top`,
`edge_scalar_csr_sys`, and the `edge_fpu_fmac`, `edge_fpu_misc`, and
`edge_fpu_cvt` issue/complete boundaries. The FPR
path now has real arithmetic, misc, move, and conversion producers plus a
placeholder FPR completion input that remains for future FP-load integration.
The scalar ALU boundary has two registered fast-complete paths for ordinary
integer, control, and Zba operations, plus an independent registered multi-cycle
RV64M path. Ready is selected by the candidate's class: RV64M busy does not
backpressure Fast ALU/control issue, and the three completion channels may be
valid together.
It recognizes placeholder RV64I load/store memory instructions to prove scalar
memory decode and pipeline flow before D-cache/scalar DTCM integration. Lane0
keeps the full scalar instruction contract. Lane1 is opportunistic and accepts
memory operations or non-control fast integer ALU operations when paired with
the opposite lane0 unit, in addition to `load+load` and `store+store`.
Mixed `load+store` / `store+load`, control/system/fence lane1, and FP lane1
remain non-goals for this slice. System, fence, and
selected Edge custom control instructions are exposed as explicit placeholder
packets so the future system, DMA, cache-maintenance, ordering, and fatal-error
boundaries have fixed wiring.
Architectural FCSR/`frm`/sticky `fflags` and partial same-epoch FPU redirect
preservation are intentional non-goals. FP instructions use only immediate
static `rm=000..100`, and frontend recovery uses a new epoch with full old-epoch
FPU cancellation.

Ready/backpressure is computed from the current instruction candidate plus a
top-level retire allocation capacity input, not from accepted-pulse metadata
produced by `edge_scalar_idu_shim`. This avoids a combinational loop:

```text
shim scalar_ready -> shim issue_valid/scalar_def_valid -> pipe issue_ready
```

The pipe therefore decodes enough of `issue_inst` locally to decide whether the
candidate touches GPR or FPR WBT. The accepted shim metadata is still used for
the actual producer tag, destination domain, and completion bookkeeping.
`retire_alloc_ready` must be provided by the owner from registered or otherwise
loop-free retire capacity. Do not wire it directly from a retire queue
`alloc_ready` signal that itself depends on the pipe's same-cycle
`retire_alloc_valid`.
Tensor GPR holder pseudo instructions are the exception: they only write a
snapshot into the tensor command queue and do not allocate a retire entry, so
they may issue even when `retire_alloc_ready` is low. This lets a waiting tensor
command receive its snapshot and complete, which can in turn free retire queue
space.

`PSEUDO_ACCEL_GETCSR` issues without waiting for the accelerator result. It
allocates normal GPR WBT and retire state, then records snapshot ID,
destination, sequence, epoch, and bank in a two-slot pending table indexed by
snapshot ID. The background completion path consumes a ready reverse snapshot
and feeds the existing held CSR/GPR completion slot. Retirement therefore
waits for the value without creating a predecoder/accelerator ready loop.
Redirect kills remove younger pending metadata.

`PSEUDO_TENSOR_JOIN` is the explicit synchronization exception in the other
direction. It has no GPR operands, allocates a scalar retire entry, and does not
assert an immediate no-writeback completion. The matching Tensor/DMA sync-done
event arrives through `gpr_placeholder_complete_*` and marks that entry done.

The production tensor/DMA holder path is not a lite-rename producer fill. Each
holder reads one selected architectural GPR in scalar issue order and writes
one of eight snapshot slots through a 3-bit target. Tensor/DMA commands consume
only that stored operand.

Redirect kill has priority over accepting a new scalar instruction. When
`redirect_kill_valid` is asserted, `issue_ready` is deasserted so a flushed
predecoder/tokenizer packet cannot be captured by the scalar pipe in the same
clock edge that the frontend applies the redirect.
For the current FPU integration, a full-epoch redirect uses
`redirect_kill_seq_id=0`: FMAC metadata/data valids, the slow slot, and the FPU
completion queue are cleared together; LSU queues, GPR/FPR WBTs, and the
composed retire queue discard the same epoch. The scalar FPU directed test
holds destination sentinels while killing in-flight FMAC, misc, slow, and FP
load work, rejects stale load responses, checks that no killed producer or
retire event escapes, and then reuses the destination in a new epoch. A
partial redirect that preserves older in-flight FPU work is not claimed by
this global-cancel proof slice.

GPR/FPR WBT reserve pulses are driven only from accepted issue pulses:

```text
issue_fire = issue_valid && issue_ready
issue1_fire = issue1_valid && issue1_ready
```

The local candidate decode may look at `issue_inst` while backpressured, but it
must not reserve WBT, enqueue unit work, or otherwise create architecturally
visible state until `issue_fire` is true. This is especially important on branch
redirect cycles, where the killed token can still be visible on the issue bus
while `issue_ready` is held low.
Lane1 memory issue also enters the GPR WBT when it needs source checks. Lane1
loads reserve their destination register, while lane1 stores use the same WBT
path to wait for base/data source operands before their address/data are handed
to the LSU. Besides same-class `load+load` and `store+store`, a ready non-control
integer ALU operation in lane0 may pair with a memory operation in lane1. The
WBT rejects lane1 WAW dependencies on lane0. For a non-RV64M, non-control
integer fast-ALU operation that writes a GPR, the scalar pipe may forward the
combinational lane0 result into lane1 LSU `rs1` address-base and/or store-data
`rs2`. Forwarded sources are removed from the lane1 WBT source check; all other
same-cycle RAW dependencies remain blocked. The reverse `memory+fast ALU`
direction reuses the same physical ALU because lane0 occupies the LSU. Its
lane1 ALU sources and destination pass through the dual-port GPR WBT; therefore
`load->ALU` RAW and same-destination WAW pairs are rejected, while an independent
lane1 ALU result uses the normal ALU completion/writeback path.
The GPR WBT busy bitmap is exposed from the pipe as `gpr_busy_status` because
the core tensor fallback capture path uses it as functional readiness status.
Debug builds may still expose that bitmap through a `debug_gpr_busy` wrapper
pin, but the pipe-level signal is not debug-only.

## Owned State

- GPR register file.
- FPR register file, if present in the selected target.
- GPR/FPR instances of the shared WBT dependency/writeback primitive.
- Issue/complete wiring to `edge_scalar_alu`.
- A concentrated FPU integration island containing independent fixed-latency
  unified FMAC pipeline plus the misc/conversion and completion-queue
  wiring.
- Issue/complete wiring to `edge_lsu_top`, including the first memory-only
  lane1 issue path.
- Issue/complete wiring to `edge_scalar_csr_sys`.
- An eight-entry scalar producer queue that preserves same-cycle ALU/load/FPR producer
  events behind the single external `producer_*` pulse interface.
- A minimal `cycle` CSR counter used by software benchmarks that share the
  C906 `rdcycle`/`csrr cycle` measurement flow.

Atomics are not supported in the first target, so this pipe does not need AMO or
LR/SC reservation state.

The scalar pipe does not execute Edge Vector or Edge Tensor operations and does
not decode the full 64-bit Edge Vector or Edge Tensor opcode.

The first RTL does not yet implement D-cache or scalar DTCM access. Integer
loads reserve GPR WBT, issue `edge_lsu_top` for placeholder address/size
generation, emit a placeholder memory packet, send a backend request through
`lsu_load_req_*`, then accept load data through `lsu_load_resp_*`;
`edge_lsu_top` returns the GPR load completion with retained `rd/bank` metadata.
Integer stores issue `edge_lsu_top`, emit a placeholder memory packet, expose
formatted store drain beats through `lsu_store_req_*`, and complete execution
without writing memory in the scalar pipe itself. In the maintained core the
beat stays suppressed until ordered-retire feedback commits it. Lane1 stores
allocate the LSU/STB lane1 path and emit a retire allocation plus a no-writeback completion;
the lane1 no-writeback completion uses its own retire-complete port so it does
not mask same-cycle GPR/ALU completions. The external placeholder memory packet
remains lane0-only in this compatibility slice.
Until scalar store-to-load forwarding exists, scalar loads are issued
conservatively only when the store buffer is empty. This preserves RV memory
program order when the pipe accepts `store+store` pairs faster than the backend
can drain them. The scalar pipe keeps independent area/performance depth knobs.
The store buffer remains four entries while the production load queue defaults
to two, the minimum depth that accepts one complete adjacent dual-load
allocation. The load queue count width is derived from that configured depth so
full detection cannot wrap and admit more live loads than physical entries.
`EDGE_SCALAR_LOAD_QUEUE_DEPTH` remains available for larger stress/debug
configurations. Top-level `load+load` pairing is enabled as a
load-queue proof point and now reaches the D-cache lane1 request boundary for
same-line hit pairs. It remains intentionally conservative: DTCM is lane0-only,
and D-cache lane1 may replay on misses, different-line pairs, dirty/conflicting states, or
same-64-bit-bank conflicts.
Misaligned scalar load/store attempts are detected in `edge_lsu_top`. Because
the current scalar pipe does not yet have precise architectural exception
retirement, the first slice reports them through `fatal_report_valid` with code
`3` and, under `IVERILOG_SIM`, terminates simulation with
`EDGE_SCALAR_PIPE_FATAL_MISALIGNED`. The LSU suppresses load queue, store
buffer, and backend side effects for the faulting operation.
FP32 FADD.S, FSUB.S, FMUL.S, FMADD.S, FMSUB.S, FNMADD.S, and FNMSUB.S issue to
the integrated `edge_fpu_fmac`, read operands from the scalar FPR file with
same-cycle FPR completion bypass, reserve the destination in the FPR WBT, then
write the FPR file, emit an FPR producer, and retire when FMAC completes. Edge
FPR storage, FPR reads, completion bypass, FMAC operands, and FPR writeback are
physically 32-bit FP32 payloads, not RV NaN-boxed storage. There is no 64-bit
boxing boundary inside the maintained FMAC path.
FLH promotes binary16 exactly to FP32, FLW takes the low 32 bits, and FLD rounds
binary64 to FP32 with round-to-nearest-even. FSH rounds FP32 to binary16 with
round-to-nearest-even, FSW stores the payload, and FSD expands FP32 exactly to
binary64. These operations share the scalar LSU load queue and store buffer;
the load queue retains a one-bit GPR/FPR destination domain. Conversion bit
patterns follow Berkeley SoftFloat Release 3e with the `RISCV` specialization
and round-to-nearest-even. Cross-format NaNs become the RISC-V canonical
default NaN (`f16=0x7e00`, `f32=0x7fc00000`,
`f64=0x7ff8000000000000`); conversion exception flags are not yet routed to
architectural `fflags`. The arithmetic `.S/.D/.H` format field is ignored;
all three encodings produce the same physical FP32 result. FMV ingress/egress remains responsible for
the standard bit-move/sign-extension behavior at the GPR boundary while still
normalizing FPR writes to the Edge FP32 payload contract. FADD, FSUB, FMUL, and
the fused family share one fixed-latency FMAC pipeline. Every arithmetic mode
uses the same stage count and completion latency, while valid and
sequence/epoch/destination metadata advance through the matching four-cycle
pipeline every cycle without a busy bit. Redirect kill clears every metadata
valid stage together with the FMAC datapath.
The scalar single-issue boundary can therefore feed any arithmetic mode on
consecutive cycles without duplicating the FMAC datapath. Misc and conversion
operations retain their separate registered fast boundary.
The related attachment wires are grouped into one integration island so a
future build parameter can remove or replace the complete FPU boundary without
scattering optional-unit wiring through the pipe. Arithmetic blocks still
produce local exception flags for bit-true testing, but architectural
FCSR/`frm`/sticky `fflags` state is intentionally omitted.
The four-entry completion queue absorbs unified FMAC, misc/cvt, FP-load, and
slow FDIV/FSQRT results before the single GPR/FPR writeback boundary. Its four
live ingress lanes determine the worst-case reserved capacity; the unused fifth
queue lane is tied off. This queue is writeback collision buffering, not an
execution busy mechanism. FDIV/FSQRT share a variable-latency single-outstanding slow slot;
only another slow instruction is blocked while it is occupied, so fixed-latency
FP arithmetic can continue to issue and complete.
The external `fpr_placeholder_complete_*` hook remains as a 32-bit test and
integration completion source, but architectural FP loads complete through the
LSU and release the FPR WBT directly.
If an FMAC and FP-load response arrive together, FMAC keeps the current FPR
completion port and a one-entry 32-bit pending register replays the FP-load
completion on the next available cycle. This preserves load/FMAC overlap
without adding a second FPR write port.
The manual `hw_edge_scalar_pipe_fpu_random_diff` target generates dependent
mixed streams containing FMAC-family arithmetic, variable-latency FDIV/FSQRT,
sign injection, min/max, compare/class/move (including FMV.X.H/H.X),
W/WU/L/LU integer conversions, and
FLH/FLW/FLD/FSH/FSW/FSD. A sequential RISCV-specialized SoftFloat oracle
maintains GPR, FPR, and a 256-byte little-endian memory image. The scalar-pipe
checker requires ordered-retire sequence IDs without
gaps or duplicates, epoch 1 on every retirement, empty GPR and FPR WBTs at
drain, empty LSU load/store queues, and bit-exact final register and memory
contents. This deliberately
mixes four-cycle FMAC completion, one-cycle misc/FCVT completion, and the
single-outstanding slow slot across both writeback domains. Batch runs use
`run_fpu_random_diff.py`; failing seeds retain
register/memory inputs, trace, expected state, simulator log, and a replay command outside
default CTest.
GPR source operands bypass same-cycle GPR writeback completion data, including
registered ALU/CSR completions and placeholder load completion data, so the GPR
WBT can release a dependent source on the completion cycle. This is a narrow
writeback-completion bypass, not a complete multi-stage scalar forwarding
network.

## Shared WBT Use

Scalar GPR and FPR dependencies use the same `edge_wbt` primitive as the vector
VR domain. Each architectural register file has its own WBT instance:

```text
GPR WBT for integer/scalar address registers
FPR WBT for scalar floating-point registers
VR WBT for Edge Vector registers
```

The FPR WBT is specialized with `ISSUE1_ENABLE=0` because FP instructions only
issue on scalar lane0. GPR lane1 remains enabled for memory/tensor-sidecar work.

Instructions that cross domains, such as integer/FPR moves or converts, check
the source domain and reserve the destination domain independently.

## Inputs

From `edge_predecoder`:

```text
issue_valid
issue_ready
issue1_valid
issue1_ready
issue_pc
issue_inst
issue_len
issue_is_pseudo
issue_pseudo_kind
issue_seq_id
issue_epoch
issue1_pc
issue1_inst
issue1_seq_id
issue1_epoch
scalar_def_valid
scalar_def_domain
scalar_def_dst_reg
scalar_def_bank
scalar_def_seq_id
scalar_def_epoch
scalar1_def_valid
scalar1_def_dst_reg
scalar1_def_bank
scalar1_def_seq_id
scalar1_def_epoch
scalar_gpr_src_mask
scalar_fpr_src_mask
scalar_n_src_gpr
scalar_alloc_n_capture
scalar_n_capture_id
scalar_wait_vector_done
scalar_wait_tensor_done
```

From vector/retire side:

```text
vec_done_valid
vec_done_seq_id
retire_alloc_ready
ordered_retire0_valid
ordered_retire0_seq_id
ordered_retire0_epoch
ordered_retire1_valid
ordered_retire1_seq_id
ordered_retire1_epoch
redirect_kill_valid
redirect_kill_seq_id
redirect_kill_epoch
```

First-slice load/FPR completion:

```text
gpr_placeholder_complete_valid
gpr_placeholder_complete_seq_id
gpr_placeholder_complete_epoch
gpr_placeholder_complete_reg
gpr_placeholder_complete_bank
gpr_placeholder_complete_value

lsu_load_resp_valid
lsu_load_resp_seq_id
lsu_load_resp_epoch
lsu_load_resp_value

lsu_load_req_valid
lsu_load_req_ready
lsu_load_req_seq_id
lsu_load_req_epoch
lsu_load_req_addr
lsu_load_req_size
lsu_load_req_signed
lsu_load_req1_valid
lsu_load_req1_ready
lsu_load_req1_seq_id
lsu_load_req1_epoch
lsu_load_req1_addr
lsu_load_req1_size
lsu_load_req1_signed
lsu_store_req_valid
lsu_store_req_ready
lsu_store_req_seq_id
lsu_store_req_epoch
lsu_store_req_addr
lsu_store_req_size
lsu_store_req_data
lsu_store_req_wstrb
lsu_store_req1_valid
lsu_store_req1_ready
lsu_store_req1_seq_id
lsu_store_req1_epoch
lsu_store_req1_addr
lsu_store_req1_size
lsu_store_req1_data
lsu_store_req1_wstrb

lsu_misaligned_valid
lsu_misaligned_lane1
lsu_misaligned_seq_id
lsu_misaligned_epoch
lsu_misaligned_is_store
lsu_misaligned_size
lsu_misaligned_addr

fpr_placeholder_complete_valid
fpr_placeholder_complete_seq_id
fpr_placeholder_complete_epoch
fpr_placeholder_complete_reg
fpr_placeholder_complete_bank
fpr_placeholder_complete_value
```

## Outputs

To LSU/D-cache:

```text
lsu_load_req_valid
lsu_load_req_ready
lsu_load_req_seq_id
lsu_load_req_epoch
lsu_load_req_addr
lsu_load_req_size
lsu_load_req_signed
lsu_store_req_valid
lsu_store_req_ready
lsu_store_req_seq_id
lsu_store_req_epoch
lsu_store_req_addr
lsu_store_req_size
lsu_store_req_data
lsu_store_req_wstrb
cache_op_valid
cache_op_ready
cache_op_is_va
cache_op_kind
cache_op_addr
cache_op_seq_id
cache_op_epoch
cache_op_complete_valid
cache_op_complete_seq_id
cache_op_complete_epoch
```

The producer port has no backpressure in this proof slice. `issue_ready` is
gated by local producer queue space so internally generated ALU producers do not
overflow the queue while external placeholder completions drain.
The pipe also exposes debug-only ready breakdown outputs for the ROM harness:
redirect blocking, retire capacity, producer queue readiness/count, GPR/FPR WBT
readiness, execution-unit readiness, and the candidate class bits used by the
`issue_ready` equation. These signals are observability aids for `+trace_rom`;
they do not participate in the architectural contract.

To retire:

```text
retire_valid                 // legacy single retire pulse, kept for focused tests
retire_seq_id
retire_epoch
retire_is_pseudo

retire_alloc_valid           // scalar token accepted into program order
retire_alloc_seq_id
retire_alloc_epoch
retire_alloc_kind
retire_alloc_serializing
retire_alloc1_valid          // lane1 scalar token accepted into program order
retire_alloc1_seq_id
retire_alloc1_epoch
retire_alloc1_kind
retire_alloc1_serializing

`PSEUDO_TENSOR_GPR_HOLDER` does not assert `retire_alloc_valid` or
`retire_alloc1_valid`; it is an internal scalar-order snapshot write, not a
programmer-visible retire token.

retire_complete0_valid       // ALU/GPR writeback completion
                             // or lane1 store no-writeback completion
retire_complete0_seq_id
retire_complete0_epoch
retire_complete1_valid       // GPR load response by default; lane0 integer
                             // load acceptance in early-retire mode
retire_complete1_seq_id
retire_complete1_epoch
retire_complete2_valid       // FPR placeholder completion
retire_complete2_seq_id
retire_complete2_epoch
retire_complete3_valid       // no-writeback or cache-op completion
retire_complete3_seq_id
retire_complete3_epoch
```

Retire completion port 4 carries lane1 Fast/no-writeback completions and the
lane1 integer load-accept completion in early-retire mode. If a prior lane1
Fast completion occupies it, a candidate lane1 load is retained for replay.

## Lane1 Pairing Rules

Lane1 is an in-order dual-issue shell, not a ROB-backed superscalar path. It is
accepted only when lane0 also issues in the same cycle and the pair is proven
safe by local checks.

Allowed in this slice:

```text
load + load, different destination GPRs, all sources ready
store + store, all sources ready
fast integer ALU + load/store, with lane0-result forwarding where needed
load/store + independent fast integer ALU
```

Rejected in this slice:

```text
RV64M/control/system/fence/FP in lane1
ALU + ALU
mixed load/store pairs
lane0 rd == lane1 rd
lane1 ALU rs1/rs2 depends on a lane0 load destination
any WBT, retire, or LSU resource backpressure
```

If lane1 is rejected, the frontend/predecoder must keep or replay that token and
issue it later through lane0. The frontend ROM path now connects the predecoder
`scalar1_*` candidate directly into this boundary, while non-ROM focused tests
may still tie lane1 off when they are not exercising dual scalar issue.

Placeholder memory packet:

```text
mem_placeholder_valid
mem_placeholder_is_store
mem_placeholder_size       // 0 byte, 1 halfword, 2 word, 3 doubleword
mem_placeholder_load_signed
mem_placeholder_addr
mem_placeholder_store_data
mem_placeholder_seq_id
mem_placeholder_epoch
mem_placeholder1_valid
mem_placeholder1_is_store
mem_placeholder1_size
mem_placeholder1_load_signed
mem_placeholder1_addr
mem_placeholder1_store_data
mem_placeholder1_seq_id
mem_placeholder1_epoch
```

`mem_placeholder_*` is the canonical lane0 address-generation packet.
`mem_placeholder1_*` is the matching lane1 packet for accepted memory-only
pairs. The transitional TCM/ROM harness may accept both packets in the same
cycle and return load data later through the single `lsu_load_resp_*` channel;
the LSU load queue, not the harness, owns `rd/bank` metadata for load
completion.

Placeholder system packet:

```text
system_placeholder_valid
system_placeholder_funct3
system_placeholder_csr
system_placeholder_rd
system_placeholder_rs1
system_placeholder_rs1_value
system_placeholder_seq_id
system_placeholder_epoch
```

Placeholder fence packet:

```text
fence_placeholder_valid
fence_placeholder_i
fence_placeholder_seq_id
fence_placeholder_epoch
```

Fatal unreachable/error-report packet:

```text
fatal_report_valid
fatal_report_code
fatal_report_inst
fatal_report_seq_id
fatal_report_epoch
ebreak_report_valid
ebreak_report_seq_id
ebreak_report_epoch
```

Placeholder scalar control packet:

```text
control_placeholder_valid
control_placeholder_taken
control_placeholder_target
control_placeholder_seq_id
control_placeholder_epoch
```

Production scalar-to-core readout:

```text
gpr_busy_status
```

`EDGE_DEBUG` scalar-pipe readout:

```text
debug_gpr_read_reg
debug_gpr_read_data
debug_fpr_read_reg
debug_fpr_read_data
debug_fpr_busy
```

Tensor/DMA commands consume issue-ordered holder snapshots; the scalar pipe
does not expose separate committed-GPR read ports for tensor operand fallback.
The holder snapshot path reuses the accepted scalar lane operand reads.
The `debug_*` GPR/FPR read and FPR busy ports are only present when
`EDGE_DEBUG` is defined. Production builds do not keep runtime debugger register
read ports; Verilator tests that need those signals either define `EDGE_DEBUG`
or probe the scalar-pipe internals hierarchically.

## Pseudo Instruction Behavior

### VEC_TOKEN

No GPR/FPR read by the scalar pipe. Creates the retire entry that waits for the
matching vector completion.

### TENSOR_SYNC_JOIN

No GPR/FPR read by the scalar pipe. Creates the scalar retire entry for
`tensor.sync` or `dma.sync`; unlike ordinary no-writeback pseudos it waits for
the matching accel completion. Tensor GPR holders only write snapshots and do
not allocate retire entries.

## Placeholder RV64IM/FPR Behavior

The first GPR datapath supports placeholder RV64IM integer operations.
Arithmetic and control-target evaluation are delegated to `edge_scalar_alu`;
load/store placeholder execution is delegated to the `edge_lsu_top` subsystem;
and system/fence placeholder packet formatting is delegated to
`edge_scalar_csr_sys`. This pipe keeps instruction classification, operand
reads, WBT reserve/release, writeback, producer fills, and done/retire events.

Supported placeholder operations:

```text
LUI, AUIPC
JAL, JALR
BEQ, BNE, BLT, BGE, BLTU, BGEU
ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
ADDIW, SLLIW, SRLIW, SRAIW
ADDW, SUBW, SLLW, SRLW, SRAW
MULW, DIVW, DIVUW, REMW, REMUW
SH1ADD, SH2ADD, SH3ADD
ADD.UW, SH1ADD.UW, SH2ADD.UW, SH3ADD.UW, SLLI.UW
LB, LH, LW, LD, LBU, LHU, LWU      // placeholder, no memory read
SB, SH, SW, SD                     // placeholder, no memory write
FENCE, FENCE.I                     // placeholder, no ordering side effect
CSRR cycle                         // single-cycle GPR producer, no CSR side effect
SYSTEM/CSR opcode except EBREAK    // placeholder, no privileged-state side effect
EBREAK                             // ordered host-completion stop marker
FADD.S, FSUB.S, FMUL.S
FMADD.S, FMSUB.S, FNMADD.S, FNMSUB.S
```

Accepted ALU, Zba, `lui`, `auipc`, `jal`, and `jalr` instructions reserve GPR
WBT when `rd != x0`, issue `edge_scalar_alu`, write the GPR file from the ALU
complete packet, release WBT through that completion, and emit a scalar retire pulse. Fast ALU
instructions complete one cycle after accept through a registered complete
packet; RV64M instructions complete from the registered multi-cycle ALU path.
Zba operations are scalar arithmetic helpers for address/index formation; they
do not issue an LSU request by themselves.

Accepted branches issue `edge_scalar_alu`, emit a placeholder scalar control
packet from the fire-qualified issue-cycle resolved result, and retire.
Accepted `jal`/`jalr` emit both the GPR link writeback and the placeholder
control packet. This bypasses the ALU completion register for redirect only;
it does not predict either path or let a younger scalar instruction execute
past the branch. Operands, dependencies, retire capacity, and the ALU issue
resource must all be ready before the control packet is valid.

The first implemented CSR behavior is the standard benchmark read
`csrrs rd, cycle, x0` (`CSR_CYCLE = 12'hc00`). When `rd != x0`, the scalar pipe
reserves the GPR WBT entry, latches the local cycle counter, completes through a
registered GPR complete pulse on the following cycle, writes the captured value
into `rd`, emits a GPR producer packet, and retires the token. This keeps the
CSR benchmark path behind the same registered writeback boundary as ALU
completions. This is intentionally only a read of `cycle`; other CSR encodings
still flow through `edge_scalar_csr_sys` as serializing placeholder packets with
no privileged-state side effect. The scalar pipe classifies system/CSR, fence,
cache-maintenance, and scalar DMA-control instructions through one serializing
issue class. Except for the local read-only `cycle` CSR, this class waits for
both the LSU load queue and store buffer to empty before issue. Tensor/DMA
snapshot pseudo-uops are unchanged: their 64-bit owner occupies the frontend
window and their selected GPR sources remain protected by WBT dependencies
until the snapshot is captured.

The FPU island issues supported FMAC-family operations to `edge_fpu_fmac`,
sign/min/max/compare/class/move operations to `edge_fpu_misc`, and format or
integer conversions to `edge_fpu_cvt`. It checks the actual GPR/FPR source
domain, reserves the actual destination domain (including architectural f0),
and routes completion through the matching WBT writeback, producer, and retire
path with the original sequence/epoch/bank. Divide and sqrt use the integrated
single-outstanding slow slot; unsupported or reserved OP-FP encodings remain
outside this slice.

The conversion contract treats FCVT among D/S/H as an identity move on
the physical FP32 FPR payload. Only FP32-to-integer and integer-to-FP32 FCVT
operations perform numeric conversion. They support RNE, RTZ, RDN, RUP, and
RMM directly from instruction `rm=000..100`. Dynamic `rm=111` is accepted as
RNE (`000`) until the core grows architectural `frm`/FCSR state. Encodings
`101/110` take the unsupported/fatal path. On
RV64, W and WU conversion results are both sign-extended from bit 31. The
external move contract is different from FPR-to-FPR FCVT: FMV.X.W
sign-extends the FP32 payload, while FMV.X.H first rounds physical FP32 to
binary16 using RNE and then sign-extends bit 15.
An accepted `LOAD-FP` packet reserves the FPR WBT and enters the LSU load
queue. The backend response retains its FPR destination domain, performs the
H/S/D-to-physical-FP32 boundary conversion, writes the FPR file, releases the
WBT, emits `producer_valid` with `producer_domain = FPR`, and completes retire.
The separate `fpr_placeholder_complete_*` input is only a compatibility/test
injection hook.

Accepted integer loads reserve the GPR WBT for `rd`, issue `edge_lsu_top`, and
emit `mem_placeholder_valid` from the LSU complete packet. In the maintained
default they wait for the LSU-originated GPR load completion to write the GPR
file, release the WBT, emit `producer_valid`, and retire. With
`ENABLE_EARLY_LOAD_RETIRE=1`, successful queue allocation completes retire
first; the response later performs writeback, producer publication, and WBT
release without a duplicate retire completion. Accepted integer stores check
GPR source readiness for base and store-data registers, issue `edge_lsu_top`, emit
`mem_placeholder_valid` with the computed address and store data from the LSU
complete packet, and retire in the same placeholder slice.

`gpr_placeholder_complete_*` remains as a compatibility path for focused unit
tests that want to inject a GPR load completion directly. Integrated ROM/TCM
tests should feed `lsu_load_resp_*` instead so LSU owns `rd/bank` metadata.

The maintained default couples retire to load-data completion:

```text
load acceptance:
  scalar pipe reserves rd in GPR WBT
  edge_lsu_top allocates a load-queue entry
  younger independent scalar instructions may continue

load completion:
  edge_lsu_top returns rd/value/seq_id/epoch
  scalar pipe writes GPR, releases WBT, emits producer_valid, and retires
```

The implemented default-off experiment further separates retire completion
from data completion for integer loads:

```text
eligible load accepted into edge_load_queue:
  send seq_id/epoch completion to edge_retire_sync
  keep destination WBT reserved

matching load response:
  write GPR, emit producer_valid, and release WBT
  do not emit another retire completion
```

This is not out-of-order architectural retirement: `edge_retire_sync` still
advances tokens strictly in program order. It only lets the oldest accepted
load leave the retire queue while the LSU retains responsibility for its late
writeback. Dependent and same-destination younger instructions remain blocked
by WBT; independent younger instructions can use the retire capacity that was
previously pinned by the missed load.

The RTL keeps early load retire behind the default-off
`ENABLE_EARLY_LOAD_RETIRE` experiment switch. Both integer memory lanes have
acceptance-side completion paths. Load response remains the completion source
in the maintained mode; the experimental mode has directed coverage proving
that pending late writeback continues to block fence and cache-maintenance
issue. AXI refill errors now return through LSU with the matching sequence and
epoch and raise fatal report code `4`; the failed line is not installed and
the matching late completion still releases bounded LSU/WBT ownership. This is
an asynchronous machine-check policy, not precise rollback. STB committed
drain is enabled in the core. In the experimental mode,
`retire_complete1` changes meaning from load-data completion to lane0 load-
accept completion; lane1 uses an independent completion source so a paired load
cannot remain response-coupled. FP loads stay response-coupled because their
shared completion queue does not yet retain a source-kind discriminator.

For stack/index-heavy code, the scalar pipe must not treat "an older load is in
flight" as a global issue blocker. A younger instruction should be blocked only
by its own dependency/resource checks:

- source GPR/FPR WBT busy
- destination WBT cannot reserve
- LSU issue resource unavailable
- load queue or store buffer full
- memory-ordering stall, such as an older store with unknown address
- fence/cache-op/flush ordering

Under that model, four independent loads can be accepted in four cycles by a
single-issue scalar pipe, and a following independent ALU instruction can issue
before those loads complete. A dependent ALU instruction still stalls until the
specific producer load releases its destination WBT.

The GPR WBT connects ALU completion and integer load placeholder completion on
separate completion ports. This keeps an ALU result from masking an independent
load completion when both arrive in the same cycle; the scalar pipe still owns
architectural register-file writeback ordering.

The scalar pipe also exposes those completion sources separately to
`edge_retire_sync`. The legacy single `retire_valid` output remains as a
priority-compressed compatibility pulse for existing focused tests, but composed
frontends should allocate scalar tokens with `retire_alloc_*` and mark done with
the four `retire_complete*` ports:

```text
complete0: ALU/JAL/JALR GPR-producing completion
complete1: LSU/load placeholder GPR completion
complete2: FPR placeholder completion
complete3: no-writeback completion, including stores, branches, pseudo,
           system/fence placeholders, rd=x0 scalar ops, and cache-op
           completions returned by the D-cache boundary
```

This is a wiring step toward using `edge_retire_sync` as the architectural
in-order retire point. It does not yet add multi-port architectural GPR/FPR
writeback or data forwarding; producer/writeback remains conservative inside
`edge_scalar_pipe`.

The first frontend ROM LSU integration test provides a small testbench scalar
RAM responder behind `mem_placeholder_*`. It proves that a scalar store updates
the responder RAM, a later scalar load returns through
`gpr_placeholder_complete_*`, and a younger ALU consumer of the load destination
does not issue before the load completion releases the GPR WBT. This responder
is a harness proof point only; it is not the D-cache or DTCM implementation.

Accepted `fence`/`fence.i` instructions issue `edge_scalar_csr_sys`, emit a
placeholder fence packet from the system-unit complete packet, and retire in the
same slice. The packet carries `fence_placeholder_i` to separate
instruction-fetch ordering from ordinary data fences when a real fence/frontend
boundary is connected.

Accepted Edge custom cache-control and DMA instructions still issue
`edge_scalar_csr_sys` and emit a placeholder system packet. DMA commands retire
in the same slice after their ready handshake. Cache-maintenance commands
allocate a serializing retire entry at issue but do not complete retire until
the D-cache returns `cache_op_complete_*`.

```text
dcache all: opcode=0x0b funct7=0 funct3=0 rd=x0 rs1=x0 rs2={x1,x2,x3}
dcache VA:  opcode=0x0b funct7=0 funct3=1 rd=x0 rs2={x5,x6,x7}
dma.start:  opcode=0x2b funct7=0 funct3=0 rd=len rs1=src rs2=dst
dma.sync:   opcode=0x2b funct7=1 funct3=0 rd=x0 rs1=x0 rs2=x0
```

For D-cache maintenance, the scalar pipe emits `cache_op_valid`,
`cache_op_kind`, `cache_op_is_va`, `cache_op_addr`, and the scalar sequence /
epoch; VA operations read `rs1` as their address operand. Cache-maintenance
issue is held until both the LSU load queue and store buffer are empty so all
older scalar memory operations have completed or drained into D-cache before a
clean observes the line. The scalar pipe holds a
single outstanding cache-maintenance command pending until
`cache_op_complete_valid`, then reports `retire_complete3` with the returned
sequence and epoch. While that pending bit is set, later scalar issue is held
so younger loads, stores, DMA placeholders, and control operations cannot pass a
still-running cache maintenance command. For `dma.start`, the scalar pipe treats `rs1`, `rs2`, and
`rd` as source registers and emits `dma_start_src`, `dma_start_dst`, and
`dma_start_len`; issue is held until the DMA port is ready, no cache operation
is pending, and both LSU queues are empty. For `dma.sync`, issue is held until
`dma_sync_ready`, no cache operation is pending, and both LSU queues are empty.

Accepted `SYSTEM` opcode instructions, excluding architectural `EBREAK`
(`32'h0010_0073`), issue `edge_scalar_csr_sys`, emit a placeholder system packet
from the system-unit complete packet, and retire in the same slice. The packet
preserves `funct3`, CSR field, `rd`, and `rs1`. This is only a decoded
system-opcode boundary; the Edge ASIC target does not implement a RISC-V
privileged CSR machine behind this path.

Unknown or reserved scalar encodings emit `fatal_report_valid` with fatal error
code `2`, zero-extended `issue_inst` in `fatal_report_inst`, and the original
sequence/epoch. `EBREAK` is separated from the fatal path, allocates a
serializing retire token, and emits registered `ebreak_report_valid` with the
same sequence/epoch only after ordered-retire feedback returns that token. This
ensures every older instruction and committed store is visible at the SoC
completion boundary; a fixed post-issue delay is not sufficient when older
variable-latency work remains in the retire queue.
Redirect kill discards a pending younger `EBREAK` report just as it discards
the corresponding retire token.
Semantically this is closer to `exit(err_code)` or
`panic!("unreachable")` than to a RISC-V exception. In `IVERILOG_SIM`, taking
this path prints the sequence, epoch, PC, and instruction, then normally stops
simulation with `$fatal`; the SoC runner may compile with
`EDGE_SCALAR_PIPE_EBREAK_REPORT_ONLY` so `EBREAK` is delivered through the SoC
completion event before simulation exits. For first-slice ROM and riscv-tests
execution, `EBREAK` is the explicit stop marker after software writes any
pass/fail code; it retires as an ordered host-completion marker rather than a
normal privileged system placeholder. In an ASIC
system slice, this packet should feed a small completion/error adapter that can
write status and assert an interrupt toward the host CPU. It must not be
expanded into standard RISC-V CSR write/read state or an internal interrupt
path.

Misaligned scalar load/store attempts use the same first-slice reporting
mechanism with fatal error code `3`. The focused expected-failure regressions
separate `EDGE_SCALAR_PIPE_FATAL_UNREACHABLE` from
`EDGE_SCALAR_PIPE_FATAL_MISALIGNED` so decode/fatal regressions and LSU
alignment regressions fail independently.

A D-cache/AXI refill error returned by LSU uses fatal error code `4` with the
matching load sequence and epoch. The dedicated expected-failure regression
keeps this intentional stop separate from ordinary early-load-retire coverage.

## Scalar Memory Contract

- Scalar LSU owns D-cache access.
- Scalar LSU may access DTCM only through the scalar memory path.
- Scalar DTCM access does not automatically order older vector DTCM writes.
  Software/compiler code must issue `vector.sync` before scalar DTCM reads that
  inspect vector-produced data.
- Future auto-insertion of an equivalent sync pseudo instruction from
  predecoder scalar-load address analysis is optional and not part of the first
  proof slice; explicit `vector.sync` remains the base contract.
