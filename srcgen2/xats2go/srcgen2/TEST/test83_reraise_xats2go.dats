(* ****** ****** *)
(*
EXCEPTIONS (step 2/2) — RE-RAISE: the INNER `try` has a handler for a DIFFERENT
exception type (ErrorExn) than the one raised (ErrmsgExn), so the raised
exception does NOT match the inner handler's tag/name test and falls to the
inner `default: panic(goxrec)` -- propagating to the OUTER `try`, whose
ErrmsgExn handler catches it.  This adversarially exercises (a) the Name-aware
tag test that distinguishes excptcon types that all share ctag -1, and (b) the
`default: panic(goxrec)` re-raise.  GOLDEN-validated.  Expected:
`outer caught: bang\n`.
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
val () =
try
  // INNER try: catches ONLY ErrorExn, but we raise ErrmsgExn -> the inner
  // handler's `case .Tag==-1 && .Name=="ErrorExn"` is FALSE -> default: panic
  // (re-raise) -> escapes to the OUTER try.
  (
  try
    $raise ErrmsgExn("bang")
  with
  ErrorExn() => prints("inner caught ErrorExn (WRONG)\n")
  )
with
ErrmsgExn(m) => prints("outer caught: ", m, "\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
