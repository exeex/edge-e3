# edge-e3 Hardware

This directory contains the edge-e3 product RTL: an 8x8 tensor implementation
with one ACTU and one CMPU. Its hardware licensing model is documented in
`LICENSE.md`.

Module unit tests are intentionally excluded from this public product tree. In
the development repository they live in the optional sibling `src/test-e3`
package, which is planned as a private submodule.

The target is not a general-purpose CPU. It is a programmable static
accelerator: a mostly fixed ASIC-like vector/tensor dataflow system with a small
scalar control stream. The scalar side exists to sequence work, set up memory,
feed captured operands, and let `.s`/`.c` simulation tests verify results.

## Mental Model

```text
IFU/I-cache fetch packet
        |
        v
edge_predecoder
        |
        +----------------+----------------+
        |                                 |
        v                                 v
edge_scalar_pipe                  edge_accel_pipe
RV64 scalar                       64-bit DMA/Tensor/ACTU
GPR/FPR/LSU                       accelerator command/control
        |                                 |
        +----------------+----------------+
                         v
          edge_retire_sync
          in-order completion
```

The design has one programmed operation stream and one in-order completion
contract, but scalar, vector, and tensor-pipeline work may execute concurrently.
Vector, tensor, and DMA pipelines are expected to behave like fixed hardware
pipelines once launched; CPU-style stop-and-inspect debug is not a first-slice
goal.

## What To Read First

- `edge_ifu_fetch/edge_ifu_fetch.v.md` defines the 128-bit fetch packet,
  packet-middle redirect, and no-prediction first frontend slice.
- `edge_predecoder/edge_predecoder.v.md` explains the 32-bit scalar / 64-bit Edge Vector /
  64-bit Edge Tensor stream split and pseudo-token generation.
- `edge_scalar_snapshot/edge_scalar_snapshot.v.md` and
  `edge_accel_cmd_queue/edge_accel_cmd_queue.v.md` define the production four-slot tensor/DMA
  GPR snapshot path.
- `edge_scalar_pipe/edge_scalar_pipe.v.md`, `edge_scalar_alu/edge_scalar_alu.v.md`,
  `edge_scalar_branch/edge_scalar_branch.v.md`,
  `edge_lsu/edge_lsu_top.v.md`, `edge_scalar_lsu/edge_scalar_lsu.v.md`, and
  `edge_scalar_csr_sys/edge_scalar_csr_sys.v.md` cover the scalar state/WBT
  boundary and modular scalar execute units.
- `edge_accel_cmd_queue/edge_accel_cmd_queue.v.md` and
  `edge_accel_pipe/edge_accel_pipe.v.md` cover the maintained accelerator
  command, snapshot, issue, and completion boundary.
- `edge_wbt/edge_wbt.v.md` defines the shared GPR/FPR/VR dependency/writeback primitive.
- `edge_dtcm_subsys/edge_dtcm_subsys.v.md`, `edge_dtcm_dma/edge_dtcm_dma.v.md`, `edge_dcache/edge_dcache.v.md`,
  `edge_lsu/edge_lsu_top.v.md`, and `edge_scalar_lsu/edge_scalar_lsu.v.md`
  cover memory movement and routing.
- `edge_accel_pipe/edge_accel_pipe.v.md` documents the tensor command queue/control boundary,
  including DMA routing, descriptor visibility, WLD waits, and done reporting.
- `edge_tensor_unit/edge_tensor_unit.v.md` documents the tensor datapath wrapper and descriptor
  behavior behind the accelerator pipe.

## Scalar, Vector, And Tensor Split

Scalar instructions remain 32-bit RV64IM/F control instructions. Edge Vector,
DMA, and Tensor instructions are 64-bit custom commands using the shared
standard 64-bit length marker `inst[6:0] = 7'b0111111`. The second 32-bit
parcel carries `opcode8 = high_word[7:0]`; `opcode8[7]` is the stream select
that routes Vector versus Tensor/DMA commands.

The predecoder owns instruction length and stream classification. The legacy
scalar IDU must not see either real 64-bit opcode family.

The scalar side owns:

