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
( ls: sint
, hl: hovlst, dl: deflst, tl: toklst
, cl: candlst, ll: loclst)
: @(hovlst, deflst, toklst, candlst, loclst) =
if (ls >= e0) then @(hl, dl, tl, cl, ll) else
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
lines(nxt, HVcons(f1.0, f2.0, f3.0, f4.0, typ, hl), dl, tl, cl, ll)
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
then lines(nxt, hl, dl, tl, cl, ll)
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
  , path, g1.0, g2.0, g3.0, g4.0, dl), tl, cl, ll)
end
end
else
if strn_starts_at(s0, ls, "T\t")
then
let
val f1 = ifield(s0, ls+2)
val f2 = ifield(s0, f1.1)
val f3 = ifield(s0, f2.1)
val f4 = ifield(s0, f3.1)
val k0 = atoi_at(s0, f4.1)
in
(* single-line tokens only; length in UTF-16 units *)
if (f3.0 = f1.0)
then
lines
(nxt, hl, dl, TKcons(f1.0, f2.0, f4.0 - f2.0, k0.0, tl), cl, ll)
else lines(nxt, hl, dl, tl, cl, ll)
end
else
if strn_starts_at(s0, ls, "P\t")
then
let
val f1 = ifield(s0, ls+2)
in
lines
( nxt, hl, dl, tl
, CDcons(f1.0, 3, strn_slice(s0, f1.1, le), cl), ll)
end
else
if strn_starts_at(s0, ls, "S\t")
then
let
val f1 = ifield(s0, ls+2)
val f2 = ifield(s0, f1.1)
val rnk = (if (f2.0 = 0) then 1 else 2): sint
in
lines
( nxt, hl, dl, tl
, CDcons(f1.0, rnk, strn_slice(s0, f2.1, le), cl), ll)
end
else
if strn_starts_at(s0, ls, "L\t")
then
let
val f1 = ifield(s0, ls+2)
val f2 = ifield(s0, f1.1)
val f3 = ifield(s0, f2.1)
val f4 = ifield(s0, f3.1)
val f5 = ifield(s0, f4.1)
in
lines
( nxt, hl, dl, tl, cl
, LCcons
  ( f1.0, f2.0, f3.0, f4.0, f5.0
  , strn_slice(s0, f5.1, le), ll))
end
else lines(nxt, hl, dl, tl, cl, ll)
end
in//let
if (b0 < 0) then @(HVnil(), DFnil(), TKnil(), CDnil(), LCnil()) else
if (e0 < 0) then @(HVnil(), DFnil(), TKnil(), CDnil(), LCnil()) else
lines(b0 + 20, HVnil(), DFnil(), TKnil(), CDnil(), LCnil())
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
(* semantic tokens: O(n log n) merge sort + LSP delta encoding *)
(* ****** ****** *)
//
fun
tk_leq
(al: sint, ac: sint, bl: sint, bc: sint): bool =
if (al < bl) then true else
if (al > bl) then false else (ac <= bc)
//
fun
tk_split
(xs: toklst): @(toklst, toklst) =
case+ xs of
| TKnil() => @(TKnil(), TKnil())
| TKcons(a0, b0, c0, d0, r0) =>
  let
  val s0 = tk_split(r0)
  in
  @(TKcons(a0, b0, c0, d0, s0.1), s0.0)
  end
//
fun
tk_merge
(xs: toklst, ys: toklst): toklst =
case+ xs of
| TKnil() => ys
| TKcons(al, ac, an, ak, ar) =>
  (
  case+ ys of
  | TKnil() => xs
  | TKcons(bl, bc, bn, bk, br) =>
    (
    if tk_leq(al, ac, bl, bc)
    then TKcons(al, ac, an, ak, tk_merge(ar, ys))
    else TKcons(bl, bc, bn, bk, tk_merge(xs, br))))
//
fun
tk_sort(xs: toklst): toklst =
case+ xs of
| TKnil() => xs
| TKcons(_, _, _, _, TKnil()) => xs
| _(*two or more*) =>
  let
  val s0 = tk_split(xs)
  in
  tk_merge(tk_sort(s0.0), tk_sort(s0.1))
  end
//
fun
jvl_rev2(xs: jvlst, acc: jvlst): jvlst =
case+ xs of
| JVLnil() => acc
| JVLcons(x0, r0) => jvl_rev2(r0, JVLcons(x0, acc))
//
#implfun
idx_toks_data
(tl) =
let
fun
enc
( xs: toklst
, pl: sint, pc: sint, fst: sint
, acc: jvlst): jvlst =
case+ xs of
| TKnil() => acc
| TKcons(l0, c0, n0, k0, r0) =>
  (
  (* the wire needs strictly increasing starts: drop duplicates *)
  if (if fst = 0 then (if l0 = pl then (c0 = pc) else false) else false)
  then enc(r0, pl, pc, fst, acc)
  else
  let
  val dl = (if fst = 1 then l0 else l0 - pl): sint
  val dc = (if (if fst = 0 then (l0 = pl) else false) then c0 - pc else c0): sint
  in
  enc
  ( r0, l0, c0, 0
  , JVLcons(JVint(0)
  , JVLcons(JVint(k0)
  , JVLcons(JVint(n0)
  , JVLcons(JVint(dc)
  , JVLcons(JVint(dl), acc))))))
  end)
