# edge_scalar_lsu.v

## Purpose

Single-cycle scalar LSU placeholder leaf. This block owns scalar load/store
address generation and scalar memory placeholder packet formatting for the
first `edge_lsu_top` slice.

Implemented file:

```text
edge_scalar_lsu/edge_scalar_lsu.v
```

## Ownership

`edge_scalar_lsu` owns:

- scalar load/store effective-address calculation
- load/store size decode from `funct3[1:0]`
- load signedness decode for scalar loads
- load/store alignment detection from effective address and access size
- store-data forwarding into the placeholder packet
- completion packet generation for the accepted issue packet

It does not own:

- GPR/FPR register files
- GPR/FPR WBT reserve or release
- D-cache implementation
- vector DTCM VLSU requests
- architectural retire

`edge_lsu_top` owns the maintained LSU subsystem boundary and instantiates this
leaf in the first placeholder slice. The owning pipe, currently
`edge_scalar_pipe`, reads source registers, checks WBT, reserves load
destinations, registers the placeholder packet, accepts external load
completion, releases WBT, publishes producer fills, and emits done/retire
events.

## Issue Interface

```text
lsu_issue_valid
lsu_issue_ready
lsu_issue_seq_id
lsu_issue_epoch
lsu_issue_is_store
lsu_issue_funct3
lsu_issue_base_value
lsu_issue_offset
lsu_issue_store_data
```

The first slice is always ready.

## Complete Interface

```text
lsu_complete_valid
lsu_complete_seq_id
lsu_complete_epoch
lsu_complete_is_store
lsu_complete_size
lsu_complete_load_signed
lsu_complete_misaligned
lsu_complete_addr
lsu_complete_store_data
```

Completion means the placeholder memory packet is formatted. For loads, the
actual GPR value still arrives later through the owning pipe's external
`gpr_placeholder_complete_*` input. For stores, the placeholder slice treats the
store packet as accepted in the same cycle.

`lsu_complete_misaligned` is asserted when the effective address violates the
access-size alignment:

```text
byte:       always aligned
halfword:   addr[0] == 0
word:       addr[1:0] == 0
doubleword: addr[2:0] == 0
```

The leaf still emits the address/metadata for a misaligned operation; the
owning LSU subsystem decides whether to suppress backend side effects and how to
report the fault.

## Tests

Module-local leaf tests:

```text
src/test-e3/edge_scalar_lsu/edge_scalar_lsu_placeholder_tb.v
```

Subsystem boundary tests:

```text
src/test-e3/edge_lsu/edge_lsu_placeholder_tb.v
```

The leaf test covers aligned placeholder load/store formatting and misaligned
halfword/word detection. The subsystem test covers suppression of load queue,
store buffer, and backend request side effects for misaligned operations.
