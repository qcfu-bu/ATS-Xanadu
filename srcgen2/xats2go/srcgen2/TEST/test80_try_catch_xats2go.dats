(* ****** ****** *)
(*
EXCEPTIONS (step 2/2) — the headline CATCH: a `try` whose body `$raise`s
ErrmsgExn("boom") is caught by a `with ErrmsgExn(m) => ...` handler.  The
emitter must lower the raise to a Go `panic(...)` and the try to an IIFE with
`defer func(){ if r := recover(); ... }()` whose handler is a datacon switch
on the caught `*xatsgo.XatsCon`.  GOLDEN-validated (the JS oracle cannot
compile try/raise -- see BUILD-NOTES "EXCEPTIONS").  Expected: `caught: boom\n`.
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
  $raise ErrmsgExn("boom")
with
ErrmsgExn(m) => prints("caught: ", m, "\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
