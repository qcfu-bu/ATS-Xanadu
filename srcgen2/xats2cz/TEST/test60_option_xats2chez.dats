(* ****** ****** *)
(*
M2.7 conformance: a simple monomorphic OPTION datatype.  Build iSome(x)/iNone,
then pattern-match to extract the payload or default.  Exercises datacon
construction (&xatsgo.XatsCon{Tag,Args}) + a datacon `case` with a tag test
(v.Tag == ctag) + a typed projection (the iSome field is `int`, recovered from
the constructor's static type -> v.Args[0].(int)).  Byte-equal-vs-JS.
//
A MONOMORPHIC datatype (no type parameter) is chosen so the payload field's
concrete Go type is recoverable from the d2con itself (a POLYMORPHIC payload
field of type `a` is stored uniformly as `any`, faithful to ATS's own boxed
representation -- the M3 framing -- and is exercised separately).
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
intopt =
| iNone of ()
| iSome of (sint)
//
// extract the payload of an intopt, defaulting to d when None.
fun
unopt(o: intopt, d: sint): sint =
(
case+ o of
| iNone() => d
| iSome(x) => x
)
//
val s0 = iSome(42)
val n0 = iNone()
//
val () = sint_print(unopt(s0, 0))   // 42
val () = strn_print("\n")
val () = sint_print(unopt(n0, 99))  // 99
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
