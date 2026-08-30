(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(*
xats2go_lspidx — see xats2go_lspidx.sats.  CLAUDE-2026-08-29.

Two pieces:
- typ_pr: the s2typ -> ATS3-surface pretty-printer (hover mode) per
  language-server/docs/S2TYP-SURFACE-SYNTAX.md, printing straight to
  the FILR (no string building; identifiers cannot contain tab/nl so
  records stay single-line).  Depth-capped ("...") defensively.
- the d3 walk: every d3exp/d3pat with a target-file span emits an H
  record; D3Evar/D3Ecst/D3Econ (+D3Pcon) also emit a D record with
  the entity's definition location.  Resolved template BODIES
  (D3Etimp/D3Etimq payloads) are NOT descended: they are
  instantiation copies, not user code.
*)
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
#include
"./../HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../HATS/mytmplib00.hats"
(* ****** ****** *)
(* [fpath_get_fnm1] is not in libxatsopt.hats *)
#staload "./../../../SATS/filpath.sats"
(* ****** ****** *)
#staload "./xats2go_lspidx.sats"
(* ****** ****** *)
(* ****** ****** *)
//
(* the raw print floor: belief-consistent leaves (see libcats GO arm) *)
#extern
fun
XATS2GO_strn_fprint:
(strn, FILR) -> void = $extnam()
#extern
fun
XATS2GO_gint_fprint$sint:
(sint, FILR) -> void = $extnam()
//
fun
pr(out: FILR, s0: strn): void = XATS2GO_strn_fprint(s0, out)
fun
pn(out: FILR, i0: sint): void = XATS2GO_gint_fprint$sint(i0, out)
//
(* ****** ****** *)
//
fun
lx_streq
(s1: strn, s2: strn): bool =
let
val n1 = strn_length(s1)
val n2 = strn_length(s2)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s1, i0) = strn_get$at(s2, i0)
then loop(i0+1) else false
in//let
if n1 = n2 then loop(0) else false
end//endof[lx_streq]
//
(* ****** ****** *)
(* the s2typ surface printer (hover mode) *)
(* ****** ****** *)
//
(* friendly names for prelude type constants (basics0.sats heads) *)
fun
cst_friendly(name: strn): strn =
if lx_streq(name, "xats_void_t") then "void" else
if lx_streq(name, "bool_type") then "bool" else
if lx_streq(name, "char_type") then "char" else
if lx_streq(name, "gint_type") then "int" else
if lx_streq(name, "gflt_type") then "double" else
if lx_streq(name, "string_i0_tx") then "string" else
if lx_streq(name, "p1tr_tbox") then "ptr" else
if lx_streq(name, "p2tr_tbox") then "p2tr" else
if lx_streq(name, "list_t0_i0_tx") then "list" else
if lx_streq(name, "list_vt_i0_vx") then "list_vt" else
if lx_streq(name, "optn_t0_i0_tx") then "optn" else
if lx_streq(name, "optn_vt_i0_vx") then "optn_vt" else
if lx_streq(name, "lazy_t0_tx") then "lazy" else
(* literal-type constants *)
if lx_streq(name, "the_s2exp_sint0") then "int" else
if lx_streq(name, "the_s2exp_bool0") then "bool" else
if lx_streq(name, "the_s2exp_char0") then "char" else
if lx_streq(name, "the_s2exp_dflt0") then "double" else
if lx_streq(name, "the_s2exp_strn0") then "string" else
if lx_streq(name, "the_s2exp_void0") then "void" else
if lx_streq(name, "the_s2exp_void") then "void" else
name
//
(* the per-width tag of a gint/gflt application argument *)
fun
width_name(tag: strn): strn =
if lx_streq(tag, "xats_sint_t") then "int" else
if lx_streq(tag, "xats_uint_t") then "uint" else
if lx_streq(tag, "xats_slint_t") then "lint" else
if lx_streq(tag, "xats_ulint_t") then "ulint" else
if lx_streq(tag, "xats_sllint_t") then "llint" else
if lx_streq(tag, "xats_ullint_t") then "ullint" else
if lx_streq(tag, "xats_ssint_t") then "sint" else
if lx_streq(tag, "xats_usint_t") then "usint" else
if lx_streq(tag, "xats_sflt_t") then "float" else
if lx_streq(tag, "xats_dflt_t") then "double" else
if lx_streq(tag, "xats_lflt_t") then "ldouble" else
""
//
(*
a numeric application (gint_type/gflt_type head): if the first arg is
the width text, print just the width name; "" = not numeric-special.
*)
fun
numeric_width
(name: strn, args: s2typlst): strn =
let
val giq = lx_streq(name, "gint_type")
val gfq = lx_streq(name, "gflt_type")
in
if (if giq then true else gfq)
then
(
case+ args of
| list_cons(a0, _) =>
  (
  case+ s2typ_get_node(a0) of
  | T2Ptext(tnm, _) => width_name(tnm)
  | _(*else*) => (if giq then "int" else "double"))
| list_nil() => (if giq then "int" else "double"))
else ""
end//endof[numeric_width]
//
(* ****** ****** *)
//
fun
typ_pr
(out: FILR, t2p: s2typ, d0: sint): void =
if (d0 <= 0) then pr(out, "...") else
(
case+ s2typ_get_node(t2p) of
//
| T2Pcst(s2c) =>
  pr(out, cst_friendly(symbl_get_name(s2cst_get_name(s2c))))
| T2Pvar(s2v) =>
  pr(out, symbl_get_name(s2var_get_name(s2v)))
//
| T2Plft(t1) => typ_pr(out, t1, d0-1)
| T2Pxtv(xtv) => typ_pr(out, x2t2p_get_styp(xtv), d0-1)
//
| T2Ptop0(t1) => (typ_pr(out, t1, d0-1); pr(out, "?"))
| T2Ptop1(t1) => typ_pr(out, t1, d0-1)
//
| T2Parg1(knd, t1) =>
  (
  if (knd = 1) then pr(out, "!") else
  if (knd = 0 - 1) then pr(out, "&") else ();
  typ_pr(out, t1, d0-1))
| T2Patx2(bef, aft) =>
  (typ_pr(out, bef, d0-1); pr(out, " >> "); typ_pr(out, aft, d0-1))
//
| T2Papps(tfn, args) =>
  let
  val wname =
  (
  case+ s2typ_get_node(tfn) of
  | T2Pcst(s2c) =>
    numeric_width
    (symbl_get_name(s2cst_get_name(s2c)), args)
  | _(*else*) => ""): strn
  in
  if (strn_length(wname) > 0)
  then pr(out, wname)
  else
  (
  typ_pr(out, tfn, d0-1);
  pr(out, "("); typs_pr(out, args, 0, d0-1); pr(out, ")"))
  end
| T2Plam1(s2vs, body) =>
  (
  pr(out, "lam("); vars_pr(out, s2vs, 0); pr(out, ") => ");
  typ_pr(out, body, d0-1))
//
| T2Pf2cl(fcl) => pr(out, f2cl_text(fcl))
//
| T2Pfun1(tfcl, npf, args, res) =>
  let
  val () = pr(out, "(")
  val () = funargs_pr(out, args, 0, npf, d0-1)
  val () = pr(out, ") ")
  val () =
  (
  case+ s2typ_get_node(tfcl) of
  | T2Pf2cl(fcl) => pr(out, f2cl_text(fcl))
  | _(*else*) => pr(out, "->"))
  val () = pr(out, " ")
  in
  typ_pr(out, res, d0-1)
  end
//
| T2Ptext(name, args) =>
  let
  (* the width tags and prelude heads read better friendly *)
  val w0 = width_name(name)
  val nm =
  (
  if (strn_length(w0) > 0) then w0 else
  if lx_streq(name, "xats_void_t") then "void" else
  cst_friendly(name)): strn
  in
  case+ args of
  | list_nil() => pr(out, nm)
  | list_cons(_, _) =>
    (
    pr(out, nm);
    pr(out, "("); typs_pr(out, args, 0, d0-1); pr(out, ")"))
  end
//
| T2Pexi0(s2vs, body) =>
  (
  pr(out, "["); vars_pr(out, s2vs, 0); pr(out, "] ");
  typ_pr(out, body, d0-1))
| T2Puni0(s2vs, body) =>
  (
  pr(out, "{"); vars_pr(out, s2vs, 0); pr(out, "} ");
  typ_pr(out, body, d0-1))
//
| T2Ptrcd(knd, npf, lt2ps) =>
  trcd_pr(out, knd, npf, lt2ps, d0-1)
//
| T2Pnone0() => pr(out, "_")
| T2Pnone1(t1) => typ_pr(out, t1, d0-1)
| T2Ps2exp(_) => pr(out, "_")
//
| T2Perrck(_, t1) => typ_pr(out, t1, d0-1))
//
and
typs_pr
(out: FILR, ts: s2typlst, k0: sint, d0: sint): void =
case+ ts of
| list_nil() => ()
| list_cons(t1, ts1) =>
  let
  val () = (if (k0 > 0) then pr(out, ", ") else ())
  val () = typ_pr(out, t1, d0)
  in
  typs_pr(out, ts1, k0+1, d0)
  end
