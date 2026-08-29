(* ****** ****** *)
(*
lsp_index.sats — the hover/def index: parse the checker's --index
records and answer position queries.

The driver (xats2go-tcheck --index) emits, between sentinel lines on
stdout,

  H <TAB> l0 <TAB> c0 <TAB> l1 <TAB> c1 <TAB> <type>
  D <TAB> l0 <TAB> c0 <TAB> l1 <TAB> c1 <TAB> <defpath> <TAB> dl0 <TAB> dc0 <TAB> dl1 <TAB> dc1
  T <TAB> l0 <TAB> c0 <TAB> l1 <TAB> c1 <TAB> <kind>

with 0-based positions whose columns are UTF-16 code units — LSP's
default encoding, no conversion.  A query returns the INNERMOST
(smallest-span) record containing the position.  T records are
single-line semantic tokens; kind indexes the server legend
(0 variable, 1 function, 2 enumMember).
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#staload "./lsp_json.sats"
(* ****** ****** *)
//
datatype
hovlst =
| HVnil of ()
| HVcons of (sint, sint, sint, sint, string(*type*), hovlst)
//
datatype
deflst =
| DFnil of ()
| DFcons of
  ( sint, sint, sint, sint
  , string(*defpath*)
  , sint, sint, sint, sint, deflst)
//
datatype
toklst =
| TKnil of ()
| TKcons of
  (sint(*line*), sint(*col*), sint(*len*), sint(*kind*), toklst)
//
(* ****** ****** *)
//
(* parse the sentinel-delimited record stream *)
fun
idx_parse(s0: string): @(hovlst, deflst, toklst)
//
(*
the Hover result for (line, character): {contents, range}, or JVerr
when no record contains the position
*)
fun
idx_hover(hl: hovlst, ln: sint, ch: sint): jval
//
(*
the definition's (path, range) for (line, character) as
@(path, Range jval); path = "" when no record contains the position
*)
fun
idx_def(dl: deflst, ln: sint, ch: sint): @(string, jval)
//
(*
the LSP semanticTokens data array: tokens sorted by position
(merge sort), same-start duplicates dropped, delta-encoded as
[dLine, dStart, len, kind, 0]*
*)
fun
idx_toks_data(tl: toklst): jval
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_index.sats] *)
(***********************************************************************)
