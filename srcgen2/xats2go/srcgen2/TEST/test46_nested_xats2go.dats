(* ****** ****** *)
(*
M2.6b conformance: a NESTED tuple/record -- a flat tuple whose SECOND field is
itself a flat tuple `@(a, @(b, c))`, projected through two levels
(`p.0 + (p.1).0 + (p.1).1`).  The nested field's Go type is itself a
`struct{...}` (the recursion in [goty_of_i0t_fields]/[gorender_trcd_body]), so
the projection `p.1` yields a value struct whose `.F0`/`.F1` resolve.
Byte-equal-vs-JS.
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
// nested flat tuple: @(n, @(n+1, n+2)) ; project all three leaves.
fun
nt(n: sint): sint =
let
  val p = @(n, @(n+1, n+2))
  val q = p.1
in
  p.0 + q.0 + q.1
end
//
val () = sint_print(nt(3))   // 3 + 4 + 5 = 12
val () = strn_print("\n")
val () = sint_print(nt(10))  // 10 + 11 + 12 = 33
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