//
(* function args honoring the proof separator: npf = -1 none; k>=0 bar *)
and
funargs_pr
(out: FILR, ts: s2typlst, k0: sint, npf: sint, d0: sint): void =
case+ ts of
| list_nil() =>
  (if (if npf >= 0 then (k0 = npf) else false) then pr(out, "|") else ())
| list_cons(t1, ts1) =>
  let
  val () =
  (
  if (if npf >= 0 then (k0 = npf) else false)
  then (if (k0 > 0) then pr(out, " | ") else pr(out, "| "))
  else (if (k0 > 0) then pr(out, ", ") else ()))
  val () = typ_pr(out, t1, d0)
  in
  funargs_pr(out, ts1, k0+1, npf, d0)
  end
//
and
vars_pr
(out: FILR, vs: s2varlst, k0: sint): void =
case+ vs of
| list_nil() => ()
| list_cons(v1, vs1) =>
  let
  val () = (if (k0 > 0) then pr(out, ", ") else ())
  val () = pr(out, symbl_get_name(s2var_get_name(v1)))
  in
  vars_pr(out, vs1, k0+1)
  end
//
and
trcd_pr
(out: FILR
, knd: trcdknd
, npf: sint, lt2ps: l2t2plst, d0: sint): void =
let
(* sigil by boxity; record-ness shows through the labels *)
val sig0 =
(
case+ knd of
| TRCDflt0 => "@("
| TRCDbox0 => "#("
| TRCDbox1 => "#("
| _(*box2*) => "$tuprf("): strn
val () = pr(out, sig0)
val () = ltyps_pr(out, lt2ps, 0, d0)
in
pr(out, ")")
end
//
and
ltyps_pr
(out: FILR, ls: l2t2plst, k0: sint, d0: sint): void =
case+ ls of
| list_nil() => ()
| list_cons(l1, ls1) =>
  let
  val () = (if (k0 > 0) then pr(out, ", ") else ())
  val () =
  (
  case+ l1 of
  | S2LAB(lab, t1) =>
    let
    val () =
    (
    case+ lab of
    | LABsym(sym) =>
      (pr(out, symbl_get_name(sym)); pr(out, "="))
    | _(*LABint*) => ())
    in
    typ_pr(out, t1, d0)
    end)
  in
  ltyps_pr(out, ls1, k0+1, d0)
  end
//
and
f2cl_text(fcl: f2clknd): strn =
case+ fcl of
| F2CLfun() => "->"
| F2CLclo(knd) =>
  (if (knd = 0 - 1) then "-<cloref>" else "-<cloptr>")
//
(* ****** ****** *)
(* record emission *)
(* ****** ****** *)
//
(* is loc a real span in the target file? *)
fun
loc_targetq
(loc: loctn, tgt: strn): bool =
if (postn_get_nrow(loctn_get_pbeg(loc)) < 0) then false else
(
case+ loctn_get_lsrc(loc) of
| LCSRCsome1(path) => lx_streq(path, tgt)
| LCSRCfpath(fpx) => lx_streq(fpath_get_fnm1(fpx), tgt)
| _(*none*) => false)
//
fun
span_pr
(out: FILR, loc: loctn): void =
let
val pb = loctn_get_pbeg(loc)
val pe = loctn_get_pend(loc)
val () = pn(out, postn_get_nrow(pb))
val () = pr(out, "\t")
val () = pn(out, postn_get_ncol(pb))
val () = pr(out, "\t")
val () = pn(out, postn_get_nrow(pe))
val () = pr(out, "\t")
in
pn(out, postn_get_ncol(pe))
end//endof[span_pr]
//
fun
emit_hov
(out: FILR, tgt: strn, loc: loctn, t2p: s2typ): void =
if loc_targetq(loc, tgt)
then
(
(* a typeless node ("_") is a useless hover: skip *)
case+ s2typ_get_node(t2p) of
| T2Pnone0() => ()
| _(*else*) =>
  (
  pr(out, "H\t");
  span_pr(out, loc);
  pr(out, "\t");
  typ_pr(out, t2p, 16);
  pr(out, "\n")))
