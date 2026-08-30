(* ****** ****** *)
(*
lsp_diag.dats — checker-report -> LSP diagnostics.  See lsp_diag.sats.
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
(* a parsed location: (path, span width, l0, c0, l1, c1) — all printed 1-based *)
datatype
dloc =
| DLnone of ()
| DLsome of (string, sint, sint, sint, sint, sint)
//
(* ****** ****** *)
//
(* the index just past lit at i0, or -1 *)
fun
d_expect
(s0: string, i0: sint, lit: string): sint =
if strn_starts_at(s0, i0, lit)
then i0 + strn_length(lit) else (0 - 1)
//
(*
parse "PATH)@(N(line=L,offs=C)--N2(line=L2,offs=C2))" with p0 at the
"LCSRCsome1(" marker; any shape mismatch is DLnone.
*)
fun
parse_loc
(s0: string, p0: sint): dloc =
let
val i0 = p0 + 11
val q0 = strn_index_of(s0, i0, ")@(")
in
if (q0 < 0) then DLnone() else
let
val path = strn_slice(s0, i0, q0)
val r0 = atoi_at(s0, q0+3)
val a1 = d_expect(s0, r0.1, "(line=")
in
if (a1 < 0) then DLnone() else
let
val rl = atoi_at(s0, a1)
val a2 = d_expect(s0, rl.1, ",offs=")
in
if (a2 < 0) then DLnone() else
let
val rc = atoi_at(s0, a2)
val a3 = d_expect(s0, rc.1, ")--")
in
if (a3 < 0) then DLnone() else
let
val r1 = atoi_at(s0, a3)
val b1 = d_expect(s0, r1.1, "(line=")
in
if (b1 < 0) then DLnone() else
let
val rl2 = atoi_at(s0, b1)
val b2 = d_expect(s0, rl2.1, ",offs=")
in
if (b2 < 0) then DLnone() else
let
val rc2 = atoi_at(s0, b2)
val b3 = d_expect(s0, rc2.1, "))")
in
if (b3 < 0) then DLnone() else
DLsome(path, r1.0 - r0.0, rl.0, rc.0, rl2.0, rc2.0)
end
end
end
end
end
end
end//endof[parse_loc]
//
(*
the smallest-width span on the line (ties -> the LATER, i.e. more
deeply nested, occurrence); targetq restricts to the target path.
*)
fun
scan_loc
(line: string, target: string, targetq: bool): dloc =
let
fun
takeq(path: string): bool =
if targetq then streq(path, target) else true
fun
loop(from: sint, best: dloc): dloc =
let
val p0 = strn_index_of(line, from, "LCSRCsome1(")
in
if (p0 < 0) then best else
let
val dl = parse_loc(line, p0)
in
case+ dl of
| DLnone() => loop(p0+11, best)
| DLsome(path, w0, _, _, _, _) =>
  (
  if takeq(path)
  then
  (
  case+ best of
  | DLnone() => loop(p0+11, dl)
  | DLsome(_, bw, _, _, _, _) =>
    (if (w0 <= bw) then loop(p0+11, dl) else loop(p0+11, best)))
  else loop(p0+11, best))
end
end
in//let
loop(0, DLnone())
end//endof[scan_loc]
//
(* ****** ****** *)
//
fun
classify
(line: string, preadq: bool): string =
if preadq then "syntax error" else
if (strn_index_of(line, 0, "D3Et2pck") >= 0) then "type mismatch" else
let
val p0 = strn_index_of(line, 0, "D2Enone1(D1Eid0(")
in
if (p0 >= 0)
then
let
val e0 = strn_index_of(line, p0+16, ")")
in
if (e0 < 0)
then "unbound identifier"
else strn_append("unbound identifier: ", strn_slice(line, p0+16, e0))
end
else
if (strn_index_of(line, 0, "D3Etimp") >= 0) then "unresolved template" else
if (strn_index_of(line, 0, "D3Etimq") >= 0) then "unresolved template" else
if (strn_index_of(line, 0, "D0Cerrck") >= 0) then "syntax error" else
if (strn_index_of(line, 0, "D0Eerrck") >= 0) then "syntax error" else
if (strn_index_of(line, 0, "D0Perrck") >= 0) then "syntax error" else
if (strn_index_of(line, 0, "D0Ctkerr") >= 0) then "syntax error" else
if (strn_index_of(line, 0, "S2Eerrck") >= 0) then "static error" else
"error"
end//endof[classify]
//
(* ****** ****** *)
//
(* the spans already emitted (dedup keep-first) *)
datatype
spans =
| SPnil of ()
| SPcons of (sint, sint, sint, sint, spans)
//
fun
sp_has
(sp: spans, l0: sint, c0: sint, l1: sint, c1: sint): bool =
case+ sp of
| SPnil() => false
| SPcons(a0, b0, a1, b1, r0) =>
  (
  if (a0 = l0)
  then
  (
  if (b0 = c0)
  then
  (
  if (a1 = l1)
  then (if (b1 = c1) then true else sp_has(r0, l0, c0, l1, c1))
  else sp_has(r0, l0, c0, l1, c1))
  else sp_has(r0, l0, c0, l1, c1))
  else sp_has(r0, l0, c0, l1, c1))
//
(* ****** ****** *)
//
(* foreign-file errors, grouped by path (first-seen order preserved) *)
datatype
fors =
| FRSnil of ()
| FRScons of (string(*path*), sint(*count*), sint(*first line*), string(*first class*), fors)
//
fun
frs_add
(fs: fors, path: string, l0: sint, cls: string): fors =
case+ fs of
| FRSnil() => FRScons(path, 1, l0, cls, FRSnil())
| FRScons(p0, n0, a0, c0, r0) =>
  (
  if streq(p0, path)
  then FRScons(p0, n0+1, a0, c0, r0)
  else FRScons(p0, n0, a0, c0, frs_add(r0, path, l0, cls)))
//
(* ****** ****** *)
//
(* 0-based positions, straight through *)
fun
mk_pos0(l0: sint, c0: sint): jval =
JVobj
( JKVcons("line", JVint(l0)
, JKVcons("character", JVint(c0), JKVnil())))
//
fun
mk_diag0
(l0: sint, c0: sint, l1: sint, c1: sint, msg: string): jval =
JVobj
( JKVcons("range"
, JVobj
  ( JKVcons("start", mk_pos0(l0, c0)
  , JKVcons("end", mk_pos0(l1, c1), JKVnil())))
, JKVcons("severity", JVint(1)
, JKVcons("source", JVstr("ats3")
, JKVcons("message", JVstr(msg), JKVnil())))))
//
(* printed 1-based -> LSP 0-based (columns are already UTF-16 units) *)
fun
mk_diag
(l0: sint, c0: sint, l1: sint, c1: sint, msg: string): jval =
mk_diag0(l0 - 1, c0 - 1, l1 - 1, c1 - 1, msg)
//
fun
jvl_rev(xs: jvlst, acc: jvlst): jvlst =
case+ xs of
| JVLnil() => acc
| JVLcons(x0, r0) => jvl_rev(r0, JVLcons(x0, acc))
//
fun
jvl_append(xs: jvlst, ys: jvlst): jvlst =
case+ xs of
| JVLnil() => ys
| JVLcons(x0, r0) => JVLcons(x0, jvl_append(r0, ys))
//
(* ****** ****** *)
//
fun
basename_of(path: string): string =
let
val n0 = strn_length(path)
fun
rsl(k0: sint, best: sint): sint =
if (k0 >= n0) then best else
if (byte_at(path, k0) = 47) then rsl(k0+1, k0) else rsl(k0+1, best)
val p0 = rsl(0, 0 - 1)
in//let
strn_slice(path, p0+1, n0)
end//endof[basename_of]
//
(*
the 0-based (line, ucol-start, ucol-end) of the first occurrence of
ndl in doctext (UTF-16 columns); line = -1 when absent
*)
fun
find_pos
(doctext: string, ndl: string): @(sint, sint, sint) =
let
val p0 = strn_index_of(doctext, 0, ndl)
in
if (p0 < 0) then @(0 - 1, 0, 0) else
let
fun
lc(k0: sint, ln: sint, ls: sint): @(sint, sint) =
if (k0 >= p0) then @(ln, ls) else
if (byte_at(doctext, k0) = 10)
then lc(k0+1, ln+1, k0+1) else lc(k0+1, ln, ls)
val r0 = lc(0, 0, 0)
val c0 = u16_units(doctext, r0.1, p0)
in
@(r0.0, c0, c0 + u16_units(doctext, p0, p0 + strn_length(ndl)))
end
end//endof[find_pos]
//
(*
one summary diagnostic per foreign file, at its basename mention —
preferring the QUOTED occurrence (the staload string, `dep.sats"`)
over e.g. a mention in a comment; the range covers the basename only.
*)
fun
mk_foreign
(doctext: string, path: string, n0: sint, l0: sint, cls: string): jval =
let
val bn = basename_of(path)
val psq = find_pos(doctext, strn_append(bn, "\""))
val ps =
(
if (psq.0 >= 0)
then @(psq.0, psq.1, psq.2 - 1)
else find_pos(doctext, bn)): @(sint, sint, sint)
val msg =
strn_append("errors in staloaded file: "
, strn_append(path
, strn_append(" ("
, strn_append(itoa(n0)
, strn_append(", first: "
, strn_append(cls
, strn_append(" at line "
, strn_append(itoa(l0), ")"))))))))
in
if (ps.0 < 0)
then mk_diag0(0, 0, 0, 1, msg)
else mk_diag0(ps.0, ps.1, ps.0, ps.2, msg)
end//endof[mk_foreign]
//
fun
frs_jv
(doctext: string, fs: fors): jvlst =
case+ fs of
| FRSnil() => JVLnil()
| FRScons(p0, n0, a0, c0, r0) =>
  JVLcons(mk_foreign(doctext, p0, n0, a0, c0), frs_jv(doctext, r0))
//
(* ****** ****** *)
//
#implfun
diag_build
(target, wsroot, doctext, report) =
let
val n0 = strn_length(report)
fun
lines
( ls: sint
, seen: spans, fseen: spans
, fs: fors, acc: jvlst): @(jvlst, fors) =
if (ls >= n0) then @(acc, fs) else
let
val le0 = strn_index_of(report, ls, "\n")
val le = (if (le0 < 0) then n0 else le0): sint
val nxt = (if (le0 < 0) then n0 else le0 + 1): sint
val preadq = strn_starts_at(report, ls, "PREAD00-ERROR:")
val f3q = strn_starts_at(report, ls, "F3PERR0-ERROR:")
val f2q = strn_starts_at(report, ls, "F2PERR0-ERROR:")
in
if (if preadq then true else (if f3q then true else f2q))
then
let
val line = strn_slice(report, ls, le)
in
case+ scan_loc(line, target, true) of
| DLsome(_, _, l0, c0, l1, c1) =>
  (
  if sp_has(seen, l0, c0, l1, c1)
  then lines(nxt, seen, fseen, fs, acc)
  else
  lines
  ( nxt
  , SPcons(l0, c0, l1, c1, seen), fseen, fs
  , JVLcons(mk_diag(l0, c0, l1, c1, classify(line, preadq)), acc)))
| DLnone() =>
  (
  case+ scan_loc(line, target, false) of
  | DLnone() => lines(nxt, seen, fseen, fs, acc)
  | DLsome(path, _, l0, c0, l1, c1) =>
    (
    if (strn_length(wsroot) <= 0)
    then lines(nxt, seen, fseen, fs, acc) else
    if strn_starts_at(path, 0, wsroot)
    then
    (
    if sp_has(fseen, l0, c0, l1, c1)
    then lines(nxt, seen, fseen, fs, acc)
    else
    lines
    ( nxt
    , seen, SPcons(l0, c0, l1, c1, fseen)
    , frs_add(fs, path, l0, classify(line, preadq)), acc))
    else lines(nxt, seen, fseen, fs, acc)))
end
else lines(nxt, seen, fseen, fs, acc)
end
val r0 = lines(0, SPnil(), SPnil(), FRSnil(), JVLnil())
in//let
JVarr
(jvl_append(jvl_rev(r0.0, JVLnil()), frs_jv(doctext, r0.1)))
end//endof[diag_build]
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_diag.dats] *)
(***********************************************************************)
