# edge_predecode_issue_window.v

## Purpose

`edge_predecode_issue_window` is the first standalone queue primitive for the
tokenized frontend redesign described in `edge_token_issue_window.md`.

It stores normalized predecode entries in program order and exposes the oldest
two entries to an issue selector. The selector decides whether to consume zero,
one, or two entries in the current cycle.

## Interface

The enqueue side accepts up to four already-normalized entries:

```text
enqueue0_valid
enqueue1_valid
enqueue2_valid
enqueue3_valid
enqueue*_kind
enqueue*_class
enqueue*_pc
enqueue*_inst
enqueue*_seq_id
enqueue*_epoch
enqueue_ready
flush_valid
```

Entries must be contiguous from slot 0. For example, `enqueue2_valid` should not
be asserted when `enqueue1_valid` is deasserted.

The issue side exposes:

```text
head0_valid
head0_*
head1_valid
head1_*
pop_count       // 0, 1, or 2
```

`head0` is always the oldest entry. `head1` is the next entry when at least two
entries are present. The issue selector must only request `pop_count=2` when it
has consumed both `head0` and `head1`.

## Queue Semantics

The queue permits same-cycle pop and enqueue. `enqueue_ready` is computed from
free space after the requested pop count, so a full queue can accept new entries
in the same cycle that old entries retire from the head.

`flush_valid` clears the whole window. The first predecoder integration uses
this for redirect cleanup; selective per-entry kill is still a later extension.

This supports the target consume table:

```text
S S S S  enqueue four entries
S S V    pop two scalars, leave vector as head
S V S    pop one scalar, leave vector as head
V S S    pop one vector, expose two scalars as head/head1
V V      pop one vector, expose next vector
```

The block does not classify instructions or decide lane legality. It only
preserves order and exposes head/head1 state.

## Current Non-Goals

- No redirect selective kill inside the queue. Redirect cleanup flushes the
  whole window.
- No scalar/vector bypass across the head entry.
- No dependency checking.
- No lane1 policy. `load+load` / `store+store` pairing remains the selector's
  job.

## Focused Test

`edge_predecode_issue_window_tb.v` proves four-wide enqueue, one/two-wide pop,
same-cycle pop+enqueue, and pattern exposure for `S S V`, `S V S`, `V S S`,
and `V V` style ordering.