else ()
//
(*
a semantic token: T \t l0 \t c0 \t l1 \t c1 \t kind — kinds are the
server legend's indices: 0 variable, 1 function, 2 enumMember
(constructor).  Single-line identifier spans only.
*)
fun
emit_tok
(out: FILR, tgt: strn, loc: loctn, knd: sint): void =
if loc_targetq(loc, tgt)
then
let
val pb = loctn_get_pbeg(loc)
val pe = loctn_get_pend(loc)
in
if (postn_get_nrow(pb) = postn_get_nrow(pe))
then
(
pr(out, "T\t");
span_pr(out, loc);
pr(out, "\t");
pn(out, knd);
pr(out, "\n"))
else ()
end
else ()
//
(* 1 (function) when the styp peels to a T2Pfun1, else 0 (variable) *)
fun
funknd_of
(t2p: s2typ, d0: sint): sint =
if (d0 <= 0) then 0 else
(
case+ s2typ_get_node(t2p) of
| T2Pfun1(_, _, _, _) => 1
| T2Puni0(_, t1) => funknd_of(t1, d0-1)
| T2Pexi0(_, t1) => funknd_of(t1, d0-1)
| T2Plft(t1) => funknd_of(t1, d0-1)
| T2Pnone1(t1) => funknd_of(t1, d0-1)
| T2Perrck(_, t1) => funknd_of(t1, d0-1)
| T2Pxtv(xtv) => funknd_of(x2t2p_get_styp(xtv), d0-1)
| _(*else*) => 0)
//
(* the definition location must itself carry a file *)
fun
emit_def
(out: FILR, tgt: strn, useloc: loctn, defloc: loctn): void =
if loc_targetq(useloc, tgt)
then
let
val dpath =
(
case+ loctn_get_lsrc(defloc) of
| LCSRCsome1(path) => path
| LCSRCfpath(fpx) => fpath_get_fnm1(fpx)
| _(*none*) => ""): strn
in
if (strn_length(dpath) <= 0) then () else
if (postn_get_nrow(loctn_get_pbeg(defloc)) < 0) then () else
(
pr(out, "D\t");
span_pr(out, useloc);
pr(out, "\t");
pr(out, dpath);
pr(out, "\t");
span_pr(out, defloc);
pr(out, "\n"))
end
else ()
//
(* ****** ****** *)
(* completion candidates (M5a) *)
(* ****** ****** *)
//
(*
candidate records (kinds: 0 variable/value, 1 function,
2 constructor, 3 type):
  P \t kind \t name                          pervasive (prelude)
  S \t kind \t dep \t name                   top-level decl (dep: 0 =
                                             the target file, 1 = a
                                             staloaded workspace dep)
  L \t kind \t sl0 \t sc0 \t sl1 \t sc1 \t name
                                             local binder, visible in
                                             the given scope span
*)
fun
ecand_p
(out: FILR, knd: sint, sym: sym_t): void =
(
pr(out, "P\t"); pn(out, knd); pr(out, "\t");
pr(out, symbl_get_name(sym)); pr(out, "\n"))
//
fun
ecand_s
(out: FILR, knd: sint, depq: sint, sym: sym_t): void =
(
pr(out, "S\t"); pn(out, knd); pr(out, "\t"); pn(out, depq);
pr(out, "\t"); pr(out, symbl_get_name(sym)); pr(out, "\n"))
//
fun
ecand_l
(out: FILR, knd: sint
, sl0: sint, sc0: sint, sl1: sint, sc1: sint, sym: sym_t): void =
(
pr(out, "L\t"); pn(out, knd); pr(out, "\t");
pn(out, sl0); pr(out, "\t"); pn(out, sc0); pr(out, "\t");
pn(out, sl1); pr(out, "\t"); pn(out, sc1); pr(out, "\t");
pr(out, symbl_get_name(sym)); pr(out, "\n"))
//
(* a top-level (scope sentinel sl0 < 0) binder is an S record *)
fun
ecand_sl
(out: FILR, knd: sint
, sl0: sint, sc0: sint, sl1: sint, sc1: sint, sym: sym_t): void =
if (sl0 < 0)
then ecand_s(out, knd, 0, sym)
else ecand_l(out, knd, sl0, sc0, sl1, sc1, sym)
//
(* ****** ****** *)
//
(*
documentSymbol records (M7): a TARGET-file top-level declaration —
  Y \t kind \t l0 \t c0 \t l1 \t c1 (name span)
    \t dl0 \t dc0 \t dl1 \t dc1 (decl span) \t name
kinds as the candidate kinds (0 value, 1 fun, 2 con, 3 type); the
server maps them to LSP SymbolKind and builds the outline in document
order.  The decl span must CONTAIN the name span (LSP requires it);
sites without a wider span pass the name span for both.
*)
fun
emit_sym
(out: FILR, tgt: strn, knd: sint
, nameloc: loctn, declloc: loctn, sym: sym_t): void =
if loc_targetq(nameloc, tgt)
then
(
pr(out, "Y\t"); pn(out, knd); pr(out, "\t");
span_pr(out, nameloc); pr(out, "\t");
span_pr(out, declloc); pr(out, "\t");
pr(out, symbl_get_name(sym)); pr(out, "\n"))
else ()
//
(* ****** ****** *)
//
(* the pervasive name environments (loaded once at prelude time) *)
fun
pv_d2itm
(out: FILR, itm: d2itm): void =
case+ itm of
| D2ITMvar(d2v) =>
  ecand_p(out, funknd_of(d2var_get_styp(d2v), 8), d2var_get_name(d2v))
| D2ITMcst(cs) =>
  (
  case+ cs of
  | list_cons(c1, _) =>
    ecand_p(out, funknd_of(d2cst_get_styp(c1), 8), d2cst_get_name(c1))
  | list_nil() => ())
| D2ITMcon(cs) =>
  (
  case+ cs of
  | list_cons(c1, _) => ecand_p(out, 2, d2con_get_name(c1))
  | list_nil() => ())
| D2ITMsym(sym, _) => ecand_p(out, 1, sym)
//
fun
pv_s2itm
(out: FILR, itm: s2itm): void =
case+ itm of
| S2ITMcst(cs) =>
  (
  case+ cs of
  | list_cons(c1, _) => ecand_p(out, 3, s2cst_get_name(c1))
  | list_nil() => ())
