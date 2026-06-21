(* ****** ****** *)
(*
** M7-import GATING SPIKE — a small STOCK ATS `.sats` "user module" to be loaded by
** the import spike driver via the SAME pervasive loader the pyrt prelude uses
** (filpath_pvsload -> f0_pvsload). It exports one typed `fun` constant. Because it
** is declared in a `.sats`, `lib_double` becomes a TYPED d2cst CONSTANT (-> D2ITMcst),
** which resolves + type-checks at a call site exactly like a prelude function
** (M16 finding). Plain stock ATS, stadyn=0 (static interface).
*)
(* ****** ****** *)
//
#include
"./../../../srcgen2/prelude/HATS/prelude_sats.hats"
//
(* ****** ****** *)
//
// the single export the spike will REFERENCE from the importing program.
//
fun
lib_double(x: int): int
//
(* ****** ****** *)
(*
** end of [frontend/TEST/m7imp/lib.sats]
*)
