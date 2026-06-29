(* ****** ****** *)
(*
HX-2026-06-29:
This is for loading
ATS3_XANADU/prelude/DATS/CATS/GO

The GO backend's primitive FFI floor — the typed Go analog of
prelude_JS_cats.hats.  Each [#extcode file] splices a typed `.cats` of
XATS2GO_* primitives into the emitted Go.  Everything ELSE in the prelude is
shared ATS, COMPILED to Go by xats2go (NOT mirrored here).

VERTICAL SLICE (in progress): only gint000 is wired so far; the remaining 13
modules (xtop/gbas/gdbg/bool/char/gflt/strn/list/optn/strm/strx/axrf/axsz)
are added once the slice is proven end-to-end through the oracle.  See
srcgen2/xats2go/docs/01-cats-go-prelude.md.
*)
(* ****** ****** *)
//
#extcode
file"prelude/DATS/CATS/GO/gint000.cats"
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_HATS_prelude_GO_cats.hats] *)
(***********************************************************************)
