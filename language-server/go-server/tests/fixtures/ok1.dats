(* a clean fixture: zero diagnostics expected *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
//
fun
double(x0: sint): sint = x0 + x0
//
val () = sint_print(double(21))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
//