| _(*var/env*) => ()
//
fun
pv_dloop(out: FILR): void =
let
#typedef
dkxs = @(sint, list(d2itm))
fun
auxlst(xs: list(d2itm)): void =
case+ xs of
| list_nil() => ()
| list_cons(x1, xs1) => (pv_d2itm(out, x1); auxlst(xs1))
fun
auxloop(kxss: strm_vt(dkxs)): void =
case+ !kxss of
| ~
strmcon_vt_nil() => ()
| ~
strmcon_vt_cons(kxs1, kxss) =>
let
val (k1, xs1) = kxs1
in
(auxlst(xs1); auxloop(kxss))
end
in//let
auxloop(topmap_strmize(the_dexpenv_pvstmap()))
end//endof[pv_dloop]
//
fun
pv_sloop(out: FILR): void =
let
#typedef
skxs = @(sint, list(s2itm))
fun
auxlst(xs: list(s2itm)): void =
case+ xs of
| list_nil() => ()
| list_cons(x1, xs1) => (pv_s2itm(out, x1); auxlst(xs1))
fun
auxloop(kxss: strm_vt(skxs)): void =
case+ !kxss of
| ~
strmcon_vt_nil() => ()
| ~
strmcon_vt_cons(kxs1, kxss) =>
let
val (k1, xs1) = kxs1
in
(auxlst(xs1); auxloop(kxss))
end
in//let
auxloop(topmap_strmize(the_sexpenv_pvstmap()))
end//endof[pv_sloop]
//
fun
emit_pervasives(out: FILR): void =
(pv_dloop(out); pv_sloop(out))
//
(* ****** ****** *)
//
(* stdlib-dep filter (same rule as the tcheck01 error walk) *)
fun
lx_startsw
(s0: strn, off: sint, part: strn): bool =
let
val n0 = strn_length(s0)
val n1 = strn_length(part)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s0, off+i0) = strn_get$at(part, i0)
then loop(i0+1) else false
in//let
if off < 0 then false else
if off + n1 > n0 then false else loop(0)
end//endof[lx_startsw]
//
fun
lx_depwantq(fopt: fpathopt): bool =
case+ fopt of
| optn_nil() => true
| optn_cons(fpx) =>
  let
  val path = fpath_get_fnm1(fpx)
  val xhome = the_XATSHOME()
  val nx = strn_length(xhome)
  in
  if lx_startsw(path, 0, xhome)
  then
  (
  if lx_startsw(path, nx, "/prelude/") then false else
  if lx_startsw(path, nx, "/xatslib/") then false else true)
  else true
  end
//
(* ****** ****** *)
//
(*
top-level names of a staloaded workspace dep (an L2 decl walk).
M7: [tgt] rides along so the TARGET's own L2-routed decls (depq = 0,
the D3Cd2ecl arm) also emit Y documentSymbol records; name span
doubles as the decl span at this level.
*)
fun
s2_ysym
(out: FILR, tgt: strn, depq: sint
, knd: sint, nameloc: loctn, sym: sym_t): void =
if (depq = 0)
then emit_sym(out, tgt, knd, nameloc, nameloc, sym)
else ()
//
fun
s2_decl
(out: FILR, tgt: strn, depq: sint, d2cl: d2ecl): void =
case+ d2ecl_get_node(d2cl) of
//
| D2Cfundclst(_, _, cs, _) => s2_csts(out, tgt, depq, cs)
| D2Cdynconst(_, _, dcls) => s2_cstdcls(out, tgt, depq, dcls)
//
| D2Cdatatype(_, scs) => s2_dtcsts(out, tgt, depq, scs)
| D2Cexcptcon(_, cs) => s2_cons(out, tgt, depq, cs)
//
| D2Csexpdef(s2c, _) =>
  (
  ecand_s(out, 3, depq, s2cst_get_name(s2c));
  s2_ysym(out, tgt, depq, 3, s2cst_get_lctn(s2c), s2cst_get_name(s2c)))
| D2Cabstype(s2c, _) =>
  (
  ecand_s(out, 3, depq, s2cst_get_name(s2c));
  s2_ysym(out, tgt, depq, 3, s2cst_get_lctn(s2c), s2cst_get_name(s2c)))
| D2Cstacst0(s2c, _) =>
  (
  ecand_s(out, 3, depq, s2cst_get_name(s2c));
  s2_ysym(out, tgt, depq, 3, s2cst_get_lctn(s2c), s2cst_get_name(s2c)))
//
| D2Cstatic(_, d1) => s2_decl(out, tgt, depq, d1)
| D2Cextern(_, d1) => s2_decl(out, tgt, depq, d1)
| D2Clocal0(_, bd) => s2_decls(out, tgt, depq, bd)
//
| D2Cinclude(_, _, _, _, dopt) => s2_dclopt(out, tgt, depq, dopt)
| D2Cstaload(_, _, _, fopt2, sopt2) =>
  (
  if lx_depwantq(fopt2)
  then s2_staload(out, tgt, sopt2) else ())
