#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
apply(f: sint -> sint, x: sint): sint = f(x)
//
fun
loop(i: sint, acc: sint, f: sint -> sint): sint =
if (i <= 0) then acc else loop(i - 1, apply(f, acc), f)
//
val () = strn_print("hof=")
val () = sint_print(loop(200000000, 0, lam(x: sint): sint => x + 3))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
