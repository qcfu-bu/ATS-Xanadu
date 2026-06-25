(* ****** ****** *)
(*
M2.6b conformance: a flat tuple PASSED TO and RETURNED FROM a function -- so
the function's Go signature has a tuple-typed PARAMETER and a tuple-typed
RESULT (`func(struct{F0 int; F1 int}) struct{F0 int; F1 int}`), recovered via
[gotype_of_styp]'s [T2Ptrcd] arm (NOT `any`).  [swap] takes `@(a,b)` and
returns `@(b,a)`; the caller projects the swapped tuple.  The param/result
struct type at the call/decl sites is byte-identical to the construction +
projection struct types (all driven from the same translator).  Byte-equal-vs-JS.
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
// take a flat tuple, return a flat tuple with the components swapped.
fun
swap(p: @(sint, sint)): @(sint, sint) =
@(p.1, p.0)
//
// build a tuple, pass it to swap, project the result.
fun
test(n: sint): sint =
let
  val p = @(n, n+1)
  val q = swap(p)
in
  q.0 * 10 + q.1
end
//
val () = sint_print(test(3))   // swap(@(3,4)) = @(4,3) -> 4*10+3 = 43
val () = strn_print("\n")
val () = sint_print(test(10))  // swap(@(10,11)) = @(11,10) -> 11*10+10 = 120
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