//
//
| D2Cnone2(d1) => s2_decl(out, tgt, depq, d1)
| D2Cerrck(_, d1) => s2_decl(out, tgt, depq, d1)
//
| _(*else*) => ()
//
and
s2_decls
(out: FILR, tgt: strn, depq: sint, dcls: d2eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (s2_decl(out, tgt, depq, d1); s2_decls(out, tgt, depq, ds1))
//
and
s2_dclopt
(out: FILR, tgt: strn, depq: sint, dopt: d2eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => s2_decls(out, tgt, depq, dcls)
//
and
s2_csts
(out: FILR, tgt: strn, depq: sint, cs: d2cstlst): void =
case+ cs of
| list_nil() => ()
| list_cons(c1, cs1) =>
  (
  ecand_s
  (out, funknd_of(d2cst_get_styp(c1), 8), depq, d2cst_get_name(c1));
  s2_ysym
  ( out, tgt, depq, funknd_of(d2cst_get_styp(c1), 8)
  , d2cst_get_lctn(c1), d2cst_get_name(c1));
  s2_csts(out, tgt, depq, cs1))
//
and
s2_cstdcls
(out: FILR, tgt: strn, depq: sint, dcls: d2cstdclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  let
  val c1 = d2cstdcl_get_dpid(d1)
  in
  (
  ecand_s
  (out, funknd_of(d2cst_get_styp(c1), 8), depq, d2cst_get_name(c1));
  s2_ysym
  ( out, tgt, depq, funknd_of(d2cst_get_styp(c1), 8)
  , d2cst_get_lctn(c1), d2cst_get_name(c1));
  s2_cstdcls(out, tgt, depq, ds1))
  end
//
and
s2_cons
(out: FILR, tgt: strn, depq: sint, cs: d2conlst): void =
case+ cs of
| list_nil() => ()
| list_cons(c1, cs1) =>
  (
  ecand_s(out, 2, depq, d2con_get_name(c1));
  s2_ysym(out, tgt, depq, 2, d2con_get_lctn(c1), d2con_get_name(c1));
  s2_cons(out, tgt, depq, cs1))
//
and
s2_dtcsts
(out: FILR, tgt: strn, depq: sint, scs: s2cstlst): void =
case+ scs of
| list_nil() => ()
| list_cons(s1, ss1) =>
  let
  val () = ecand_s(out, 3, depq, s2cst_get_name(s1))
  val () =
  s2_ysym(out, tgt, depq, 3, s2cst_get_lctn(s1), s2cst_get_name(s1))
  val () =
  (
  case+ s2cst_get_d2cs(s1) of
  | ~
  optn_vt_nil() => ()
  | ~
  optn_vt_cons(cs) => s2_cons(out, tgt, depq, cs))
  in
  s2_dtcsts(out, tgt, depq, ss1)
  end
//
and
s2_staload
(out: FILR, tgt: strn, sopt2: s2taloadopt): void =
case+ sopt2 of
(*
M7.2: the shr flag inside a CACHED AST is frozen from its own
elaboration time — with warm deps it cannot gate this walk, or dep
candidates would vanish from completion on every warm check.  Walk
unconditionally (staloads form a DAG; the server dedups by name).
*)
| S2TALOADdpar(_(*shr: frozen*), d2p) => s2_dep(out, tgt, d2p)
| _(*none/fenv*) => ()
//
and
s2_dep
(out: FILR, tgt: strn, d2p: d2parsed): void =
s2_dclopt(out, tgt, 1, d2parsed_get_parsed(d2p))
//
(* a DATS dep's L2 twin, via the d2parenv (as tcheck01 does) *)
fun
s2_dep_find
(out: FILR, tgt: strn, fpx: fpath): void =
case+ the_d2parenv_pvsfind(fpath_get_fnm2(fpx)) of
| ~
optn_vt_nil() => ()
| ~
optn_vt_cons(d2p) => s2_dep(out, tgt, d2p)
//
(* ****** ****** *)
//
(* pattern binders -> S (top-level) or L (scoped) candidate records *)
fun
cb_pat
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, d3p: d3pat): void =
case+ d3pat_get_node(d3p) of
| D3Pvar(d2v) =>
  (
  if loc_targetq(d3pat_get_lctn(d3p), tgt)
  then
  (
  ecand_sl
  ( out, funknd_of(d2var_get_styp(d2v), 8)
  , sl0, sc0, sl1, sc1, d2var_get_name(d2v));
  (
  if (sl0 < 0)
  then
  emit_sym
  ( out, tgt, funknd_of(d2var_get_styp(d2v), 8)
  , d3pat_get_lctn(d3p), d3pat_get_lctn(d3p), d2var_get_name(d2v))
  else ()))
  else ())
| D3Pbang(p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pflat(p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pfree(p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Psapp(p1, _) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Psapq(p1, _) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Ptapq(p1, _) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pdap1(p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pdapp(p1, _, ps) =>
  (
  cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1);
  cb_pats(out, tgt, sl0, sc0, sl1, sc1, ps))
| D3Prfpt(p1, _, p2) =>
  (
  cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1);
  cb_pat(out, tgt, sl0, sc0, sl1, sc1, p2))
| D3Ptup0(_, ps) => cb_pats(out, tgt, sl0, sc0, sl1, sc1, ps)
| D3Ptup1(_, _, ps) => cb_pats(out, tgt, sl0, sc0, sl1, sc1, ps)
| D3Prcd2(_, _, lps) => cb_lpats(out, tgt, sl0, sc0, sl1, sc1, lps)
| D3Pargtp(p1, _) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pannot(p1, _, _) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pt2pck(p1, _) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Pnone2(p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3Perrck(_, p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| _(*leaves*) => ()
//
and
cb_pats
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, ps: d3patlst): void =
case+ ps of
| list_nil() => ()
| list_cons(p1, ps1) =>
  (
  cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1);
  cb_pats(out, tgt, sl0, sc0, sl1, sc1, ps1))
//
and
cb_lpats
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, ls: l3d3plst): void =
case+ ls of
| list_nil() => ()
| list_cons(l1, ls1) =>
  (
  case+ l1 of
  | D3LAB(_, p1) =>
    (
    cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1);
    cb_lpats(out, tgt, sl0, sc0, sl1, sc1, ls1)))
//
(* the binders of a f3arg list, scoped to the given span *)
fun
cb_fargs
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, fs: f3arglst): void =
case+ fs of
| list_nil() => ()
| list_cons(f1, fs1) =>
  let
  val () =
  (
  case+ f3arg_get_node(f1) of
  | F3ARGdapp(_, ps) => cb_pats(out, tgt, sl0, sc0, sl1, sc1, ps)
  | _(*sapp/mets*) => ())
  in
  cb_fargs(out, tgt, sl0, sc0, sl1, sc1, fs1)
  end
//
(* case-clause binders (guards included), scoped to the clause *)
fun
cb_gualst
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, gs: d3gualst): void =
case+ gs of
| list_nil() => ()
| list_cons(g1, gs1) =>
  let
  val () =
  (
  case+ d3gua_get_node(g1) of
  | D3GUAmat(_, p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
  | _(*exp*) => ())
  in
  cb_gualst(out, tgt, sl0, sc0, sl1, sc1, gs1)
  end
//
fun
cb_gpt
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, gpt: d3gpt): void =
case+ d3gpt_get_node(gpt) of
| D3GPTpat(p1) => cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1)
| D3GPTgua(p1, gs) =>
  (
  cb_pat(out, tgt, sl0, sc0, sl1, sc1, p1);
  cb_gualst(out, tgt, sl0, sc0, sl1, sc1, gs))
//
(* the begin/end rows+cols of a span, for scope params *)
fun
loc_r0(loc: loctn): sint = postn_get_nrow(loctn_get_pbeg(loc))
fun
loc_c0(loc: loctn): sint = postn_get_ncol(loctn_get_pbeg(loc))
fun
loc_r1(loc: loctn): sint = postn_get_nrow(loctn_get_pend(loc))
fun
loc_c1(loc: loctn): sint = postn_get_ncol(loctn_get_pend(loc))
//
(*
member (dot-completion) records: for every record/tuple-typed
expression in the target file, its field labels keyed by the
RECEIVER's span:
  M \t l0 \t c0 \t l1 \t c1 \t kind \t name
The server offers them when completion fires just after a `.` whose
position matches the span's end.
*)
fun
emit_members
(out: FILR, tgt: strn, loc: loctn, t2p: s2typ, d0: sint): void =
if (d0 <= 0) then () else
if loc_targetq(loc, tgt)
then
(
case+ s2typ_get_node(t2p) of
| T2Ptrcd(_, _, lt2ps) => mem_labels(out, loc, lt2ps)
| T2Pxtv(xtv) =>
  emit_members(out, tgt, loc, x2t2p_get_styp(xtv), d0-1)
| T2Plft(t1) => emit_members(out, tgt, loc, t1, d0-1)
| T2Ptop1(t1) => emit_members(out, tgt, loc, t1, d0-1)
| T2Pnone1(t1) => emit_members(out, tgt, loc, t1, d0-1)
| T2Perrck(_, t1) => emit_members(out, tgt, loc, t1, d0-1)
| T2Pexi0(_, t1) => emit_members(out, tgt, loc, t1, d0-1)
| T2Puni0(_, t1) => emit_members(out, tgt, loc, t1, d0-1)
| _(*else*) => ())
else ()
//
and
mem_labels
(out: FILR, loc: loctn, ls: l2t2plst): void =
case+ ls of
| list_nil() => ()
| list_cons(l1, ls1) =>
  let
  val () =
  (
  case+ l1 of
  | S2LAB(lab, _) =>
    let
    val () = pr(out, "M\t")
    val () = span_pr(out, loc)
    val () = pr(out, "\t")
    val () = pn(out, 0)
    val () = pr(out, "\t")
    val () =
    (
    case+ lab of
    | LABsym(sym) => pr(out, symbl_get_name(sym))
    | LABint(i0) => pn(out, i0))
    in
    pr(out, "\n")
    end)
  in
  mem_labels(out, loc, ls1)
  end
