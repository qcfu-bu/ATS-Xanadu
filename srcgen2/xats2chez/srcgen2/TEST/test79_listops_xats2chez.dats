#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
fun mk(): list(sint) = list_cons(1, list_cons(2, list_cons(3, list_nil())))
fun run0(): sint = list_length<sint>(list_reverse<sint>(mk()))
val () = (sint_print(run0()); strn_print("\n"); the_print_store_log())
