# edge_cmpu_bf16_relation

This combinational leaf classifies one raw-BF16 operand pair into mutually
exclusive ordered less/equal/greater relations plus unordered.  Positive and
negative zero compare equal; any NaN makes the relation unordered.  The leaf
does not select operands or implement a software-visible mode.

`edge_cmpu` instantiates one shared relation leaf for all elementwise modes and
the reduction maximum update.  A second identical leaf is enabled by operand
isolation only for the simultaneous reduction minimum update.  This is the
minimum hardware required to retain one accepted reduction element per cycle
while computing min and max in one traversal.
