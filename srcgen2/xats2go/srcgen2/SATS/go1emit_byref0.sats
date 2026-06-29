(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(* ****** ****** *)
//
(*
go1emit_byref0 — self-hosting GAP A1 — the by-REFERENCE-parameter STAMP SET.
//
WHAT IT IS.  A PROCESS-GLOBAL mutable set recording the [stamp]s of the
function/closure PARAMETER temps ([i1tnm]) that are CALL-BY-REFERENCE
(declared `&T` in the source).  ATS `&T` params are call-by-reference: a
mutation inside the callee must propagate to the caller's variable.
//
THE Go MAPPING (Go has real pointers -- no simulation, unlike the JS
backend's `XATSVAR1` box + `XATSADDR`/`XATS000_assgn` path-encoding):
  - a `&T` parameter            -> a Go `*T` (pointer to the caller's cell)
  - the call site's `&cell` arg  -> `&<cell>` (address of the addressable var)
  - a READ of the param          -> `*p`   (dereference)
  - a WRITE to the param         -> `*p = v` (assign through the pointer)
  - passing the param ONWARD     -> `p`    (it is already the pointer)
The byref STAMP set is the discriminator the read/write/call emitters use to
choose the deref-vs-pointer form: a param stamp in this set is a `*T` pointer.
//
HOW IT IS POPULATED.  When a function/closure's parameters are emitted, the
emitter walks the parameter binds in parallel with the function's static
arg types; an arg whose static type is `T2Parg1(-1, _)` (knd = -1 = by-ref;
see statyp2.sats `~/!/& = 0/1/-1`) marks that param's i1tnm stamp by-ref
([byref_register_params], in go1emit_styp0.dats).  The set is read at the
emit sites in go1emit_dynexp.dats.
//
ORDERING / SOUNDNESS.  A function's params are registered at the START of
its body emission, BEFORE any read/write/call in that body is emitted (the
emitter is a single in-order traversal), so every query inside a body sees
its own params already registered.  Stamps are globally unique per i1tnm, so
there is no cross-function aliasing of a byref stamp.  [byref_reset] is
provided for defensiveness (single-file-per-run today, like the tytab).
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#staload
"./../../../SATS/xstamp0.sats"//for[stamp]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
[byref_add(stmp)]: mark the param temp with stamp [stmp] as by-reference
(a Go `*T` pointer).  Idempotent (a duplicate add is harmless -- the set
membership test is all the reader needs).
*)
fun
byref_add
(stmp: stamp): void
//
(*
[byref_has(stmp)]: is the temp with stamp [stmp] a by-reference pointer
param?  The read/write/call emitters use this to deref (`*p`) reads/writes
and pass the bare pointer (`p`) at call sites.
*)
fun
byref_has
(stmp: stamp): bool
//
(*
[byref_reset]: clear the set.  Not needed for the single-file-per-run
driver, but provided so a future multi-file run cannot read stale stamps.
*)
fun
byref_reset((*void*)): void
//
(* ****** ****** *)
//
(*
GO-ARM MODE (CATS/GO prelude pivot).  A process-global boolean, default
FALSE.  When the driver is invoked for a program that targets the CATS/GO
prelude arm (it passes `--go-arm`), it calls [go_arm_set] BEFORE emission; the
emitter then EMITS prelude template bodies (so they reach the typed
`XATS2GO_*` leaves of the linked .cats floor) instead of shortcutting them to
`xatsgo.Xats_*`.  Default-false means a JS-arm program (the existing suite) is
byte-identical -- the gate is never taken.
*)
fun
go_arm_set((*void*)): void
fun
go_arm_getq((*void*)): bool
//
(* ****** ****** *)
//
(*
NULLARY-INSTANCE TEMP SET (go-arm higher-order path).  A value-like (nullary,
no-param) template instance is emitted as a Go THUNK `func() T {..}` bound to
a temp.  When that temp is later APPLIED WITH ARGS (a g_print/prints hook
returns a function), the call must be `tmp()(args)` -- invoke the thunk to get
the function, THEN apply -- not `tmp(args)` (an arity mismatch).  This records
the stamps of such temps (populated at the I1INStimp dispatch in go-arm mode);
the I1INSdapp emitter inserts the `()` for a non-empty arg list.  A 0-arg
application stays `tmp()` (the generic form already invokes the thunk).
*)
fun
nullary_inst_add(stmp: stamp, paramty: strn): void
fun
nullary_inst_has(stmp: stamp): bool
//
(*
[nullary_inst_paramty(stmp)]: the Go param type of the value-like instance's
RESULT function (its first param), recorded at registration -- used to ASSERT
an `any`-typed arg at the hook application (`tmp()(arg.(T))`).  Empty string
when unknown / the result is not a function.
*)
fun
nullary_inst_paramty(stmp: stamp): strn
//
(* ****** ****** *)
//
(*
INSTANCE-FUNC EMITTED-RETURN-TYPE SIDE-TABLE (go-arm RESULT boundary).  A
template instance is emitted as a Go func literal bound to a temp; its emitted
return type is the body-derived [gotype_of_lam_ret], which for a forwarding
instance over an `any`-returning leaf (e.g. XATS2GO_a0rf_get) is "any".  We
record (instance-temp stamp -> emitted return type) at the I1INStimp emission;
when that temp is later APPLIED and the application's result temp has a CONCRETE
gotyp, the call must be asserted (`tmp(args).(T)`) -- the recorded "any" is the
signal that the emitted func really returns `any` (the temp's own recorded gotyp
carries the CONCRETE type, so it cannot be used to detect the mismatch).
*)
fun
inst_retty_add(stmp: stamp, retty: strn): void
//
(*
[inst_retty_get(stmp)]: the recorded emitted return type of the instance-func
temp [stmp], or "" if none was recorded (not an instance func / not go-arm).
*)
fun
inst_retty_get(stmp: stamp): strn
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_SATS_go1emit_byref0.sats] *)
(***********************************************************************)
