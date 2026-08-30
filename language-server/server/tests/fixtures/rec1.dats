(* rec1.dats — tuple projection fixture for member completion *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
//
val pair1 = @(42, "answer")
val first1 = pair1.0
//
val () = sint_print(first1)
val () = strn_print("\n")
val () = the_print_store_log((*void*))
//
