(* ****** ****** *)
(*
M2.6b ADVERSARIAL: MIXED nesting — a FLAT tuple whose first field is a BOXED
tuple. Emitted Go must be `struct{F0 *struct{F0 int; F1 int}; F1 int}` — the
INNER boxed tuple a POINTER, the OUTER flat tuple a VALUE. Per-level trcdknd.
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
//
fun
f(n: sint): sint =
let
  val inner = #(n, n + 1)      // BOXED tuple
  val outer = @(inner, n + 2)  // FLAT tuple of (boxed-tuple, int)
in (outer.0).0 + (outer.0).1 + outer.1 end
//
val () = sint_print(f(10))    // (10 + 11) + 12 = 33
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
