# Historical tensor implementations

These sources preserve development and comparison implementations. Production
filelists exclude this directory. Tests and synthesis comparisons that select
an old implementation must list its sources explicitly.

- `edge_tensor_unit.v`: original tensor wrapper and lease/remux implementation.
- `rtl/ref/wld8x8/`, `edge_dot8_unit`, `edge_tile8x8_unit`: original unpacked
  weight-fill and compute path (`PACKED_WEIGHT=0`).
- `rtl/weight/` and `rtl/compute/*32*`: circular, WLD2x2 and packed32 experiments.
- `edge_dot8_weight_bank_elements`: earlier axis relay (`RELAY_WEIGHT=1`).
- Token, start-queue, stream-engine and WLD2x2 sidecars: development boundaries
  superseded by the current bank16 engine and dot-local relay.

The maintained entry is `../edge_tensor_unit.v` (module
`edge_tensor_unit_bank16`). Current RTL uses packed WLD with `RELAY_WEIGHT=2`,
FP4/FP8 promotion at dot ingress, and BF22-in-FP32 psum. The shared scale
multiplier lives in `../rtl/compute/edge_bf16_mul8_pipe.v`; historical tiles
also require that file. Matching implementation contracts remain in the
private test package under the same relative legacy paths.
