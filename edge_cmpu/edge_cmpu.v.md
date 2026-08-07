# edge_cmpu

`edge_cmpu` is the standalone bit-true compute core for the Edge compare unit.
It has no DTCM or instruction dependencies.  `tools/cmpu/cmpu_asic_model.py`
is its executable reference model.

## Modes

```text
0 REDUCE_MINMAX: one traversal publishes max, argmax, min, and argmin
1 MIN:           numeric-over-NaN elementwise minimum
2 MAX:           numeric-over-NaN elementwise maximum
3 SELECT:        mask != 0 ? rhs : lhs
4 CMP_GT:        lhs >  rhs
5 CMP_GE:        lhs >= rhs
6 CMP_EQ:        lhs == rhs
7 CMP_LE:        lhs <= rhs
8 CMP_NE:        lhs != rhs
```

Inputs and numeric outputs are raw BF16 bits.  Compare outputs use byte values
zero and one in `out_value[7:0]`, with `out_is_mask` asserted.

## Job And Stream Handshakes

`start_valid && start_ready` snapshots `start_mode` and opens one job.  Input
elements are accepted on `in_valid && in_ready`; the source supplies the linear
element index and marks the final element with `in_last`.

Vector results have fixed one-cycle latency from each accepted input and
preserve `out_last`.  There is intentionally no output ready signal: the shared
accelerator IO reserves output-FIFO capacity before dispatch. Reduction results use an independent
`result_valid/result_ready` interface and publish all four result fields
atomically.  A result remains stable while backpressured.

`start_ready` remains low until the active job ends or a reduction result has
been consumed. Empty reduction jobs are rejected by the future unit/IO layer;
the standalone core expects at least one element after a reduction start.

## BF16 Rules

- Ordered comparisons with a NaN are false; `NE` with a NaN is true.
- Positive and negative zero compare equal.
- Elementwise MIN/MAX choose the numeric operand over NaN; two NaNs retain lhs.
- Elementwise ties retain lhs, including signed-zero ties.
- Reduction skips NaNs when at least one numeric value exists.
- An all-NaN reduction returns the first NaN and its index for both extrema.
- Equal reduction values retain the first/lower stream index because extrema
  update only on strict greater-than or less-than.

## State And Reset

The core contains one shared relation leaf for elementwise modes/reduction max,
a second operand-isolated leaf for simultaneous reduction min, the fixed
output register, one completed result packet, and running extrema. Active-low `cpurst_b` clears all valid
and active state.  There is no redirect/flush input in this standalone slice.

## Focused Test

`test/edge_cmpu_tb.v` consumes Python-generated BF16 comparison and reduction
vectors.  It checks every visible mode, NaNs, infinities, signed zero, stable
ties, one-element jobs, all-NaN reduction, consecutive fixed-latency throughput,
and result backpressure.