//
(* ****** ****** *)
(* the d3 walk *)
(* ****** ****** *)
//
fun
w_exp
(out: FILR, tgt: strn, d3e: d3exp): void =
let
val loc = d3exp_get_lctn(d3e)
val () = emit_hov(out, tgt, loc, d3exp_get_styp(d3e))
val () = emit_members(out, tgt, loc, d3exp_get_styp(d3e), 8)
in
case+ d3exp_get_node(d3e) of
//
| D3Evar(d2v) =>
  (
  emit_tok(out, tgt, loc, funknd_of(d2var_get_styp(d2v), 8));
  emit_def(out, tgt, loc, d2var_get_lctn(d2v)))
| D3Ecst(d2c) =>
  (
  emit_tok(out, tgt, loc, funknd_of(d2cst_get_styp(d2c), 8));
  emit_def(out, tgt, loc, d2cst_get_lctn(d2c)))
| D3Econ(d2c) =>
  (
  emit_tok(out, tgt, loc, 2);
  emit_def(out, tgt, loc, d2con_get_lctn(d2c)))
//
| D3Etimp(d3f, _) => w_exp(out, tgt, d3f)
| D3Etimq(d3f, _, _) => w_exp(out, tgt, d3f)
//
| D3Esapp(d3f, _) => w_exp(out, tgt, d3f)
| D3Esapq(d3f, _) => w_exp(out, tgt, d3f)
| D3Etapp(d3f, _) => w_exp(out, tgt, d3f)
| D3Etapq(d3f, _) => w_exp(out, tgt, d3f)
//
| D3Edap0(d3f) => w_exp(out, tgt, d3f)
| D3Edapp(d3f, _, args) =>
  (w_exp(out, tgt, d3f); w_explst(out, tgt, args))
//
| D3Epcon(_, _, d3f) => w_exp(out, tgt, d3f)
| D3Eproj(_, _, d3f) => w_exp(out, tgt, d3f)
//
| D3Elet0(dcls, body) =>
  (
  w_decls
  ( out, tgt
  , loc_r0(loc), loc_c0(loc), loc_r1(loc), loc_c1(loc), dcls);
  w_exp(out, tgt, body))
//
| D3Eift0(cnd, thn, els) =>
  (
  w_exp(out, tgt, cnd);
  w_expopt(out, tgt, thn); w_expopt(out, tgt, els))
//
| D3Ecas0(_, d3f, clss) =>
  (w_exp(out, tgt, d3f); w_clslst(out, tgt, clss))
//
| D3Eseqn(inis, last) =>
  (w_explst(out, tgt, inis); w_exp(out, tgt, last))
//
| D3Etup0(_, d3es) => w_explst(out, tgt, d3es)
| D3Etup1(_, _, d3es) => w_explst(out, tgt, d3es)
| D3Ercd2(_, _, lexs) => w_lexps(out, tgt, lexs)
//
| D3Elam0(_, fargs, _, _, body) =>
  (
  cb_fargs
  ( out, tgt
  , loc_r0(loc), loc_c0(loc), loc_r1(loc), loc_c1(loc), fargs);
  w_farglst(out, tgt, fargs); w_exp(out, tgt, body))
| D3Efix0(_, fid, fargs, _, _, body) =>
  let
  val () =
  (
  if loc_targetq(d2var_get_lctn(fid), tgt)
  then
  ecand_l
  ( out, 1
  , loc_r0(loc), loc_c0(loc), loc_r1(loc), loc_c1(loc)
  , d2var_get_name(fid))
  else ())
  val () =
  cb_fargs
  ( out, tgt
  , loc_r0(loc), loc_c0(loc), loc_r1(loc), loc_c1(loc), fargs)
  in
  (w_farglst(out, tgt, fargs); w_exp(out, tgt, body))
  end
//
| D3Etry0(_, body, clss) =>
  (w_exp(out, tgt, body); w_clslst(out, tgt, clss))
//
| D3Eaddr(d3f) => w_exp(out, tgt, d3f)
| D3Eview(d3f) => w_exp(out, tgt, d3f)
| D3Elval(d3f) => w_exp(out, tgt, d3f)
| D3Eflat(d3f) => w_exp(out, tgt, d3f)
| D3Eeval(d3f) => w_exp(out, tgt, d3f)
| D3Efold(d3f) => w_exp(out, tgt, d3f)
| D3Efree(d3f) => w_exp(out, tgt, d3f)
| D3Edp2tr(d3f) => w_exp(out, tgt, d3f)
| D3Edl0az(d3f) => w_exp(out, tgt, d3f)
| D3Edl1az(d3f) => w_exp(out, tgt, d3f)
| D3Edelaz(d3f) => w_exp(out, tgt, d3f)
//
| D3Ewhere(body, dcls) =>
  (
  w_exp(out, tgt, body);
  w_decls
  ( out, tgt
  , loc_r0(loc), loc_c0(loc), loc_r1(loc), loc_c1(loc), dcls))
//
| D3Eassgn(lhs, rhs) =>
  (w_exp(out, tgt, lhs); w_exp(out, tgt, rhs))
| D3Exazgn(lhs, rhs) =>
  (w_exp(out, tgt, lhs); w_exp(out, tgt, rhs))
| D3Exchng(lhs, rhs) =>
  (w_exp(out, tgt, lhs); w_exp(out, tgt, rhs))
//
| D3Eraise(_, d3f) => w_exp(out, tgt, d3f)
//
| D3El0azy(_, d3f) => w_exp(out, tgt, d3f)
| D3El1azy(_, d3f, frees) =>
  (w_exp(out, tgt, d3f); w_explst(out, tgt, frees))
| D3Eelazy(_, d3f, frees) =>
  (w_exp(out, tgt, d3f); w_explst(out, tgt, frees))
