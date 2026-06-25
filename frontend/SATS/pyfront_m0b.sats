(* ****** ****** *)
(*
** M0b — Python-surface frontend: the CODEGEN-spine driver (SATS).
**
** M0a proved the typecheck spine: a hand-built L2 `d2parsed` for
**
**     val x = 1
**     val y = x
**
** drives cleanly through `d3parsed_of_trans23` with nerror = 0, yielding a
** type-checked `d3parsed` (see frontend/SATS/pyfront.sats:`pyfront_m0a_check`).
**
** M0b closes the "compile to JS" tracer bullet: it takes THAT SAME `d3parsed`
** (obtained by REUSING `pyfront_m0a_check()`), drives it through the in-memory
** `xats2js` backend pass sequence (see pyfront_m0b.dats for the verified
** sequence + file:line), and emits the USER PROGRAM's JavaScript to the FILR.
**
** This SATS only declares the driver entry. The backend SATS staloads live in
** the DATS (a .sats's nested #staloads are NOT re-exported to a DATS that
** staloads it, so the backend names must be staloaded directly where used).
**
** PURELY ADDITIVE: nothing under srcgen2/ or language-server/ is modified, and
** M0a's pyfront.sats / pyfront.dats / build-m0a.sh are untouched.
*)
(* ****** ****** *)
//
// Stock compiler front-end header so this SATS's signature types (FILR from
// libcats via the prelude header chain, sint from xbasics) are in scope. Same
// header M0a's pyfront.sats includes.
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
//
(* ****** ****** *)
//
// Drive `pyfront_m0a_check()`'s d3parsed through the xats2js backend and emit
// the user program's JS to `filr`. Returns the nerror count carried on the L3
// (0 = the typecheck spine that fed codegen was clean).
//
fun
pyfront_m0b_emit(filr: FILR): sint
//
(* ****** ****** *)
//
(*
end of [frontend/SATS/pyfront_m0b.sats]
*)
