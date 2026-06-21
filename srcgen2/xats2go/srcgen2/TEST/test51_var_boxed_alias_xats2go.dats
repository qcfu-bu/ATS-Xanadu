(* ****** ****** *)
(*
M2.6c conformance: BOXED tuple mutation through an ALIAS (the sharing test).
//
`var p = #(1,2)` is a Go `*struct` (heap pointer); `val q = p` ALIASES the same
boxed tuple (a pointer copy, NOT a deep copy).  Mutating `p.0 := 10` is then
VISIBLE through `q` (`q.0 + q.1` reads `10 + 2 = 12`) -- the boxed=SHARED
semantics.  This is the case READ-only M2.6b could not distinguish: the Go
pointer-var + alias reproduce the JS backend's reference-box sharing exactly
(byte-equal-vs-JS), validating that the boxed layout really is shared mutation.
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
// boxed tuple var + alias: mutate via p, observe via q (shared).
fun
ba(n: sint): sint =
let
  var p = #(n, n+1)
  val q = p            // alias the SAME boxed tuple
in
  p.0 := 100;          // mutate via p
  q.0 + q.1            // observe via q -> 100 + (n+1)
end
//
val () = sint_print(ba(3))    // 100 + 4 = 104
val () = strn_print("\n")
val () = sint_print(ba(40))   // 100 + 41 = 141
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
