(* ****** ****** *)
(*
ADVERSARIAL M2.5: MULTIPLE INDEPENDENT closures from the SAME generator,
each capturing a DIFFERENT value.  If the divergence accidentally shared a
single env / captured the last value, both would print the same.
  adder(d) = lam x => x + d
  add5  = adder(5)    ; add5(100)  = 105
  add10 = adder(10)   ; add10(100) = 110
Then ALSO mix them: add5(add10(0)) = add5(10) = 15.
HAND-COMPUTED EXPECTED (one line):  a=105 b=110 mix=15
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
adder(d: sint): sint -> sint = lam(x: sint): sint => x + d
//
val add5  = adder(5)
val add10 = adder(10)
//
val () = strn_print("a=")
val () = sint_print(add5(100))           // 105
val () = strn_print(" b=")
val () = sint_print(add10(100))          // 110
val () = strn_print(" mix=")
val () = sint_print(add5(add10(0)))      // add5(10) = 15
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test32_multi_clos_xats2go.dats] *)
(***********************************************************************)
