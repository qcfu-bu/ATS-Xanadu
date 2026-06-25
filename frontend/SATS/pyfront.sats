(* ****** ****** *)
(*
** M0a — Python-surface frontend: the typecheck-spine driver (SATS).
**
** This declares the M0a driver surface. There is NO lexer/parser yet (that is
** M1+); M0a HAND-BUILDS an L2 `d2parsed` for a trivial dynamic program
**
**     val x = 1
**     val y = x        // a use-site that must resolve `x` through the env
**
** and drives it through the reused L2->L3 entry `d3parsed_of_trans23`, asserting
** `nerror = 0`. See frontend/docs/PYTHON-FRONTEND-PLAN.md (§2, §5.4, §6) and
** frontend/docs/LOWERING-MAP.md (§4 templates C/A, §5).
**
** Everything here is PURELY ADDITIVE: no file under srcgen2/ or language-server/
** is modified. We only CALL the compiler-as-a-library.
*)
(* ****** ****** *)
//
// Pull in the stock compiler front-end header so the abstract handle types this
// SATS mentions in signatures (d3parsed from dynexp3, sint from xbasics) are in
// scope. This is the SAME header the resident LSP SATS includes.
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
//
(* ****** ****** *)
//
// Build the hand-crafted L2 program `val x = 1 ; val y = x` and run it through
// trans23. Returns the resulting type-checked d3parsed. RE-ENTRANT: it makes a
// FRESH tr12env every call and never mutates the global prelude env (plan §6.2).
//
fun
pyfront_m0a_check((*void*)): d3parsed
//
// One self-contained "run": build + check + report (f3perr0_d3parsed to stderr)
// + print success markers (nerror) to stdout. Returns the nerror count so the
// caller can assert across the re-entrancy loop.
//
fun
pyfront_m0a_run(iter: sint): sint
//
(* ****** ****** *)
//
(*
end of [frontend/SATS/pyfront.sats]
*)
