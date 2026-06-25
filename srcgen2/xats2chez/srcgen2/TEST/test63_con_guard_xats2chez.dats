(* ****** ****** *)
(*
M2.7 conformance: a multi-constructor datatype matched with a GUARD and a
WILDCARD/default clause.  `shape` has three constructors; classify maps each to
a number, but the `rect` case has a GUARD (square-vs-oblong) and the final clause
is a wildcard catch-all.  Exercises: datacon tag tests folded with a guard
(`case <tag-test> && <guard>:`), a wildcard clause, and typed int-field
projections feeding the guard comparison.  Byte-equal-vs-JS.
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
datatype
shape =
| circle of (sint)          // radius
| rect of (sint, sint)      // width, height
| dot of ()
//
// classify: circle -> 1, square (rect w==h) -> 2, other rect -> 3, dot -> 0
// (the wildcard handles dot; the guard distinguishes square from oblong rect).
fun
classify(s: shape): sint =
(
case+ s of
| circle(_) => 1
| rect(w, h) when w = h => 2
| rect(_, _) => 3
| _ => 0
)
//
val c0 = circle(5)
val sq = rect(4, 4)
val ob = rect(4, 7)
val d0 = dot()
//
val () = sint_print(classify(c0))   // 1
val () = sint_print(classify(sq))   // 2 (guard: 4==4)
val () = sint_print(classify(ob))   // 3 (guard fails -> next rect clause)
val () = sint_print(classify(d0))   // 0 (wildcard)
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
