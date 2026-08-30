(* ****** ****** *)
(*
lsp_diag.sats — shape the checker's stderr report into LSP diagnostics.

The check-only driver (srcgen2/xats2go/selfhost-build/src/xats2go-tcheck)
prints one line per error:

  PREAD00-ERROR:LCSRCsome1(<path>)@(<n>(line=<L>,offs=<C>)--<n>(line=<L>,offs=<C>)):<node>
  F3PERR0-ERROR:...same shape...
  F2PERR0-ERROR:...same shape (dependency reports, level 2)...

Printed L/C are 1-BASED; the columns are UTF-16 CODE UNITS (verified:
the selfhost compiler's string model is UTF-16, e.g. an astral char
advances offs by 2) — exactly LSP's default position encoding, so the
mapping is (L-1, C-1) with no re-encoding.  A line may embed several
nested locations; the INNERMOST (smallest-width) span in the TARGET
file is the precise one.  Lines repeating a span already seen (the
PREAD00-vs-F3PERR0 redundancy) are deduped keep-first.
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#staload "./lsp_json.sats"
(* ****** ****** *)
//
(*
the LSP Diagnostic array (a JVarr) for the target file.  Errors whose
innermost span lies in ANOTHER file are summarized: one diagnostic per
foreign file (count + first error), positioned at the file's basename
occurrence in doctext (the staload line).  Only files under wsroot
(the workspace root) are surfaced — toolchain/prelude noise is not;
wsroot = "" disables the summaries entirely.
*)
fun
diag_build
( target: string, wsroot: string
, doctext: string, report: string): jval
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_diag.sats] *)
(***********************************************************************)