- GPR/FPR state and scalar dependencies
- GPR/FPR WBT instances
- scalar LSU and D-cache traffic
- scalar branch/control decisions
- operand capture for vector and tensor-pipeline commands

The accelerator lane owns:

- VR architectural state
- VR WBT instance
- Edge Vector command queue and execution
- vector DTCM load/store traffic

The tensor side owns:

- DMA/Tensor command queueing under the Tensor/DMA `opcode8[7]` stream
- DMA start/sync command acceptance and progress visibility
- Tensor pending/job descriptor updates, `tensor.start`, and `tensor.sync`
- DTCM clients for DMA and Tensor IO/WLD
- `tensor.wld_wait_dma`-style command dependencies that let WLD start after DMA
  has delivered a required byte count, without exposing a scalar DMA-progress CSR

## GPR `n` Capture

The common loop shape is:

```c
for (int n = element_num; n > 0; n -= vl) {
  vop(..., n);
}
```

Every vector instruction in the loop uses the current iteration's `n`, but the
accelerator pipe must not read the live scalar GPR at issue time. Instead,
predecode/vector decode performs a narrow rename/capture operation:

```text
decode vector instruction:
  derive n_src_gpr from the vector encoding
  allocate n_capture_id through the normal capture-slot mechanism
  bind the capture slot to the current scalar producer version of n_src_gpr

scalar producer:
  writes or forwards n_src_gpr
  copies the produced value into the n_capture_id slot
  marks the capture slot ready

vector command:
  waits for capture_ready_all
  selects n from capture_payload[n_capture_id]
  computes active_elems = clamp(n, 0, vl)
```

After the capture slot is filled, scalar code may overwrite the same
architectural GPR for the next loop iteration. Older vector commands continue to
use their captured copy.

Loop prediction treats these as two values:

```text
n_capture:
  lite-rename capture slot/value for the current iteration's vector `n`

n_next:
  scalar loop-control value after decrement, tested by the following
  conditional branch back to the loop head
```

The frontend may optimistically predict from `captured_n > 0` before the scalar
branch result is ready, but scalar branch resolution from the real update +
conditional-branch path is authoritative.

## Memory Model

Scalar and vector memory traffic intentionally use different paths:

```text
scalar LSU -> D-cache / external memory, or scalar DTCM client on DTCM hit
vector VLSU -> DTCM only
DMA/Tensor  -> third tensor stream, with DTCM clients behind the tensor queue
DMA         -> explicit external memory <-> DTCM movement
Tensor      -> DTCM clients for IO/psum and WLD
```

D-cache and DTCM are not implicitly coherent. Software tests and explicit DMA or
cache-maintenance sequences are responsible for moving data between external
memory and DTCM when needed.

The first-slice software path keeps the inherited C906 D-cache maintenance
controls available through `tests/software/include/edge_intrinsic.hpp`. DMA tests
clean DRAM sources before DRAM-to-DTCM transfers and invalidate DRAM
destinations after DTCM-to-DRAM transfers.

## Verification Model

The first slice is verified by simulation:

```text
scalar .s/.c test initializes data
scalar code launches vector and tensor-pipeline DMA/Tensor work
scalar code compares output against golden data
RTL/testbench assertions or $fatal catch unsupported internal states
```

There is no first-slice trap, interrupt, breakpoint, debug-halt, or
firmware-visible error-code contract. Unsupported states should fail the
simulator in the detecting RTL or testbench.

## First-Slice Boundary

The first useful proof should focus on:

- splitting 32-bit scalar, 64-bit Edge Vector, and 64-bit Edge Tensor
  instructions before scalar IDU
- preserving scalar token order with +4/+8 PC lengths
- letting vector/tensor completion block retirement without blocking younger
  scalar execution
- capturing `n` through the lite-rename path
- proving branch/loop redirect kills younger vector/tensor commands and capture
  slots
- keeping vector memory traffic on DTCM

Defer full tensor/vector/DMA mixed scheduling, advanced DTCM priority tuning,
wide vector forwarding, full fused-op decode, and CPU-style trap/debug/interrupt
machinery.
