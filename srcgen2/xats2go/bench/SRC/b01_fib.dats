#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
fib(n: sint): sint =
if (n <= 1) then n else fib(n-1) + fib(n-2)
//
val () = strn_print("fib(35)=")
val () = sint_print(fib(35))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
