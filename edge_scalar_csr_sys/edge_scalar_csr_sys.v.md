# edge_scalar_csr_sys.v

## Purpose

Single-cycle scalar CSR/system/fence placeholder execute unit. This block owns
formatting for decoded system and fence placeholder packets.

Implemented file:

```text
edge_scalar_csr_sys/edge_scalar_csr_sys.v
```

## Ownership

`edge_scalar_csr_sys` owns:

- CSR/system placeholder packet formatting
- fence/fence.i placeholder packet formatting
- same-cycle completion for accepted system/fence issue packets

It does not own:

- privileged CSR architectural state
- trap/exception/interrupt behavior
- frontend fence implementation
- WBT reserve or release
- architectural retire

The owning pipe validates instruction legality, issues this unit, registers the
placeholder packet, and emits the retire/done event.

## Issue Interface

```text
sys_issue_valid
sys_issue_ready
sys_issue_seq_id
sys_issue_epoch
sys_issue_is_fence
sys_issue_fence_i
sys_issue_funct3
sys_issue_csr
sys_issue_rd
sys_issue_rs1
```

The first slice is always ready.

## Complete Interface

```text
sys_complete_valid
sys_complete_seq_id
sys_complete_epoch
system_placeholder_valid
system_placeholder_funct3
system_placeholder_csr
system_placeholder_rd
system_placeholder_rs1
fence_placeholder_valid
fence_placeholder_i
```

## Tests

Module-local tests:

```text
src/test-e3/edge_scalar_csr_sys/edge_scalar_csr_sys_placeholder_tb.v
```
