#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
scan(s: string, i: sint, n: sint, acc: sint): sint =
if (i >= n) then acc else
scan(s, i + 1, n, (if (strn_get$at(s, i) = 'a') then acc + 1 else acc))
//
fun
rep(k: sint, s: string, n: sint, acc: sint): sint =
if (k <= 0) then acc else rep(k - 1, s, n, acc + scan(s, 0, n, 0))
//
val s0 = "abracadabra_alabama_banana_avalanche_saskatchewan"
val () = strn_print("acount=")
val () = sint_print(rep(3000000, s0, strn_length(s0), 0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
