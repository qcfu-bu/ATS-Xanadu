(* ****** ****** *)
(*
M2.6c conformance: a SEQUENCE of mutations + reads on a var tuple.
//
Each `:=` reads the CURRENT (already-mutated) field values, so the chain
exercises read-after-write through the same addressable var repeatedly:
  p = @(1,2)
  p.0 := p.0 + p.1   ->  p = (3, 2)
  p.1 := p.0 * 10    ->  p = (3, 30)
  p.0 := p.0 + p.1   ->  p = (33, 30)
  result p.0 + p.1   ->  63
Byte-equal-vs-JS (the JS reference box gives the SAME read-after-write chain).
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
sq(a: sint, b: sint): sint =
let
  var p = @(a, b)
in
  p.0 := p.0 + p.1;
  p.1 := p.0 * 10;
  p.0 := p.0 + p.1;
  p.0 + p.1
end
//
val () = sint_print(sq(1, 2))    // (3,2)->(3,30)->(33,30) -> 63
val () = strn_print("\n")
val () = sint_print(sq(2, 3))    // (5,3)->(5,50)->(55,50) -> 105
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
