# edge-e3

edge-e3 is the product-specific RTL package for the e3 configuration and is
composed with the Edge-32 scalar package and edge-asic leaves. The suffix `3`
means `2^3 = 8`: this configuration contains an 8x8 tensor unit, one
activation unit (ACTU), and one compare unit (CMPU).

## Specification

| Item @ 1 GHz | edge-e3 |
| --- | ---: |
| Tensor specification | 8x8 |
| Tensor peak throughput | 0.128 TFLOPS |
| ACTU / CMPU | 1 / 1 |
| SiLU throughput | 1 G elements/s |
| Softmax throughput | 0.333 G elements/s |

The edge-e3 hardware-identification fields are product ID 3, `P=3`, `Q=3`,
BF16 and INT8 weight support, BF16 scale support, and Tensor specification v1.
The product passes these 47 constant bits into either RV core with the
`EDGE_ASIC_ID` elaboration parameter. The selected core completes CSR `0xfc0`
with its own core/FPU/VPU fields; no runtime ID signals cross the boundary.

Tensor throughput assumes one complete tensor MAC-array operation per cycle
and counts one multiply-accumulate as two floating-point operations. Softmax
throughput assumes three ACTU passes.

## Integration

The maintained production top module is `edge_core_edge32_top` in
`edge_core/edge_core_scalar_product_top.v`.

Run Verilator or another filelist-compatible RTL tool from the repository root:

```sh
verilator --lint-only -Wno-fatal --top-module edge_core_edge32_top \
  -f edge_core/filelists/edge_core_edge32_top_verilator.fl
```

The Edge-32 product filelist includes
`edge_core_edge32_platform_verilator.fl`, which contains only the E3 platform
and Edge-32-owned FPU/cache leaves. It has no `edge-rv` source dependency.

E3 owns the composed product top, DTCM/DMA, tensor/ACTU/CMPU, accelerator I/O,
and product memory adapters. Edge-32 owns its scalar, FPU, cache, BIU, and ASIC
instruction pipe.

Unit tests and internal implementation contracts are maintained separately
and are not included in this public package.

The minimum-area product wrapper uses Edge-32 as its sole maintained scalar
implementation:

```sh
cmake -S . -B build-e3-edge32
```

The wrapper retains the AXI128, 64-bit scalar-DTCM compatibility, DMA, Tensor,
ACTU, and CMPU platform. Edge-32 supplies ASIC32 directly.

## License

edge-e3 is available under the custom edge-e3 Hardware License 1.0. Simulation,
modification, distribution, and FPGA implementation are permitted. Manufactured
silicon may contain no more than one edge-e3 core per physical package, and
products using edge-e3 must provide attribution. Multi-core physical packages
require a separate written commercial license.

See [LICENSE.md](LICENSE.md) for the complete terms. This is a source-available
hardware license, not an OSI-approved open-source license.

### Tensor/DTCM product layout

The tensor product entry is `edge_tensor_unit/edge_tensor_unit.v`, containing
module `edge_tensor_unit`. The maintained backend is fixed to packed WLD and
the final dot-local relay, supporting FP4 weights together with
BF22-in-FP32 psum. Earlier tensor, DTCM bridge and unused core-debug sources
are retained in each owning block's `legacy/` directory. Production filelists
exclude them; historical tests and synthesis comparisons opt in explicitly.

Current tensor filenames describe ownership: `edge_tensor_datapath`,
`edge_tensor_weight_banks`, `edge_tensor_wld_tile`, `edge_tensor_weights`, and
`edge_dot8_weight_bank`. These replace development-era packed/sidecar/relay
names. The current module at the tensor block entry is `edge_tensor_unit`;
the archived wrapper uses `edge_tensor_unit_legacy` to avoid a module-name
collision in comparison builds.

Current H4 implementations are `edge_dtcm_h4`, `edge_dtcm_h4_bank`,
`edge_wsld_h4`, and `edge_dma_h4`. H4, bank16 and narrow-client qualifiers
remain where they describe actual topology or transfer width.

The tensor unit and engine default to `WIDE_H4=1`, `LOWER_SIX=1`, and
`READ_LATENCY=4`. Older memory-schedule fixtures explicitly override transport
parameters. Product RTL has no `PACKED_WEIGHT` or `RELAY_WEIGHT` implementation
selector; archived comparison modules retain historical choices.

Canonical source manifests live in `edge_tensor_unit/filelists/edge_tensor.fl`
and `edge_dtcm_subsys/filelists/edge_{dtcm,accel}.fl`. Entries are file-relative
and included with `-F`. The product Verilator filelist, module CMake tests and
DTCM synthesis manifest share these lists. CMake consumers use
`cmake/EdgeSources.cmake`, which tracks nested manifests and RTL dependencies.
Historical tests explicitly load
`edge_tensor_unit/legacy/filelists/edge_tensor_legacy.fl` in addition to product
sources; product tests compile without that legacy closure.

The public `edge_dtcm_subsys` boundary defaults to wide H4 when `SRAM_H4=1`.
P and O use native 256-bit group rotation; I, WSLD, shared LSU/ACTU/CMPU,
and DMA use locally exchanged 128-bit halves. WSLD and DMA restore contiguous
order in client buffers. Circular DMA releases beats in input order only
after physical SRAM commit.

Private BF22-in-FP32 P/O vectors are eight contiguous 32-bit words with
32-byte-aligned bases. BF16 public inputs/outputs and DTCM address mapping
are unchanged. The composed SDK's `edge_e3_tensor_layout.hpp` selects this
layout by default. Historical comparison builds must define
`EDGE_DTCM_LEGACY_H4` for both RTL and software; the composed CMake option
`EDGE_E3_WIDE_H4=OFF` does this together. It is a build-time ABI choice, not
a runtime mode. Existing binaries that access the old FP32 stripe layout
must be rebuilt. Single-vector NNC FP4 scratch already satisfies both layouts.

Standalone inferred-SRAM core tests retain their explicit legacy configuration.
This promotion does not change E4 or claim physical timing/routing closure.
