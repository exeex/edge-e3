# E3 tensor dot8 physical target

Owns the E3 dot8 and BF16 lane hardening inputs. The accepted dot8 detailed
route profile is `profiles/asap7-dot8-1g-drt.tcl`; the BF16 profiles are leaf
geometry experiments that reuse the same shared OpenROAD flow.

Legacy commands through `synth/filelists` and `synth/openroad` remain valid via
compatibility symlinks while callers migrate to these canonical paths.

Run the accepted target from the integration workspace with:

```sh
synth/openroad/run_target.sh \
  src/edge-e3/physical/openroad/targets/tensor-dot8
```
