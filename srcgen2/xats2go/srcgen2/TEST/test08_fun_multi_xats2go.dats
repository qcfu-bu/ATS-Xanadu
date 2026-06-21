(* ****** ****** *)
(*
M2.2 conformance: a function CALLED MULTIPLE TIMES, and a value-returning
function whose result FEEDS ANOTHER EXPRESSION (arithmetic).  [sqr] squares
a sint; we call it three times and combine the results with +, exercising:
  - one decl, multiple I1INSdapp call sites to the SAME function (name
    mangling must agree at every site)
  - a function result used as an operand of a native Go op (the result of
    dbl/sqr feeds `+`), i.e. value-returning function in arithmetic.
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
sqr(x: sint): sint = x * x
//
// sqr(2)+sqr(3)+sqr(4) = 4 + 9 + 16 = 29
val () = sint_print(sqr(2) + sqr(3) + sqr(4))
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test08_fun_multi.dats] *)
(***********************************************************************)
