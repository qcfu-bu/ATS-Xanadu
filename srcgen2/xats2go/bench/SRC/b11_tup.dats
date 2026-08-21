#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
imod(a: sint, b: sint): sint = a - (a / b) * b
//
fun
mk(i: sint): (sint, sint) = @(i, i + i + 1)
//
fun
use(p: (sint, sint)): sint = p.0 + p.0 - p.1
//
fun
loop(i: sint, acc: sint): sint =
if (i <= 0) then acc else loop(i - 1, acc + use(mk(i)))
//
val () = strn_print("tup=")
val () = sint_print(loop(5000000, 0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
