(* ****** ****** *)
(*
EXCEPTIONS (step 2/2) — the NORMAL (non-raising) path: a `try` whose body does
NOT `$raise` runs to completion and yields its value; the `with` handler is
NEVER entered (the `defer`/`recover` sees `recover() == nil`).  GOLDEN-validated
(the JS oracle cannot compile try/raise).  Expected: `normal: 42\n`.
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
safe_div(a: sint, b: sint): sint =
  try
    (if b = 0 then $raise ErrmsgExn("divide by zero") else a / b)
  with
  ErrmsgExn(_) => 0
//
val r = safe_div(84, 2)   // b<>0 -> NORMAL path -> 84/2 = 42 (handler skipped)
//
val () = prints("normal: ", r, "\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
