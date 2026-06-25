(* ****** ****** *)
(*
test94: strn_foritm with a NON-LINEAR foritm$work (returns a count via a
captured var ref, no linear FILR capture) -> frontend resolves the body
(dclq=Y), so it is differentially testable. Exercises selective monomorphized
inlining of the foritm/$work family.
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
//
fun
count_lower(s: string): sint =
let
var n: sint = 0
#impltmp
foritm$work<char>(c0) =
if (c0 >= 'a') then (if c0 <= 'z' then (n := n + 1) else ()) else ()
val () = strn_foritm(s)
in
n
end
//
val () = sint_print(count_lower("Hello World"))   // 8
val () = strn_print(" ")
val () = sint_print(count_lower("ABC"))            // 0
val () = strn_print(" ")
val () = sint_print(count_lower("abcXYZ123"))      // 3
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
