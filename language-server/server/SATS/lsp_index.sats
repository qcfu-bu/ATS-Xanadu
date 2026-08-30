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
(*
completion candidates.  kind: 0 variable/value, 1 function,
2 constructor, 3 type (the driver's P/S record kinds).  rank orders
sources: 1 = target-file decl, 2 = workspace-dep decl, 3 = pervasive.
Locals (L records) carry a visibility span instead of a rank — they
outrank everything when the position is inside the span.
*)
datatype
candlst =
| CDnil of ()
| CDcons of (sint(*kind*), sint(*rank*), string(*name*), candlst)
//
(* record/tuple members keyed by the receiver expression's span *)
datatype
memlst =
| MMnil of ()
| MMcons of
  (sint, sint, sint, sint, sint(*kind*), string(*name*), memlst)
//
datatype
loclst =
| LCnil of ()
| LCcons of
  ( sint(*kind*)
  , sint, sint, sint, sint(*scope span*)
  , string(*name*), loclst)
//
(*
documentSymbol records (M7): a target-file top-level declaration —
kind (0 value, 1 fun, 2 con, 3 type), name span, decl span, name.
Parse order is reversed emission order; idx_symbols restores document
order.
*)
datatype
symlst =
| SYnil of ()
| SYcons of
  ( sint(*kind*)
  , sint, sint, sint, sint(*name span*)
  , sint, sint, sint, sint(*decl span*)
  , string(*name*), symlst)
//
(* ****** ****** *)
//
(* parse the sentinel-delimited record stream *)
fun
idx_parse
(s0: string): @(hovlst, deflst, toklst, candlst, loclst, memlst, symlst)
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
(*
the CompletionList for the word being typed at (line, character) in
doctext: locals-in-scope > file decls > dep decls > pervasives >
keywords > buffer words; case-insensitive prefix filter; deduped by
name (best source wins); capped with isIncomplete.
*)
fun
idx_complete
( cl: candlst, ll: loclst, ml: memlst
, doctext: string, ln: sint, ch: sint): jval
//
(* ****** ****** *)
(* M7: references / documentHighlight / documentSymbol *)
(* ****** ****** *)
//
(*
resolve the REFERENCE TARGET at (line, character): the definition the
position's innermost use-site points at, or — when the position sits
ON a definition in this very file (path) — that definition itself.
@(found 0/1, defpath, dl0, dc0, dl1, dc1).
*)
fun
idx_ref_target
( dl: deflst, path: string
, ln: sint, ch: sint): @(sint, string, sint, sint, sint, sint)
//
(*
prepend, onto acc, a Location {uri, range} for every use-site in dl
whose definition is exactly (dpath, d0..d3).  uri names the file dl
was indexed from.
*)
fun
idx_ref_locs
( dl: deflst, uri: string
, dpath: string, d0: sint, d1: sint, d2: sint, d3: sint
, acc: jvlst): jvlst
//
(*
the DocumentHighlight[] for the same-target use-sites within this
file (kind 1 = Text).
*)
fun
idx_ref_hls
( dl: deflst
, dpath: string, d0: sint, d1: sint, d2: sint, d3: sint): jval
//
(* a Range literal (the def-site addition for includeDeclaration) *)
fun
idx_range_jv
(l0: sint, c0: sint, l1: sint, c1: sint): jval
//
(*
the DocumentSymbol[] outline (document order): name, kind (candidate
kind -> LSP SymbolKind), range = decl span, selectionRange = name
span.
*)
fun
idx_symbols(yl: symlst): jval
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_index.sats] *)
(***********************************************************************)