in//let
JVarr(jvl_rev2(enc(tk_sort(tl), 0, 0, 1, JVLnil()), JVLnil()))
end//endof[idx_toks_data]
//
(* ****** ****** *)
(* completion *)
(* ****** ****** *)
//
(* identifier bytes: [A-Za-z0-9_$'] *)
fun
wordq(c0: sint): bool =
if (c0 >= 97) then (if (c0 <= 122) then true else false) else
if (c0 >= 65) then (if (c0 <= 90) then true else (c0 = 95)) else
if (c0 >= 48) then (if (c0 <= 57) then true else false) else
if (c0 = 36) then true else
if (c0 = 39) then true else false
//
fun
ci_low(c0: sint): sint =
if (c0 >= 65) then (if (c0 <= 90) then c0 + 32 else c0) else c0
//
(* is pre a (case-insensitive, ASCII) prefix of name? *)
fun
ci_prefixq
(name: string, pre: string): bool =
let
val n0 = strn_length(name)
val n1 = strn_length(pre)
fun
loop(i0: sint): bool =
if (i0 >= n1) then true else
if (ci_low(byte_at(name, i0)) = ci_low(byte_at(pre, i0)))
then loop(i0+1) else false
in//let
if (n1 <= n0) then loop(0) else false
end//endof[ci_prefixq]
//
(*
the byte offset of LSP position (ln, ch) in s0: walk to the line,
then advance ch UTF-16 units (an astral char is 2 units, 4 bytes)
*)
fun
pos_byteoff
(s0: string, ln: sint, ch: sint): sint =
let
val n0 = strn_length(s0)
fun
tol(k0: sint, l0: sint): sint =
if (l0 >= ln) then k0 else
if (k0 >= n0) then k0 else
if (byte_at(s0, k0) = 10) then tol(k0+1, l0+1) else tol(k0+1, l0)
fun
adv(k0: sint, u0: sint): sint =
if (u0 >= ch) then k0 else
if (k0 >= n0) then k0 else
let
val c0 = byte_at(s0, k0)
in
if (c0 = 10) then k0 else
if (c0 < 128) then adv(k0+1, u0+1) else
if (c0 < 192) then adv(k0+1, u0) else
if (c0 < 224) then adv(k0+2, u0+1) else
if (c0 < 240) then adv(k0+3, u0+1)
else adv(k0+4, u0+2)
end
in//let
adv(tol(0, 0), 0)
end//endof[pos_byteoff]
//
(* accumulate items with a name-dedup list and a cap *)
datatype
snames =
| SNnil of ()
| SNcons of (string, snames)
//
datatype
accm =
| ACC of (jvlst(*items, reversed*), snames, sint(*count*))
//
fun
sn_has(sn: snames, s0: string): bool =
case+ sn of
| SNnil() => false
| SNcons(s1, r0) =>
  (if streq(s1, s0) then true else sn_has(r0, s0))
//
(* our kind codes -> LSP CompletionItemKind *)
fun
lsp_cik(knd: sint): sint =
if (knd = 1) then 3(*Function*) else
if (knd = 2) then 20(*EnumMember*) else
if (knd = 3) then 7(*Class*) else
if (knd = 4) then 14(*Keyword*) else
if (knd = 5) then 1(*Text*) else 6(*Variable*)
//
fun
mk_item
(knd: sint, rank: sint, name: string, rng: jval): jval =
JVobj
( JKVcons("label", JVstr(name)
, JKVcons("kind", JVint(lsp_cik(knd))
, JKVcons("sortText", JVstr(strn_append(itoa(rank), name))
, JKVcons("textEdit"
  , JVobj
    ( JKVcons("range", rng
    , JKVcons("newText", JVstr(name), JKVnil())))
  , JKVnil())))))
//
fun
acc_add
( a0: accm, knd: sint, rank: sint
, name: string, pre: string, rng: jval): accm =
case+ a0 of
| ACC(items, seen, cnt) =>
  (
  if (cnt >= 200) then a0 else
  if ci_prefixq(name, pre)
  then
  (
  if sn_has(seen, name) then a0
  else
  ACC
  ( JVLcons(mk_item(knd, rank, name, rng), items)
  , SNcons(name, seen), cnt + 1))
  else a0)
//
(* candidates of one rank tier *)
fun
acc_cands
( a0: accm, cl: candlst, rank: sint
, pre: string, rng: jval): accm =
case+ cl of
| CDnil() => a0
| CDcons(knd, r0, name, cl1) =>
  (
  if (r0 = rank)
  then acc_cands(acc_add(a0, knd, rank, name, pre, rng), cl1, rank, pre, rng)
  else acc_cands(a0, cl1, rank, pre, rng))
//
(* locals whose scope contains the position *)
fun
acc_locals
( a0: accm, ll: loclst
, ln: sint, ch: sint, pre: string, rng: jval): accm =
case+ ll of
| LCnil() => a0
| LCcons(knd, sl0, sc0, sl1, sc1, name, ll1) =>
  (
  if pos_inq(ln, ch, sl0, sc0, sl1, sc1)
  then acc_locals(acc_add(a0, knd, 0, name, pre, rng), ll1, ln, ch, pre, rng)
  else acc_locals(a0, ll1, ln, ch, pre, rng))
//
(* the ATS3 keyword tier *)
fun
acc_kw1(a0: accm, kw: string, pre: string, rng: jval): accm =
acc_add(a0, 4, 4, kw, pre, rng)
//
fun
acc_keywords(a0: accm, pre: string, rng: jval): accm =
let
val a0 = acc_kw1(a0, "val", pre, rng)
val a0 = acc_kw1(a0, "var", pre, rng)
val a0 = acc_kw1(a0, "fun", pre, rng)
val a0 = acc_kw1(a0, "fn", pre, rng)
val a0 = acc_kw1(a0, "fnx", pre, rng)
val a0 = acc_kw1(a0, "and", pre, rng)
val a0 = acc_kw1(a0, "let", pre, rng)
val a0 = acc_kw1(a0, "in", pre, rng)
val a0 = acc_kw1(a0, "end", pre, rng)
val a0 = acc_kw1(a0, "if", pre, rng)
val a0 = acc_kw1(a0, "then", pre, rng)
val a0 = acc_kw1(a0, "else", pre, rng)
val a0 = acc_kw1(a0, "case", pre, rng)
val a0 = acc_kw1(a0, "of", pre, rng)
val a0 = acc_kw1(a0, "when", pre, rng)
val a0 = acc_kw1(a0, "lam", pre, rng)
val a0 = acc_kw1(a0, "fix", pre, rng)
val a0 = acc_kw1(a0, "where", pre, rng)
val a0 = acc_kw1(a0, "local", pre, rng)
val a0 = acc_kw1(a0, "datatype", pre, rng)
val a0 = acc_kw1(a0, "typedef", pre, rng)
val a0 = acc_kw1(a0, "abstype", pre, rng)
val a0 = acc_kw1(a0, "implement", pre, rng)
val a0 = acc_kw1(a0, "overload", pre, rng)
val a0 = acc_kw1(a0, "with", pre, rng)
val a0 = acc_kw1(a0, "try", pre, rng)
val a0 = acc_kw1(a0, "raise", pre, rng)
in
acc_kw1(a0, "extern", pre, rng)
end
//
(* words already present in the buffer (freshness tier; skips the
   partial itself) *)
fun
acc_bufwords
(a0: accm, s0: string, pre: string, rng: jval): accm =
let
val n0 = strn_length(s0)
fun
skipw(k0: sint): sint =
if (k0 >= n0) then k0 else
if wordq(byte_at(s0, k0)) then skipw(k0+1) else k0
fun
loop(k0: sint, a0: accm): accm =
if (k0 >= n0) then a0 else
if wordq(byte_at(s0, k0))
then
let
val ke = skipw(k0)
val w0 = strn_slice(s0, k0, ke)
val a1 =
(
if streq(w0, pre) then a0
else
(
if (ke - k0 >= 2)
then acc_add(a0, 5, 5, w0, pre, rng) else a0)): accm
in
loop(ke, a1)
end
else loop(k0+1, a0)
in//let
loop(0, a0)
end//endof[acc_bufwords]
//
#implfun
idx_complete
(cl, ll, doctext, ln, ch) =
let
val cur = pos_byteoff(doctext, ln, ch)
fun
back(k0: sint): sint =
if (k0 <= 0) then 0 else
if wordq(byte_at(doctext, k0 - 1)) then back(k0 - 1) else k0
val ws = back(cur)
val pre = strn_slice(doctext, ws, cur)
(* identifier bytes are ASCII, so bytes = UTF-16 units here *)
val rng = mk_range_jv(ln, ch - (cur - ws), ln, ch)
val a0 = ACC(JVLnil(), SNnil(), 0)
val a0 = acc_locals(a0, ll, ln, ch, pre, rng)
val a0 = acc_cands(a0, cl, 1, pre, rng)
val a0 = acc_cands(a0, cl, 2, pre, rng)
val a0 = acc_cands(a0, cl, 3, pre, rng)
val a0 = acc_keywords(a0, pre, rng)
val a0 = acc_bufwords(a0, doctext, pre, rng)
in//let
case+ a0 of
| ACC(items, _, cnt) =>
  JVobj
  ( JKVcons("isIncomplete"
  , (if (cnt >= 200) then JVtrue() else JVfalse()): jval
  , JKVcons("items", JVarr(jvl_rev2(items, JVLnil())), JKVnil())))
end//endof[idx_complete]
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_index.dats] *)
(***********************************************************************)
