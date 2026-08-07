# edge_wbt.v

## Additional completion inputs

`complete3_*` lets RV64M release a reservation in the same cycle as a fast-ALU
completion. `complete4_*` carries the independent lane1 Fast ALU completion.
Destination, sequence id, and epoch must still match.

## Purpose

Shared writeback/dependency table primitive for architectural register domains.
The same WBT mechanism should be instantiated for:

```text
GPR WBT
FPR WBT
VR WBT
```

Each instance owns one architectural register namespace and provides the same
source-ready, destination-reserve, completion, and redirect-kill release
behavior. This keeps scalar and vector dependency rules aligned instead of
creating separate special cases for GPR, FPR, and VR.

Implemented file:

```text
edge_wbt/edge_wbt.v
```

The current RTL is a single-owner busy-table primitive. It tracks one pending
producer per architectural register, reports source/destination dependency
stalls, reserves a destination on accepted issue, releases the reservation on
matching completion, and clears younger reservations on redirect kill.
Younger redirect age uses modulo sequence subtraction so cleanup remains
correct across sequence wrap.

## Register Domain Parameters

```text
REG_COUNT
REG_INDEX_BITS
DOMAIN_KIND = GPR | FPR | VR
ISSUE1_ENABLE
```

The first target uses 32 architectural registers for each active domain:

```text
GPR[0..31]
FPR[0..31] if FPR is present
VR[0..31]
```

## Inputs From Decode/Issue

```text
issue_valid
issue_seq_id
issue_epoch
issue_src0
issue_src0_valid
issue_src1
issue_src1_valid
issue_src2
issue_src2_valid
issue_dst
issue_dst_valid
issue1_valid
issue1_seq_id
issue1_epoch
issue1_src0
issue1_src0_valid
issue1_src1
issue1_src1_valid
issue1_src2
issue1_src2_valid
issue1_dst
issue1_dst_valid
```

`issue_*_valid` source/destination fields describe the candidate instruction
being considered for issue. `issue_valid` is the accepted issue pulse. This
separation lets an upstream pipe compute ready/backpressure without creating a
combinational loop through accepted-pulse metadata.

The exact number of source ports can be configured per domain. A scalar GPR/FPR
instance may use fewer ports than a vector fused-op instance.

The `issue1_*` port is an optional same-cycle second reserve/check lane. It is
used by the scalar memory-only lane1 shell and tied off by single-issue users.
Set `ISSUE1_ENABLE=0` for a single-lane domain such as the scalar FPR WBT; the
specialized instance constant-prunes lane1 release, hazard, ready, and entry
update logic while keeping one shared module interface.
Lane1 is conservative against lane0: a lane1 source that reads lane0's accepted
destination is reported not ready, and a lane1 destination that matches lane0's
accepted destination is reported not ready. The WBT does not provide intra-pair
forwarding or WAW resolution.

## Completion Inputs

```text
complete_valid
complete_seq_id
complete_epoch
complete_dst
complete2_valid
complete2_seq_id
complete2_epoch
complete2_dst
complete3_valid
complete3_seq_id
complete3_epoch
complete3_dst
complete4_valid
complete4_seq_id
complete4_epoch
complete4_dst
```

The completion ports release matching reservations. A source register that is
busy but matched by a same-cycle completion is reported ready, allowing the
owning pipe to issue a dependent operation if it can forward the value. The
second port exists because an owning pipe may have independent producers that can
finish in the same cycle, such as scalar ALU writeback and scalar LSU/load
placeholder completion. Architectural register-file writeback and data
forwarding still live in the owning pipe.

## Redirect/Cancel Inputs

```text
redirect_kill_valid
redirect_kill_seq_id
redirect_kill_epoch
cancel_valid
cancel_seq_id
```

Killed instructions release their pending destination reservations. No killed
completion may later write architectural state.

`cancel_valid/cancel_seq_id` is an optional local wrapper hook for a domain that
can reserve a destination and then abort after issue without producing a normal
completion. The first VR-domain implementation should not need this path:
commands waiting on lite-rename capture slots or virtual branch/control
dependencies have not issued yet and therefore have not reserved VR.

## Outputs

```text
src_ready
dst_reserve_ready
dependency_stall
forward_valid
forward_data
```

Forwarding data is not carried by this primitive. The WBT only reports that a
matching same-cycle completion releases a busy source; the owning pipe must
provide the actual data bypass before relying on that ready result.

## Rules

```text
source check:
  if any valid source register has an older pending producer:
    stall or use a valid forwarding path

destination reserve:
  if destination register already has a live reservation:
    stall younger writer unless that exact reservation completes this cycle
  else:
    reserve destination for issue_seq_id

second issue lane:
  if lane1 has RAW or WAW against lane0:
    stall lane1
  else:
    reserve lane1 destination for issue1_seq_id

completion:
  if either complete port writes the register:
    write architectural register or forward data
    release destination reservation
  else if either complete port is a matching no-writeback completion:
    release destination reservation without architectural write

redirect/local cancel:
  release killed reservations
  suppress killed writeback
```

The first RTL primitive does not carry data or perform forwarding; register-file
writeback lives in the owning pipe. Matching completions make sources ready and
allow an existing destination owner to turn over to one newly accepted writer.
A same-cycle issue and completion belonging to the newly accepted destination
is treated as an immediately completed single-cycle operation and does not
leave the busy bit set. If multiple completion ports match live reservations in
the same cycle, each matching entry is released or turned over independently.

## Cross-Domain Use

Instructions that touch more than one architectural domain must interact with
each domain's WBT instance independently:

```text
integer op:
  GPR source/destination checks

floating-point op:
  FPR source/destination checks

fmv.x.* / integer-FP convert:
  source domain check on the producer register file
  destination domain reserve on the target register file

Edge Vector op:
  VR source/destination checks
  scalar GPR/FPR operands arrive through capture slots, not direct WBT reads
```

The WBT primitive is shared, but each domain keeps separate state. GPR, FPR, and
VR dependencies must not share one busy table.

## Same-Cycle Destination Turnover

A destination whose current owning `{seq_id, epoch}` matches any completion
port is reserve-ready in that cycle. If a younger instruction accepts the same
destination, the old completion releases the old owner and the new reservation
remains busy with the younger tag. This is a one-owner turnover, not general
multi-producer WAW renaming.

Sequential update distinguishes three cases:

```text
old owner completes, no new issue:       clear busy
old owner completes, new writer issues:  replace with new owner
new writer completes in its issue cycle: leave busy clear
```

The last case compares completion `{seq_id, epoch}` with the accepted issue so
the existing zero-latency behavior is preserved. A stale completion matching
only an older tag cannot clear the replacement reservation. Lane1 has the same
turnover rule, while lane0/lane1 WAW within one issue pair remains forbidden.

`test/edge_wbt_turnover_tb.v` proves blocked WAW before completion, old-complete
plus new-reserve turnover, stale-completion rejection, zero-latency completion,
and lane1 turnover.
