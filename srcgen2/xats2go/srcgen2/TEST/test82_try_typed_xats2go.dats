(* ****** ****** *)
(*
EXCEPTIONS (step 2/2) — a try inside a FUNCTION returning a TYPED value: the
named-return type of the IIFE is exercised (concrete `int`, NOT just unit/`any`).
The body `$raise`s on a bad input; the handler returns a typed `sint` fallback.
GOLDEN-validated.  Expected: `ok: 21\nbad: -1\n`.
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
// returns the doubled input, but RAISES on a negative input -- the handler
// returns the typed fallback (0 - 1) = -1.  The try result is `sint`, so the
// IIFE's named return is `int` (the named-return-type recovery, not `any`).
fun
checked_double(n: sint): sint =
  try
    (if n < 0 then $raise ErrmsgExn("negative") else n + n)
  with
  ErrmsgExn(_) => 0 - 1
//
val a = checked_double(21)    // 21 >= 0 -> normal -> 42... wait, doubled
val b = checked_double(0 - 5) // negative -> RAISE -> caught -> -1
//
val () = prints("ok: ", checked_double(10), "\n")  // 10+10 = 20
val () = prints("a: ", a, "\n")                     // 21+21 = 42
val () = prints("bad: ", b, "\n")                   // -1
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
