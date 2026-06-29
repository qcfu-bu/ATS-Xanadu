(* ****** ****** *)
(*
HX-2026-06-29:
This is for loading
ATS3_XANADU/prelude/DATS/CATS/GO

The GO backend's prelude ARM manifest — the typed Go analog of
prelude_JS_dats.hats.  A program targeting Go `#include`s THIS (instead of
prelude_JS_dats.hats) so the prelude templates resolve to the GO arm
(XATS2GO_* primitives) rather than the JS arm.  Selection is PER-PROGRAM and
processed at runtime (the emitter reads the program + its includes), so
switching a program to the GO arm needs NO lib2xatsopt rebuild.

VERTICAL SLICE (in progress): xtop/gint/strn + the scalar floor (bool/char/
gflt) are wired; the remaining modules are added as the slice is proven.  See
srcgen2/xats2go/docs/01-cats-go-prelude.md.
*)
(* ****** ****** *)
//
#staload // XTOP
"prelude/DATS/CATS/GO/xtop000.dats"
//
#staload _ =
"prelude/DATS/CATS/GO/gint000.dats"
//
#staload _ =
"prelude/DATS/CATS/GO/bool000.dats"
//
#staload _ =
"prelude/DATS/CATS/GO/char000.dats"
//
#staload _ =
"prelude/DATS/CATS/GO/gflt000.dats"
//
#staload _ =
"prelude/DATS/CATS/GO/strn000.dats"
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_HATS_prelude_GO_dats.hats] *)
(***********************************************************************)
