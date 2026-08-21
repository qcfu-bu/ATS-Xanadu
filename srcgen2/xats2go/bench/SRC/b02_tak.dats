#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
tak(x: sint, y: sint, z: sint): sint =
if (y < x)
then tak(tak(x-1, y, z), tak(y-1, z, x), tak(z-1, x, y))
else z
//
val () = strn_print("tak(27,18,9)=")
val () = sint_print(tak(27, 18, 9))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
