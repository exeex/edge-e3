# edge-e3

edge-e3 is the product-specific RTL package for the e3 configuration and is
composed with the reusable sibling `../edge-rv` package. The suffix `3`
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

Tensor throughput assumes one complete tensor MAC-array operation per cycle
and counts one multiply-accumulate as two floating-point operations. Softmax
throughput assumes three ACTU passes.

## Integration

The production top module is `edge_core_top` in
`edge_core/edge_core_top.v`. The debug wrapper is
`edge_core/rtl/edge_core_debug.v`.

Run Verilator or another filelist-compatible RTL tool from the repository root:

```sh
verilator --lint-only -Wno-fatal --top-module edge_core_top \
  -f edge_core/filelists/edge_core_top_verilator_prod.fl
```

Use `edge_core_top_verilator_debug.fl` instead when the debug wrapper is
required. Paths in both filelists are relative to this package root, so shared
CPU entries use `../edge-rv/...`. The package has no generated-source,
test-harness, or third-party source dependency.

E3 owns the composed core top, DTCM/DMA, tensor/ACTU/CMPU, accelerator I/O and
command queues, retire synchronization, the DMA-aware BIU, and product memory
adapters. Standard RV64 datapath/cache/FPU RTL plus the ASIC bring-up
predecoder, accelerator pipe, and scalar snapshot live in `../edge-rv`.

Unit tests and internal implementation contracts are maintained separately
and are not included in this public package.

## License

edge-e3 is available under the custom edge-e3 Hardware License 1.0. Simulation,
modification, distribution, and FPGA implementation are permitted. Manufactured
silicon may contain no more than one edge-e3 core per physical package, and
products using edge-e3 must provide attribution. Multi-core physical packages
require a separate written commercial license.

See [LICENSE.md](LICENSE.md) for the complete terms. This is a source-available
hardware license, not an OSI-approved open-source license.
