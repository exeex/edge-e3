# edge_fpu_cvt

## Purpose

`edge_fpu_cvt` owns scalar floating-point conversion behind a one-cycle
issue/complete boundary. The owning scalar pipe remains responsible for GPR and
FPR scoreboards, writeback, `fflags` accumulation, producer publication, and
retire.

## Physical FPR rule

D/S/H floating formats are aliases of one physical FP32 FPR value. Therefore
`FCVT.D.S`, `FCVT.S.D`, `FCVT.H.S`, `FCVT.S.H`, `FCVT.D.H`, and `FCVT.H.D`
complete as an FPR32 move: the 32-bit payload is unchanged and no rounding or
exception flag is produced.

Conversions between FPR32 and integer are numeric conversions. Integer type
selects W, WU, L, or LU. All five static RISC-V rounding modes are implemented:
RNE, RTZ, RDN, RUP, and RMM. The current scalar pipe accepts only immediate
`rm=000..100`; reserved `101/110` and dynamic `111` are illegal because this
slice intentionally has no `frm/FCSR` state. Invalid numeric conversions saturate to the architectural
integer result and raise NV; discarded finite fractional bits raise NX.

On RV64, both FCVT.W and FCVT.WU results are sign-extended from bit 31.

## Validation

`edge_fpu_cvt_tb` checks FPR-format identity, signed/unsigned saturation,
RV64 W-result sign extension, exact and inexact conversions, and rounding-mode
differences in both directions. The scalar-pipe FPU test also checks format
identity and integer conversions through the integrated GPR/FPR scoreboards,
writeback, producer, and retire paths. Its mixed random SoftFloat comparison
also covers exact conversions under every static mode; exact RNE/RMM inputs
must not increment merely because the internal remainder and half threshold
are both zero. The mixed scalar SoftFloat flow exercises W/WU/L/LU in both
directions, while the leaf test pins signed `-2^63`, signed/unsigned overflow,
and `UINT64_MAX` rounding under RNE and RTZ.
