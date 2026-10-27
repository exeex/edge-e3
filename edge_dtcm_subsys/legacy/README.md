# Historical wide-H4 prototypes

`rtl/edge_dtcm_h4_wide.v` and `rtl/edge_dtcm_h4_wide_bank_bridge.v` preserve
the early wide-SRAM backend and its bank bridge for directed tests and
equivalence comparisons. Product RTL uses
`../rtl/edge_dtcm_h4_bank.v` through the H4 wrapper.

Production filelists exclude these prototypes. Comparison tests list them
explicitly; their contracts remain at matching paths in the private test package.
