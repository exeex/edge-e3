# edge-e3

edge-e3 is the public RTL package for the e3 configuration. The suffix `3`
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
required. All paths in both filelists are relative to this repository root.
The package has no submodule, generated-source, test-harness, or third-party
source dependency.

Unit tests and internal implementation contracts are maintained separately
and are not included in this public package.

## License

Simulation and FPGA use are unrestricted by the per-package fee model. For
manufactured silicon, a physical package containing exactly one edge-e3 core
is intended to use the no-fee Edge Apache License. Other configurations require
a separate commercial license.

The current license text is a draft and is not yet a source-code or hardware
license grant. See [LICENSE.md](LICENSE.md) before using or distributing this
work.
