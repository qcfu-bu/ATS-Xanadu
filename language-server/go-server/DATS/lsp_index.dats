(* ****** ****** *)
(*
lsp_index.dats — parse + query the --index records.  See
lsp_index.sats.
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
#include
"./../HATS/lspserver_sats.hats"
(* ****** ****** *)
//
(* the index of the next TAB at/after i0, or -1 *)
fun
tab_at
(s0: string, i0: sint, n0: sint): sint =
if (i0 >= n0) then (0 - 1) else
if (byte_at(s0, i0) = 9) then i0 else tab_at(s0, i0+1, n0)
//
(* a TAB-terminated integer field at i0: @(value, index past the TAB) *)
fun
ifield
(s0: string, i0: sint): @(sint, sint) =
let
val r0 = atoi_at(s0, i0)
in
@(r0.0, r0.1 + 1)
end
//
(* ****** ****** *)
//
#implfun
idx_parse
(s0) =
let
val n0 = strn_length(s0)
val b0 = strn_index_of(s0, 0, "//==XLSPIDX-BEGIN==\n")
val e0 = strn_index_of(s0, 0, "//==XLSPIDX-END==")
fun
lines
(ls: sint, hl: hovlst, dl: deflst): @(hovlst, deflst) =
if (ls >= e0) then @(hl, dl) else
let
val le0 = strn_index_of(s0, ls, "\n")
val le = (if (le0 < 0) then e0 else le0): sint
val nxt = (if (le0 < 0) then e0 else le0 + 1): sint
in
if strn_starts_at(s0, ls, "H\t")
then
let
val f1 = ifield(s0, ls+2)
val f2 = ifield(s0, f1.1)
val f3 = ifield(s0, f2.1)
val f4 = ifield(s0, f3.1)
val typ = strn_slice(s0, f4.1, le)
in
lines(nxt, HVcons(f1.0, f2.0, f3.0, f4.0, typ, hl), dl)
end
else
if strn_starts_at(s0, ls, "D\t")
then
let
val f1 = ifield(s0, ls+2)
val f2 = ifield(s0, f1.1)
val f3 = ifield(s0, f2.1)
val f4 = ifield(s0, f3.1)
val tb = tab_at(s0, f4.1, le)
in
if (tb < 0)
then lines(nxt, hl, dl)
else
let
val path = strn_slice(s0, f4.1, tb)
val g1 = ifield(s0, tb+1)
val g2 = ifield(s0, g1.1)
val g3 = ifield(s0, g2.1)
val g4 = atoi_at(s0, g3.1)
in
lines
( nxt, hl
, DFcons
  ( f1.0, f2.0, f3.0, f4.0
  , path, g1.0, g2.0, g3.0, g4.0, dl))
end
end
else lines(nxt, hl, dl)
end
in//let
if (b0 < 0) then @(HVnil(), DFnil()) else
if (e0 < 0) then @(HVnil(), DFnil()) else
lines(b0 + 20, HVnil(), DFnil())
end//endof[idx_parse]
//
(* ****** ****** *)
//
(* is (ln, ch) within [ (l0,c0), (l1,c1) )? *)
fun
pos_inq
(ln: sint, ch: sint
, l0: sint, c0: sint, l1: sint, c1: sint): bool =
let
val geb =
(
if (ln > l0) then true else
if (ln < l0) then false else (ch >= c0)): bool
val lte =
(
if (ln < l1) then true else
if (ln > l1) then false else (ch < c1)): bool
in
if geb then lte else false
end//endof[pos_inq]
//
(* the smaller-span metric: line span first, then column span *)
fun
span_metric
(l0: sint, c0: sint, l1: sint, c1: sint): sint =
let
val lsp = l1 - l0
in
if (lsp > 0) then lsp * 1000000 else (c1 - c0)
end
//
(* ****** ****** *)
//
fun
mk_pos_jv(l0: sint, c0: sint): jval =
JVobj
( JKVcons("line", JVint(l0)
, JKVcons("character", JVint(c0), JKVnil())))
//
fun
mk_range_jv
(l0: sint, c0: sint, l1: sint, c1: sint): jval =
JVobj
( JKVcons("start", mk_pos_jv(l0, c0)
, JKVcons("end", mk_pos_jv(l1, c1), JKVnil())))
//
(* ****** ****** *)
//
#implfun
idx_hover
(hl, ln, ch) =
let
fun
loop
( xs: hovlst
, bm: sint
, bl0: sint, bc0: sint, bl1: sint, bc1: sint
, btyp: string): jval =
case+ xs of
| HVnil() =>
  (
  if (bm < 0) then JVerr()
  else
  JVobj
  ( JKVcons("contents"
  , JVobj
    ( JKVcons("kind", JVstr("markdown")
    , JKVcons("value"
      , JVstr
        (strn_append("```ats\n", strn_append(btyp, "\n```")))
      , JKVnil())))
  , JKVcons("range", mk_range_jv(bl0, bc0, bl1, bc1), JKVnil()))))
| HVcons(l0, c0, l1, c1, typ, r0) =>
  (
  if pos_inq(ln, ch, l0, c0, l1, c1)
  then
  let
  val m0 = span_metric(l0, c0, l1, c1)
  in
  if (if bm < 0 then true else (m0 < bm))
  then loop(r0, m0, l0, c0, l1, c1, typ)
  else loop(r0, bm, bl0, bc0, bl1, bc1, btyp)
  end
  else loop(r0, bm, bl0, bc0, bl1, bc1, btyp))
in//let
loop(hl, 0 - 1, 0, 0, 0, 0, "")
end//endof[idx_hover]
//
(* ****** ****** *)
//
#implfun
idx_def
(dl, ln, ch) =
let
fun
loop
( xs: deflst
, bm: sint
, bpath: string
, bl0: sint, bc0: sint, bl1: sint, bc1: sint): @(string, jval) =
case+ xs of
| DFnil() =>
  (
  if (bm < 0)
  then @("", JVerr())
  else @(bpath, mk_range_jv(bl0, bc0, bl1, bc1)))
| DFcons(l0, c0, l1, c1, path, d0, d1, d2, d3, r0) =>
  (
  if pos_inq(ln, ch, l0, c0, l1, c1)
  then
  let
  val m0 = span_metric(l0, c0, l1, c1)
  in
  if (if bm < 0 then true else (m0 < bm))
  then loop(r0, m0, path, d0, d1, d2, d3)
  else loop(r0, bm, bpath, bl0, bc0, bl1, bc1)
  end
  else loop(r0, bm, bpath, bl0, bc0, bl1, bc1))
in//let
loop(dl, 0 - 1, "", 0, 0, 0, 0)
end//endof[idx_def]
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_index.dats] *)
(***********************************************************************)
