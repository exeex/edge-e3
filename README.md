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
