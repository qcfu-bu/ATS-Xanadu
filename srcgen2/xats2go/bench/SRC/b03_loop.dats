#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
loop(i: sint, acc: sint): sint =
if (i <= 0) then acc else loop(i - 1, acc + i)
//
val () = strn_print("sum=")
val () = sint_print(loop(1000000000, 0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