//
| D3Eannot(d3f, _, _) => w_exp(out, tgt, d3f)
| D3Elabck(d3f, _) => w_exp(out, tgt, d3f)
| D3Et2pck(d3f, _) => w_exp(out, tgt, d3f)
| D3Et2ped(d3f, _) => w_exp(out, tgt, d3f)
//
| D3Eexists(_, d3f) => w_exp(out, tgt, d3f)
//
| D3Enone2(d3f) => w_exp(out, tgt, d3f)
| D3Eerrck(_, d3f) => w_exp(out, tgt, d3f)
//
| _(*leaves: literals/top/btf/extnam/synext/none0/none1*) => ()
end//endof[w_exp]
//
and
w_explst
(out: FILR, tgt: strn, d3es: d3explst): void =
case+ d3es of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (w_exp(out, tgt, d1); w_explst(out, tgt, ds1))
//
and
w_expopt
(out: FILR, tgt: strn, opt: d3expopt): void =
case+ opt of
| optn_nil() => ()
| optn_cons(d1) => w_exp(out, tgt, d1)
//
and
w_lexps
(out: FILR, tgt: strn, ls: l3d3elst): void =
case+ ls of
| list_nil() => ()
| list_cons(l1, ls1) =>
  (
  case+ l1 of
  | D3LAB(_, d1) =>
    (w_exp(out, tgt, d1); w_lexps(out, tgt, ls1)))
//
and
w_pat
(out: FILR, tgt: strn, d3p: d3pat): void =
let
val loc = d3pat_get_lctn(d3p)
val () = emit_hov(out, tgt, loc, d3pat_get_styp(d3p))
in
case+ d3pat_get_node(d3p) of
//
| D3Pcon(d2c) =>
  (
  emit_tok(out, tgt, loc, 2);
  emit_def(out, tgt, loc, d2con_get_lctn(d2c)))
//
| D3Pvar(d2v) =>
  emit_tok(out, tgt, loc, funknd_of(d2var_get_styp(d2v), 8))
//
| D3Pbang(p1) => w_pat(out, tgt, p1)
| D3Pflat(p1) => w_pat(out, tgt, p1)
| D3Pfree(p1) => w_pat(out, tgt, p1)
//
| D3Psapp(p1, _) => w_pat(out, tgt, p1)
| D3Psapq(p1, _) => w_pat(out, tgt, p1)
| D3Ptapq(p1, _) => w_pat(out, tgt, p1)
//
| D3Pdap1(p1) => w_pat(out, tgt, p1)
| D3Pdapp(p1, _, ps) =>
  (w_pat(out, tgt, p1); w_patlst(out, tgt, ps))
//
| D3Prfpt(p1, _, p2) =>
  (w_pat(out, tgt, p1); w_pat(out, tgt, p2))
//
| D3Ptup0(_, ps) => w_patlst(out, tgt, ps)
| D3Ptup1(_, _, ps) => w_patlst(out, tgt, ps)
| D3Prcd2(_, _, lps) => w_lpats(out, tgt, lps)
//
| D3Pargtp(p1, _) => w_pat(out, tgt, p1)
| D3Pannot(p1, _, _) => w_pat(out, tgt, p1)
| D3Pt2pck(p1, _) => w_pat(out, tgt, p1)
//
| D3Pnone2(p1) => w_pat(out, tgt, p1)
| D3Perrck(_, p1) => w_pat(out, tgt, p1)
//
| _(*leaves: any/var/literals/con-decls/none0/none1*) => ()
end//endof[w_pat]
//
and
w_patlst
(out: FILR, tgt: strn, ps: d3patlst): void =
case+ ps of
| list_nil() => ()
| list_cons(p1, ps1) =>
  (w_pat(out, tgt, p1); w_patlst(out, tgt, ps1))
//
and
w_lpats
(out: FILR, tgt: strn, ls: l3d3plst): void =
case+ ls of
| list_nil() => ()
| list_cons(l1, ls1) =>
  (
  case+ l1 of
  | D3LAB(_, p1) =>
    (w_pat(out, tgt, p1); w_lpats(out, tgt, ls1)))
//
and
w_farg
(out: FILR, tgt: strn, fag: f3arg): void =
case+ f3arg_get_node(fag) of
| F3ARGdapp(_, ps) => w_patlst(out, tgt, ps)
| _(*sapp/mets*) => ()
//
and
w_farglst
(out: FILR, tgt: strn, fs: f3arglst): void =
case+ fs of
| list_nil() => ()
| list_cons(f1, fs1) =>
  (w_farg(out, tgt, f1); w_farglst(out, tgt, fs1))
//
and
w_gua
(out: FILR, tgt: strn, gua: d3gua): void =
case+ d3gua_get_node(gua) of
| D3GUAexp(d1) => w_exp(out, tgt, d1)
| D3GUAmat(d1, p1) =>
  (w_exp(out, tgt, d1); w_pat(out, tgt, p1))
//
and
w_gualst
(out: FILR, tgt: strn, gs: d3gualst): void =
case+ gs of
| list_nil() => ()
| list_cons(g1, gs1) =>
  (w_gua(out, tgt, g1); w_gualst(out, tgt, gs1))
//
and
w_gpt
(out: FILR, tgt: strn, gpt: d3gpt): void =
case+ d3gpt_get_node(gpt) of
| D3GPTpat(p1) => w_pat(out, tgt, p1)
| D3GPTgua(p1, gs) =>
  (w_pat(out, tgt, p1); w_gualst(out, tgt, gs))
//
and
w_cls
(out: FILR, tgt: strn, cls: d3cls): void =
let
val cloc = d3cls_get_lctn(cls)
in
case+ d3cls_get_node(cls) of
| D3CLSgpt(gpt) =>
  (
  cb_gpt
  ( out, tgt
  , loc_r0(cloc), loc_c0(cloc), loc_r1(cloc), loc_c1(cloc), gpt);
  w_gpt(out, tgt, gpt))
| D3CLScls(gpt, d1) =>
  (
  cb_gpt
  ( out, tgt
  , loc_r0(cloc), loc_c0(cloc), loc_r1(cloc), loc_c1(cloc), gpt);
  w_gpt(out, tgt, gpt); w_exp(out, tgt, d1))
end
//
and
w_clslst
(out: FILR, tgt: strn, cs: d3clslst): void =
case+ cs of
| list_nil() => ()
| list_cons(c1, cs1) =>
  (w_cls(out, tgt, c1); w_clslst(out, tgt, cs1))
//
and
w_tdxp
(out: FILR, tgt: strn, tdx: teqd3exp): void =
case+ tdx of
| TEQD3EXPnone() => ()
| TEQD3EXPsome(_, d1) => w_exp(out, tgt, d1)
//
and
w_valdcls
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, vds: d3valdclist): void =
case+ vds of
| list_nil() => ()
| list_cons(v1, vs1) =>
  let
  val () =
  cb_pat(out, tgt, sl0, sc0, sl1, sc1, d3valdcl_get_dpat(v1))
  val () = w_pat(out, tgt, d3valdcl_get_dpat(v1))
  val () = w_tdxp(out, tgt, d3valdcl_get_tdxp(v1))
  in
  w_valdcls(out, tgt, sl0, sc0, sl1, sc1, vs1)
  end
