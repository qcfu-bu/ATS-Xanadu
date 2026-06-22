(* ****** ****** *)
(*
test90 — I1Vtop coverage.
//
A wildcard `_` in VALUE position (isTOP = WCARD_symbl) lowers to I1Vtop(sym):
the "topmost"/omitted value the type checker fills.  The Go emitter renders it
as `xatsgo.XATSTOP0()` (the JS backend's `XATSTOP0` = undefined; the Go analog
returns nil/unit).  `_` is a placeholder whose value is NEVER demanded, so the
binding `val _unused: sint = _` is sound iff the value is not read -- here it
is bound but unused, and the program's OUTPUT is the fixed string, so the run is
well-defined and BYTE-EQUAL to the JS backend (both emit a top/undefined the
output never inspects).
//
This remains a focused surface-reachable `I1Vtop` rung.  Lazy forcing now has
its own coverage in test88; fold/free/dp2tr/p2rj coverage still belongs to
separate focused rungs as the frontend and emitter grow.
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
//
val _unused: sint = _
//
val () =
(
strn_print("top ok\n"); the_print_store_log())
//
(* ****** ****** *)
(* end of [test90_top_xats2go.dats] *)
