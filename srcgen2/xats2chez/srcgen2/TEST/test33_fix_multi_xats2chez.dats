(* ****** ****** *)
(*
ADVERSARIAL M2.5: I1INSfix0 recursion CORRECTNESS at MULTIPLE inputs (not
just one).  A local recursive closure `fix f(x) => if x>0 then x+f(x-1)
else 0` computes the triangular number T(x) = x*(x+1)/2.  Applied at
several inputs to confirm it actually recurses, terminates, and is right
EVERYWHERE (a base-case-only or off-by-one bug would surface at one input).
  T(0)=0  T(1)=1  T(5)=15  T(10)=55
HAND-COMPUTED EXPECTED:  tri 0 1 15 55
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
tri(n: sint): sint =
(fix f(x: sint): sint =>
   if x > 0 then x + f(x-1) else 0)(n)
//
val () = strn_print("tri ")
val () = sint_print(tri(0))    // 0
val () = strn_print(" ")
val () = sint_print(tri(1))    // 1
val () = strn_print(" ")
val () = sint_print(tri(5))    // 15
val () = strn_print(" ")
val () = sint_print(tri(10))   // 55
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test33_fix_multi_xats2chez.dats] *)
(***********************************************************************)
