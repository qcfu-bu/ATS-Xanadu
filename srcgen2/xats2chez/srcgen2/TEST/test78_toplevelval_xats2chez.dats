(* top-level named val, used by later top-level code *)
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
val theAnswer: sint = 42
val doubled: sint = theAnswer + theAnswer
val () = (sint_print(theAnswer); strn_print(" "); sint_print(doubled); strn_print("\n"); the_print_store_log())
