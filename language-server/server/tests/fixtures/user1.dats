(* user1.dats — clean itself; staloads the broken dep1.sats *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
//
#staload "./dep1.sats"
//
#implfun dep_id(x0) = x0
//
fun
user_f(x0: sint): sint = dep_id(x0) + 1
//
val () = sint_print(user_f(1))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
//