//
and
w_vardcls
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, vds: d3vardclist): void =
case+ vds of
| list_nil() => ()
| list_cons(v1, vs1) =>
  let
  val dpid = d3vardcl_get_dpid(v1)
  val () =
  emit_hov
  (out, tgt, d2var_get_lctn(dpid), d2var_get_styp(dpid))
  val () = emit_tok(out, tgt, d2var_get_lctn(dpid), 0)
  val () =
  (
  if loc_targetq(d2var_get_lctn(dpid), tgt)
  then ecand_sl(out, 0, sl0, sc0, sl1, sc1, d2var_get_name(dpid))
  else ())
  val () =
  (
  if (sl0 < 0)
  then
  emit_sym
  ( out, tgt, 0, d2var_get_lctn(dpid)
  , d2var_get_lctn(dpid), d2var_get_name(dpid))
  else ())
  val () = w_tdxp(out, tgt, d3vardcl_get_dini(v1))
  in
  w_vardcls(out, tgt, sl0, sc0, sl1, sc1, vs1)
  end
//
and
w_fundcls
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, fds: d3fundclist): void =
case+ fds of
| list_nil() => ()
| list_cons(f1, fs1) =>
  let
  val dpid = d3fundcl_get_dpid(f1)
  val floc = d3fundcl_get_lctn(f1)
  val () =
  emit_hov
  (out, tgt, d2var_get_lctn(dpid), d2var_get_styp(dpid))
  val () = emit_tok(out, tgt, d2var_get_lctn(dpid), 1)
  val () =
  (
  if loc_targetq(d2var_get_lctn(dpid), tgt)
  then ecand_sl(out, 1, sl0, sc0, sl1, sc1, d2var_get_name(dpid))
  else ())
  val () =
  (
  if (sl0 < 0)
  then
  emit_sym
  (out, tgt, 1, d2var_get_lctn(dpid), floc, d2var_get_name(dpid))
  else ())
  (* the args are visible throughout the fundcl *)
  val () =
  cb_fargs
  ( out, tgt
  , loc_r0(floc), loc_c0(floc), loc_r1(floc), loc_c1(floc)
  , d3fundcl_get_farg(f1))
  val () = w_farglst(out, tgt, d3fundcl_get_farg(f1))
  val () = w_tdxp(out, tgt, d3fundcl_get_tdxp(f1))
  in
  w_fundcls(out, tgt, sl0, sc0, sl1, sc1, fs1)
  end
//
and
w_decl
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, dcl: d3ecl): void =
case+ d3ecl_get_node(dcl) of
//
| D3Cstatic(_, d1) => w_decl(out, tgt, sl0, sc0, sl1, sc1, d1)
| D3Cextern(_, d1) => w_decl(out, tgt, sl0, sc0, sl1, sc1, d1)
| D3Ctmpsub(_, d1) => w_decl(out, tgt, sl0, sc0, sl1, sc1, d1)
//
| D3Cdclst0(ds) => w_decls(out, tgt, sl0, sc0, sl1, sc1, ds)
| D3Clocal0(hd, bd) =>
  (
  w_decls(out, tgt, sl0, sc0, sl1, sc1, hd);
  w_decls(out, tgt, sl0, sc0, sl1, sc1, bd))
//
| D3Cinclude(_, _, _, _, dopt) =>
  w_declopt(out, tgt, sl0, sc0, sl1, sc1, dopt)
//
| D3Cstaload(_, _, _, fopt, sopt) =>
  (
  (* completion candidates from workspace deps (kind S, dep=1) *)
  if lx_depwantq(fopt)
  then
  (
  case+ sopt of
  | S3TALOADnone(sopt2) => s2_staload(out, tgt, sopt2)
  | S3TALOADdpar(_(*shr: frozen — see s2_staload*), _) =>
    (
    case+ fopt of
    | optn_cons(fpx) => s2_dep_find(out, tgt, fpx)
    | optn_nil() => ()))
  else ())
//
| D3Cvaldclst(_, vds) =>
  w_valdcls(out, tgt, sl0, sc0, sl1, sc1, vds)
| D3Cvardclst(_, vds) =>
  w_vardcls(out, tgt, sl0, sc0, sl1, sc1, vds)
| D3Cfundclst(_, _, _, fds) =>
  w_fundcls(out, tgt, sl0, sc0, sl1, sc1, fds)
//
| D3Cimplmnt0(_, _, _, _, _, _, fargs, _, body) =>
  let
  val dloc = d3ecl_get_lctn(dcl)
  val () =
  cb_fargs
  ( out, tgt
  , loc_r0(dloc), loc_c0(dloc), loc_r1(dloc), loc_c1(dloc), fargs)
  in
  (w_farglst(out, tgt, fargs); w_exp(out, tgt, body))
  end
//
(* the target file's OWN datatype/typedef/dynconst decls ride the
   same L2 emitters as deps do, tagged dep=0 *)
| D3Cd2ecl(d2cl) => s2_decl(out, tgt, 0, d2cl)
//
| D3Ctmplocal(d1, ds) =>
  (
  w_decl(out, tgt, sl0, sc0, sl1, sc1, d1);
  w_decls(out, tgt, sl0, sc0, sl1, sc1, ds))
| D3Cimpltmpr(_, d1) => w_decl(out, tgt, sl0, sc0, sl1, sc1, d1)
//
| D3Cnone2(d1) => w_decl(out, tgt, sl0, sc0, sl1, sc1, d1)
| D3Cerrck(_, d1) => w_decl(out, tgt, sl0, sc0, sl1, sc1, d1)
//
| _(*sexpdef/abstype/absopen/absimpl/dyninit/extcode/none0/none1*) => ()
//
and
w_decls
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, ds: d3eclist): void =
case+ ds of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (
  w_decl(out, tgt, sl0, sc0, sl1, sc1, d1);
  w_decls(out, tgt, sl0, sc0, sl1, sc1, ds1))
//
and
w_declopt
(out: FILR, tgt: strn
, sl0: sint, sc0: sint, sl1: sint, sc1: sint
, dopt: d3eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(ds) => w_decls(out, tgt, sl0, sc0, sl1, sc1, ds)
//
(* ****** ****** *)
//
#implfun
lspidx_emit
(out, dpar) =
let
val tgt =
(
case+ d3parsed_get_source(dpar) of
| LCSRCsome1(path) => path
| LCSRCfpath(fpx) => fpath_get_fnm1(fpx)
| _(*none*) => ""): strn
in
if (strn_length(tgt) <= 0) then () else
let
val () = pr(out, "//==XLSPIDX-BEGIN==\n")
val () = emit_pervasives(out)
val () =
w_declopt
(out, tgt, 0 - 1, 0, 0, 0, d3parsed_get_parsed(dpar))
in
pr(out, "//==XLSPIDX-END==\n")
end
end//endof[lspidx_emit]
//
(* ****** ****** *)
(***********************************************************************)
(* end of [xats2go_lspidx.dats] *)
(***********************************************************************)
