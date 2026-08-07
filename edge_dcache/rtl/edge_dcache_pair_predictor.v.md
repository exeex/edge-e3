# edge_dcache_pair_predictor.v

## Purpose

`edge_dcache_pair_predictor` is the combinational bank/phase policy for paired
scalar D-cache requests.

It deliberately contains no queue state, tag SRAM, data SRAM, or valid/ready
storage. It answers only the question that can be known from already formatted
LSU micro-ops:

```text
given lane0 address, lane1 address, current phase, MEM activity, and cache blocking state,
can lane0 fire, and can lane1 fire with it?
```

This keeps D-cache free from ISA misalignment or split/merge behavior. The LSU
must present legal aligned or sliced micro-ops. The predictor only compares
`addr[4:3]` bank bits, `addr[4]` phase half, and same-line/cache-state facts
computed by the owning controller.

## Interface

Inputs:

```text
phase
mem_active
load0_valid/load0_addr
load1_valid/load1_addr
load_metadata_hit
load_dirty_conflict
load_backend_blocked
load1_same_line
store0_valid/store0_addr
store1_valid/store1_addr
store_backend_blocked
store1_same_line
```

Outputs:

```text
load0_ready
load1_ready
load1_same_bank_conflict
store0_ready
store1_ready
store1_same_bank_conflict
```

## Policy

- `addr[4]` selects the two-phase half-bank schedule.
- `addr[4:3]` selects the physical 64-bit SRAM bank.
- When `mem_active=0`, the MEM side has no SRAM access and LSU lanes may use
  either half. When `mem_active=1`, lane0 can fire only when its half matches
  `phase` and the controller says the backend is not globally blocked.
- Lane1 can fire only with lane0, only for same-line hit traffic, only when it
  targets an LSU-eligible half, and only when it does not collide with lane0's
  physical 64-bit bank.
- Miss, dirty-victim, refill, cache-op, DTCM, and different-line policy remain
  outside this predictor and are represented here as blocking or same-line
  facts.

The module is intentionally suitable for reuse earlier in the LSU queue/STB
path once those stages carry the same phase and cache-state summary bits.
