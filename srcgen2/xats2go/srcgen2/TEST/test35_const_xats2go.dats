(* ADVERSARIAL minimal repro: const-function closure (body = bare capture). *)
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
fun konst(a: sint): sint -> sint = lam(u: sint): sint => a
val k9 = konst(9)
val () = strn_print("k=")
val () = sint_print(k9(0))   // 9
val () = strn_print("\n")
val () = the_print_store_log()
