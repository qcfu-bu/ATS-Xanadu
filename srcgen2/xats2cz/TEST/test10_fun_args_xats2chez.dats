(* ****** ****** *)
(*
M2.2 conformance: MULTIPLE ARGUMENTS (and mixed scalar types).  [axpy]
takes three sint args and computes a*x+y; [fmix] takes two dflt args.
Exercises:
  - a multi-param Go signature (each i1bnd -> a typed Go param)
  - args of more than one scalar type across functions (int + float64)
  - the function result feeding a print.
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
axpy(a: sint, x: sint, y: sint): sint = a * x + y
//
fun
favg(p: dflt, q: dflt): dflt = (p + q) / 2.0
//
val () = sint_print(axpy(3, 4, 5))    // 3*4+5 = 17
val () = strn_print(" ")
val () = dflt_print(favg(1.0, 4.0))   // 2.5
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test10_fun_args.dats] *)
(***********************************************************************)
