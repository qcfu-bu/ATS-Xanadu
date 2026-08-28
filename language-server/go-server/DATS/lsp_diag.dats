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
the smallest-width target-file span on the line (ties -> the LATER,
i.e. more deeply nested, occurrence)
*)
fun
best_loc
(line: string, target: string): dloc =
let
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
  if streq(path, target)
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
end//endof[best_loc]
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
(* printed 1-based -> LSP 0-based (columns are already UTF-16 units) *)
fun
mk_pos(l0: sint, c0: sint): jval =
JVobj
( JKVcons("line", JVint(l0 - 1)
, JKVcons("character", JVint(c0 - 1), JKVnil())))
//
fun
mk_diag
(l0: sint, c0: sint, l1: sint, c1: sint, msg: string): jval =
JVobj
( JKVcons("range"
, JVobj
  ( JKVcons("start", mk_pos(l0, c0)
  , JKVcons("end", mk_pos(l1, c1), JKVnil())))
, JKVcons("severity", JVint(1)
, JKVcons("source", JVstr("ats3")
, JKVcons("message", JVstr(msg), JKVnil())))))
//
fun
jvl_rev(xs: jvlst, acc: jvlst): jvlst =
case+ xs of
| JVLnil() => acc
| JVLcons(x0, r0) => jvl_rev(r0, JVLcons(x0, acc))
//
(* ****** ****** *)
//
#implfun
diag_array
(target, report) =
let
val n0 = strn_length(report)
fun
lines
(ls: sint, seen: spans, acc: jvlst): jvlst =
if (ls >= n0) then acc else
let
val le0 = strn_index_of(report, ls, "\n")
val le = (if (le0 < 0) then n0 else le0): sint
val nxt = (if (le0 < 0) then n0 else le0 + 1): sint
val preadq = strn_starts_at(report, ls, "PREAD00-ERROR:")
val f3q = strn_starts_at(report, ls, "F3PERR0-ERROR:")
in
if (if preadq then true else f3q)
then
let
val line = strn_slice(report, ls, le)
in
case+ best_loc(line, target) of
| DLnone() => lines(nxt, seen, acc)
| DLsome(_, _, l0, c0, l1, c1) =>
  (
  if sp_has(seen, l0, c0, l1, c1)
  then lines(nxt, seen, acc)
  else
  lines
  ( nxt
  , SPcons(l0, c0, l1, c1, seen)
  , JVLcons(mk_diag(l0, c0, l1, c1, classify(line, preadq)), acc)))
end
else lines(nxt, seen, acc)
end
in//let
JVarr(jvl_rev(lines(0, SPnil(), JVLnil()), JVLnil()))
end//endof[diag_array]
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_diag.dats] *)
(***********************************************************************)
