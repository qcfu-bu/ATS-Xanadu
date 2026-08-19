(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2022 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
**
** ATS is free software;  you can  redistribute it and/or modify it under
** the terms of  the GNU GENERAL PUBLIC LICENSE (GPL) as published by the
** Free Software Foundation; either version 3, or (at  your  option)  any
** later version.
** 
** ATS is distributed in the hope that it will be useful, but WITHOUT ANY
** WARRANTY; without  even  the  implied  warranty  of MERCHANTABILITY or
** FITNESS FOR A PARTICULAR PURPOSE.  See the  GNU General Public License
** for more details.
** 
** You  should  have  received  a  copy of the GNU General Public License
** along  with  ATS;  see the  file COPYING.  If not, please write to the
** Free Software Foundation,  51 Franklin Street, Fifth Floor, Boston, MA
** 02110-1301, USA.
*)

(* ****** ****** *)
(* ****** ****** *)
//
(*
Author: Hongwei Xi
(*
Sat 27 Aug 2022 02:44:07 AM EDT
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../HATS/xatsopt_sats.hats"
#include
"./../HATS/xatsopt_dpre.hats"
//
(* ****** ****** *)
(* ****** ****** *)
#staload
_(*?*) = "./lexing0_print0.dats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
(*
#staload "./../SATS/staexp0.sats"
#staload "./../SATS/dynexp0.sats"
*)
(* ****** ****** *)
#staload "./../SATS/staexp1.sats"
#staload "./../SATS/dynexp1.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/dynexp2.sats"
(* ****** ****** *)
(* ****** ****** *)
#symload lctn with d2con_get_lctn
#symload name with d2con_get_name
#symload lctn with d2cst_get_lctn
#symload name with d2cst_get_name
(* ****** ****** *)
#symload lctn with d2pat_get_lctn
#symload node with d2pat_get_node
#symload styp with d2pat_get_styp
(* ****** ****** *)
#symload lctn with d2exp_get_lctn
#symload node with d2exp_get_node
#symload styp with d2exp_get_styp
(* ****** ****** *)
#symload lctn with f2arg_get_lctn
#symload node with f2arg_get_node
(* ****** ****** *)
#symload lctn with d2gua_get_lctn
#symload lctn with d2gpt_get_lctn
#symload lctn with d2cls_get_lctn
#symload node with d2gua_get_node
#symload node with d2gpt_get_node
#symload node with d2cls_get_node
(* ****** ****** *)
#symload lctn with d2ecl_get_lctn
#symload node with d2ecl_get_node
(* ****** ****** *)
#symload lctn with simpl_get_lctn
#symload node with simpl_get_node
#symload lctn with dimpl_get_lctn
#symload node with dimpl_get_node
(* ****** ****** *)
#symload lctn with d2arg_get_lctn
#symload node with d2arg_get_node
(* ****** ****** *)
#symload dpat with d2rpt_get_dpat
#symload dexp with d2rxp_get_dexp
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
x2nam_fprint
(xnam, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
in//let
case+ xnam of
|
X2NAMnone() =>
(
  (print("X2NAMnone("); print(")")))
|
X2NAMsome(dexp) =>
(
  (print("X2NAMsome("); print(dexp); print(")")))
end(*let*)//end-of-[x2nam_fprint(xnam,out0)]
//
(* ****** ****** *)
//
#implfun
d2con_fprint
(d2c0, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
val
sym0 = d2con_get_name(d2c0)
val
stmp = d2con_get_stmp(d2c0)
//
in//let
(
  (print(sym0); print("("); print(stmp); print(")")))
end(*let*)//end-of-[d2con_fprint(d2c0,out0)]
//
(* ****** ****** *)
//
#implfun
d2cst_fprint
(d2c0, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
val
sym0 = d2cst_get_name(d2c0)
val
stmp = d2cst_get_stmp(d2c0)
//
in//let
(
  (print(sym0); print("("); print(stmp); print(")")))
end(*let*)//end-of-[d2cst_fprint(d2c0,out0)]
//
(* ****** ****** *)
//
#implfun
d2var_fprint
(d2v0, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
val
sym0 = d2var_get_name(d2v0)
val
stmp = d2var_get_stmp(d2v0)
//
in//let
(
  (print(sym0); print("("); print(stmp); print(")")))
end(*let*)//end-of-[d2var_fprint(d2v0,out0)]
//
(* ****** ****** *)
//
#implfun
d2pat_fprint
(d2p0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
d2p0.node() of
//
|D2Pnil() =>
(print("D2Pnil("); print(")"))
|D2Pany() =>
(print("D2Pany("); print(")"))
|D2Parg() =>
(print("D2Parg("); print(")"))
//
|D2Pvar(d2v) =>
(print("D2Pvar("); print(d2v); print(")"))
//
|D2Pint(tok) =>
(print("D2Pint("); print(tok); print(")"))
|D2Pbtf(sym) =>
(print("D2Pbtf("); print(sym); print(")"))
|D2Pchr(tok) =>
(print("D2Pchr("); print(tok); print(")"))
|D2Pflt(tok) =>
(print("D2Pflt("); print(tok); print(")"))
|D2Pstr(tok) =>
(print("D2Pstr("); print(tok); print(")"))
//
|D2Pi00(int) =>
(print("D2Pi00("); print(int); print(")"))
|D2Pb00(btf) =>
(print("D2Pb00("); print(btf); print(")"))
|D2Pc00(chr) =>
(print("D2Pc00("); print(chr); print(")"))
|D2Pf00(flt) =>
(print("D2Pf00("); print(flt); print(")"))
|D2Ps00(str) =>
(print("D2Ps00("); print(str); print(")"))
//
|D2Pcon(d2c) =>
(print("D2Pcon("); print(d2c); print(")"))
//
|D2Pbang(d2p1) =>
(print("D2Pbang("); print(d2p1); print(")"))
|D2Pflat(d2p1) =>
(print("D2Pflat("); print(d2p1); print(")"))
|D2Pfree(d2p1) =>
(print("D2Pfree("); print(d2p1); print(")"))
//
(*
|
D2Psym0
(drpt,
 d1p1, dpis) =>
prints
( "D2Psym0("
, drpt,";",d1p1,";",dpis,")" )
*)
//
|
D2Pcons
(drpt, d2cs) =>
(print("D2Pcons("); print(drpt); print(";"); print(d2cs); print(")"))
//
|
D2Psapp
(d2f0, s2vs) =>
(print("D2Psapp("); print(d2f0); print(";"); print(s2vs); print(")"))
//
|
D2Pdap0(d1p1) =>
((print("D2Pdap0("); print(d1p1); print(")")))
|
D2Pdap1(d1p1) =>
((print("D2Pdap1("); print(d1p1); print(")")))
//
|
D2Pdapp
( d2f0
, npf1, d2ps) =>
(
print("D2Pdapp(");
(print(d2f0); print(";"); print(npf1); print(";"); print(d2ps); print(")")))
//
|
D2Prfpt
( d2p1
, tknd, d2p2) =>
(
print("D2Prfpt(");
(print(d2p1); print(";"); print(tknd); print(";"); print(d2p2); print(")")))
//
|
D2Ptup0
( npf1, d2ps) =>
(print("D2Ptup0("); print(npf1); print(";"); print(d2ps); print(")"))
|
D2Ptup1
( tknd
, npf1, d2ps) =>
( print("D2Ptup1(")
; (print(tknd); print(";"); print(npf1); print(";"); print(d2ps); print(")")))
|
D2Prcd2
( tknd
, npf1, ldps) =>
( print("D2Prcd2(")
; (print(tknd); print(";"); print(npf1); print(";"); print(ldps); print(")")))
//
|
D2Pargtp
( d2p1, t2p2) =>
(
(print("D2Pargtp("); print(d2p1); print(";"); print(t2p2); print(")")))
|
D2Pannot
( d2p1
, s1e2, s2e2) =>
( print("D2Pannot(")
; (print(d2p1); print(";"); print(s1e2); print(";"); print(s2e2); print(")")))
//
|D2Pg1mac
 (   g1m1   ) =>
(
 (print("D2Pg1mac("); print(g1m1); print(")")))//D2Pg1mac
//
|D2Pt2pck
( d2p1 , t2p2 ) =>
let
val
t2p1 = d2p1.styp() in
( print("D2Pt2pck(")
; (print(d2p1); print(";"); print(t2p1); print(";"); print(t2p2); print(")")))
endlet // end of [ D2Pt2pck(d2p1, t2p2) ]
//
|D2Pt2pkc
( d2p1 , t2p2 ) =>
let
val
t2p1 = d2p1.styp() in
( print("D2Pt2pkc(")
; (print(d2p1); print(";"); print(t2p1); print(";"); print(t2p2); print(")")))
endlet // end of [ D2Pt2pkc(d2p1, t2p2) ]
//
|D2Pnone0() => (print("D2Pnone0("); print(")"))
|D2Pnone1(d1p1) => (print("D2Pnone1("); print(d1p1); print(")"))
|D2Pnone2(d2p1) => (print("D2Pnone2("); print(d2p1); print(")"))
//
(* ****** ****** *)
//
(*
HX-2025-12-31:
Wed Dec 31 06:05:30 PM EST 2025
*)
//
|
D2Perrck // HX: generated 
( lvl1, d2p2) => // by [tread12]
if // if
(lvl1 >= 2)
then
(
  (print("D2Perrck("); print(lvl1); print(";"); print(d2p2); print(")")))
else // (lvl1<=1)
let
val loc0 = d2p0.lctn() in//let
(
  (print("D2Perrck("); print(loc0); print(";"); print(lvl1); print(";"); print(d2p2); print(")")))
end (*let*) // end-of-[ D2Perrck(lvl1,d2p2) ]
//
end (*let*) // end-of-[ d2pat_fprint(d2p0,out0) ]
//
(* ****** ****** *)
//
#implfun
d2rpt_fprint
(drpt, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
  (print("D2RPT("); print(drpt.dpat()); print(")"))
end (*let*) // end of [ d2rpt_fprint(drpt,out0) ]
//
(* ****** ****** *)
//
#implfun
d2exp_fprint
(d2e0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
d2e0.node() of
//
|D2Eint(tok) =>
(print("D2Eint("); print(tok); print(")"))
|D2Ebtf(sym) =>
(print("D2Ebtf("); print(sym); print(")"))
|D2Echr(tok) =>
(print("D2Echr("); print(tok); print(")"))
|D2Eflt(tok) =>
(print("D2Eflt("); print(tok); print(")"))
|D2Estr(tok) =>
(print("D2Estr("); print(tok); print(")"))
//
|D2Ei00(int) =>
(print("D2Ei00("); print(int); print(")"))
|D2Eb00(btf) =>
(print("D2Eb00("); print(btf); print(")"))
|D2Ec00(chr) =>
(print("D2Ec00("); print(chr); print(")"))
|D2Ef00(flt) =>
(print("D2Ef00("); print(flt); print(")"))
|D2Es00(str) =>
(print("D2Es00("); print(str); print(")"))
//
|D2Etop(sym) =>
(print("D2Etop("); print(sym); print(")"))
//
(* ****** ****** *)
//
|D2Evar(d2v) =>
(print("D2Evar("); print(d2v); print(")"))
//
|D2Econ(d2c) =>
(print("D2Econ("); print(d2c); print(")"))
|D2Ecst(d2c) =>
(print("D2Ecst("); print(d2c); print(")"))
//
(* ****** ****** *)
//
|
D2Econs(d2cs) =>
(
(print("D2Econs("); print(d2cs); print(")")))
where
{
#impltmp
g_print<d2con>(x) =
(print(x.name()); print("("); print(x.lctn()); print(")")) }
|
D2Ecsts(d2cs) =>
(
(print("D2Ecsts("); print(d2cs); print(")")))
where
{
#impltmp
g_print<d2cst>(x) =
(print(x.name()); print("("); print(x.lctn()); print(")")) }
//
(* ****** ****** *)
//
|
D2Esym0
( drxp
, d1e1, dpis) =>
(print("D2Esym0("); print(drxp); print(";"); print(d1e1); print(";"); print(dpis); print(")"))
//
(* ****** ****** *)
//
|
D2Esapp
( d2e1, s2es) =>
(print("D2Esapp("); print(d2e1); print(";"); print(s2es); print(")"))
|
D2Etapp
( d2e1, s2es) =>
(print("D2Etapp("); print(d2e1); print(";"); print(s2es); print(")"))
//
(* ****** ****** *)
//
|
D2Edap0(d2f0) =>
(print("D2Edap0("); print(d2f0); print(")"))
|
D2Edapp
( d2f0
, npf1, d2es) =>
( print("D2Edapp(")
; (print(d2f0); print(";"); print(npf1); print(";"); print(d2es); print(")")))
//
(* ****** ****** *)
//
|
D2Eproj
( tknd
, drxp
, dlab, dtup) =>
( (print("D2Eproj("); print(tknd); print(";"))
; (print(drxp); print(";"); print(dlab); print(";"); print(dtup); print(")")))
//
(* ****** ****** *)
//
|
D2Elet0
( dcls, d2e1) =>
(
(print("D2Elet0("); print(dcls); print(";"); print(d2e1); print(")")))
//
(* ****** ****** *)
//
|D2Eift0
( d2e1
, dthn, dels) =>
( print("D2Eift0(")
; (print(d2e1); print(";"); print(dthn); print(";"); print(dels); print(")")))
//
|
D2Ecas0
( tknd
, d2e1, d2cs) =>
( print("D2Ecas0(");
  (print(tknd); print(";"); print(d2e1); print(";"); print(d2cs); print(")")))
//
(* ****** ****** *)
//
|D2Eseqn
( d2es, d2e1) =>
(
(print("D2Eseqn("); print(d2es); print(";"); print(d2e1); print(")")))
//
(* ****** ****** *)
//
|D2Etup0
( npf1, d2es) =>
(
(print("D2Etup0("); print(npf1); print(";"); print(d2es); print(")")))
(*
|D2Ercd0
(npf1, ldes) =>
(
prints("D2Ercd0(",npf1,";",ldes,")"))
*)
//
|
D2Etup1
( tknd
, npf1, d2es) =>
( print("D2Etup1(")
; (print(tknd); print(";"); print(npf1); print(";"); print(d2es); print(")")) )
|
D2Ercd2
( tknd
, npf1, ldes) =>
( print("D2Ercd2(")
; (print(tknd); print(";"); print(npf1); print(";"); print(ldes); print(")")) )
//
(* ****** ****** *)
//
|
D2Elam0
( tknd
, f2as, sres
, arrw, body) =>
(
(print("D2Elam0("); print(tknd); print(";"));
(print(f2as); print(";"); print(sres); print(";"); print(arrw); print(";"); print(body); print(")")))
//
|
D2Efix0
( tknd
, dpid
, f2as, sres
, arrw, body) =>
(
(print("D2Efix0("); print(tknd); print(";"); print(dpid); print(";"));
(print(f2as); print(";"); print(sres); print(";"); print(arrw); print(";"); print(body); print(")")))
//
(* ****** ****** *)
//
|
D2Etry0
( tknd
, d2e1, dcls) =>
(
print("D2Etry0(");
(print(tknd); print(";"); print(d2e1); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
//
|
D2Eaddr(d2e1) =>
(
  (print("D2Eaddr("); print(d2e1); print(")")))
|
D2Eview(d2e1) =>
(
  (print("D2Eview("); print(d2e1); print(")")))
|
D2Elval(d2e1) =>
(
  (print("D2Elval("); print(d2e1); print(")")))
//
|
D2Eeval(d2e1) =>
(
  (print("D2Eeval("); print(d2e1); print(")")))
//
|
D2Efold(d2e1) =>
(
  (print("D2Efold("); print(d2e1); print(")")))
|
D2Efree(d2e1) =>
(
  (print("D2Efree("); print(d2e1); print(")")))
//
|
D2Ewhere
( d2e1, dcls) =>
(
(print("D2Ewhere("); print(d2e1); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
|
D2Eassgn
( d2el, d2er) =>
(
(print("D2Eassgn("); print(d2el); print(";"); print(d2er); print(")")))
//
|
D2Exazgn
( d2el, d2er) =>
(
(print("D2Exazgn("); print(d2el); print(";"); print(d2er); print(")")))
//
|
D2Exchng
( d2el, d2er) =>
(
(print("D2Exchng("); print(d2el); print(";"); print(d2er); print(")")))
//
(* ****** ****** *)
//
|
D2Ebrget
( dpis, d2es) =>
(
(print("D2Ebrget("); print(dpis); print(";"); print(d2es); print(")")))
|
D2Ebrset
( dpis, d2es) =>
(
(print("D2Ebrset("); print(dpis); print(";"); print(d2es); print(")")))
//
(* ****** ****** *)
|
D2Edtsel
( tknd
, lab1, dpis
, npf1, opt2) =>
(
print("D2Edtsel(");
(print(tknd); print(";"); print(lab1); print(";"));
(print(dpis); print(";"); print(npf1); print(";"); print(opt2); print(")")))
//
(* ****** ****** *)
//
|
D2Eraise
( tknd, d2e1) =>
(
(print("D2Eraise("); print(tknd); print(";"); print(d2e1); print(")")))
//
(* ****** ****** *)
//
|
D2El0azy
( dsym, d2e1) =>
(
(print("D2El0azy("); print(dsym); print(";"); print(d2e1); print(")")))
|
D2El1azy
( dsym
, d2e1, d2es) =>
(
print("D2El1azy(");
(print(dsym); print(";"); print(d2e1); print(";"); print(d2es); print(")")))
|
D2Eelazy
( dsym
, d2e1, d2es) =>
(
print("D2Eelazy(");
(print(dsym); print(";"); print(d2e1); print(";"); print(d2es); print(")")))
//
(* ****** ****** *)
//
|
D2Eannot
( d2e1
, s1e2, s2e2) =>
(
print("D2Eannot(");
(print(d2e1); print(";"); print(s1e2); print(";"); print(s2e2); print(")")))
//
(* ****** ****** *)
//
|D2Eg1mac
(    g1m1    ) =>
(
(print("D2Eg1mac("); print(g1m1); print(")")))//D2Eg1mac
//
(* ****** ****** *)
//
|D2Elabck
( d2e1, lab2 ) =>
let
val
t2p1 = d2e1.styp() in
(
print("D2Elabck(");
(print(d2e1); print(";"); print(t2p1); print(";"); print(lab2); print(")")))
endlet // end of [D2Elabck(d2e1, lab2)]
//
|D2Et2pck
( d2e1, t2p2 ) =>
let
val
t2p1 = d2e1.styp() in
(
print("D2Et2pck(");
(print(d2e1); print(";"); print(t2p1); print(";"); print(t2p2); print(")")))
endlet // end of [D2Et2pck(d2e1, t2p2)]
|D2Et2ped
( d2e1, t2p2 ) =>
let
val
t2p1 = d2e1.styp() in
(
print("D2Et2ped(");
(print(d2e1); print(";"); print(t2p1); print(";"); print(t2p2); print(")")))
endlet // end of [D2Et2ped(d2e1, t2p2)]
//
(* ****** ****** *)
//
|
D2Eexists
( s2es, d2e1) =>
(
(print("D2Eexists("); print(s2es); print(";"); print(d2e1); print(")")))
//
(* ****** ****** *)
//
|
D2Eextnam
( tknd, gnam) =>
(
(print("D2Eextnam("); print(tknd); print(";"); print(gnam); print(")")))
//
|
D2Esynext
( tknd, gexp) =>
(
(print("D2Esynext("); print(tknd); print(";"); print(gexp); print(")")))
//
(* ****** ****** *)
//
|D2Enone0() => (print("D2Enone0("); print(")"))
|D2Enone1(d1e1) => (print("D2Enone1("); print(d1e1); print(")"))
|D2Enone2(d2e1) => (print("D2Enone2("); print(d2e1); print(")"))
//
(* ****** ****** *)
//
(*
HX-2025-12-31:
Wed Dec 31 06:05:30 PM EST 2025
*)
//
|
D2Eerrck // HX: generated
( lvl1, d2e2) => // by [tread12]
if // if
(lvl1 >= 2)
then
(print("D2Eerrck("); print(lvl1); print(";"); print(d2e2); print(")"))
else // (lvl1<=1)
let
val loc0 = d2e0.lctn() in//let
(
  (print("D2Eerrck("); print(loc0); print(";"); print(lvl1); print(";"); print(d2e2); print(")")))
end (*let*) // end-of-[D2Eerrck(lvl1,d2e2)]
//
(* ****** ****** *)
//
end (*let*) // end-of-[ d2exp_fprint(d2e0,out0) ]
//
(* ****** ****** *)
//
#implfun
d2rxp_fprint
(drxp, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
(
  (print("D2RXP("); print(drxp.dexp()); print(")")))
end (*let*) // end of [ d2rxp_fprint(drxp,out0) ]
//
(* ****** ****** *)
//
#implfun
f2arg_fprint
(farg, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
farg.node() of
//
|
F2ARGdapp
(npf1, d2ps) =>
(print("F2ARGdapp("); print(npf1); print(";"); print(d2ps); print(")"))
//
|
F2ARGsapp
(s2vs, s2ps) =>
(print("F2ARGsapp("); print(s2vs); print(";"); print(s2ps); print(")"))
|
F2ARGmets
(   s2es   ) => (print("F2ARGmets("); print(s2es); print(")"))
//
end (*let*) // end of [ f2arg_fprint(farg,out0) ]
//
(* ****** ****** *)
//
#implfun
d2gua_fprint
(dgua, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
dgua.node() of
|
D2GUAexp(d2e1) =>
(print("D2GUAexp("); print(d2e1); print(")"))
|
D2GUAmat(d2e1,d2p2) =>
(print("D2GUAmat("); print(d2e1); print(";"); print(d2p2); print(")"))
//
end (*let*) // end of [ d2gua_fprint(dgua,out0) ]
//
(* ****** ****** *)
//
#implfun
d2gpt_fprint
(dgpt, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
case+
dgpt.node() of
|
D2GPTpat(d2p1) =>
(print("D2GPTpat("); print(d2p1); print(")"))
|
D2GPTgua(d2p1,d2gs) =>
(print("D2GPTgua("); print(d2p1); print(";"); print(d2gs); print(")"))
end (*let*) // end of [ d2gpt_fprint(dgpt,out0) ]
//
#implfun
d2cls_fprint
(dcls, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
case+
dcls.node() of
|
D2CLSgpt(dgpt) =>
(print("D2CLSgpt("); print(dgpt); print(")"))
|
D2CLScls(d2g1,d2e2) =>
(print("D2CLScls("); print(d2g1); print(";"); print(d2e2); print(")"))
end (*let*) // end of [ d2cls_fprint(dcls,out0) ]
//
(* ****** ****** *)
//
#implfun
d2itm_fprint
(d2i0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+ d2i0 of
//
|
D2ITMvar(d2v1) =>
(print("D2ITMvar("); print(d2v1); print(")"))
|
D2ITMcon(d2cs) =>
(print("D2ITMcon("); print(d2cs); print(")"))
|
D2ITMcst(d2cs) =>
(print("D2ITMcst("); print(d2cs); print(")"))
|
D2ITMsym(sym1, d2ps) =>
(print("D2ITMsym("); print(sym1); print(";"); print(d2ps); print(")"))
//
end (*let*) // end of [ d2itm_fprint(d2i0,out0) ]
//
(* ****** ****** *)
//
#implfun
d2ptm_fprint
(dptm, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+ dptm of
|
D2PTMnone(dqid) =>
(print("D2PTMnone("); print(dqid); print(")"))
|
D2PTMsome(pval, d2i1) =>
(print("D2PTMsome("); print(pval); print(";"); print(d2i1); print(")"))
//
end (*let*) // end of [ d2ptm_fprint(dptm,out0) ]
//
(* ****** ****** *)
//
#implfun
d2ecl_fprint
(dcl0, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
in//let
//
case+
dcl0.node() of
//
|D2Cd1ecl
(  d1cl  ) =>
(print("D2Cd1ecl("); print(d1cl); print(")"))
//
(* ****** ****** *)
|
D2Cstatic
( tknd , dcl1 ) =>
(print("D2Cstatic("); print(tknd); print(";"); print(dcl1); print(")"))
|
D2Cextern
( tknd , dcl1 ) =>
(print("D2Cextern("); print(tknd); print(";"); print(dcl1); print(")"))
//
(* ****** ****** *)
//
|
D2Clocal0
( head , body ) =>
(print("D2Clocal("); print(head); print(";"); print(body); print(")"))
//
|
D2Cabssort
(  tid0  ) =>
(print("D2Cabssort("); print(tid0); print(")"))
//
|
D2Cstacst0
( s2c1 , s2t2 ) =>
(print("D2Cstacst0("); print(s2c1); print(";"); print(s2t2); print(")"))
//
|
D2Csortdef
( tid1 , s2tx ) =>
(print("D2Csortdef("); print(tid1); print(";"); print(s2tx); print(")"))
//
|
D2Csexpdef
( s2c1 , s2e2 ) =>
(print("D2Csexpdef("); print(s2c1); print(";"); print(s2e2); print(")"))
//
|
D2Cabstype
( s2c1 , atdf ) =>
(print("D2Cabstype("); print(s2c1); print(";"); print(atdf); print(")"))
//
|
D2Cabsopen
( tknd , simp ) =>
(print("D2Cabsopen("); print(tknd); print(";"); print(simp); print(")"))
|
D2Cabsimpl
(tknd,simp,sdef) =>
( print("D2Cabsimpl(")
; (print(tknd); print(";"); print(simp); print(";"); print(sdef); print(")")))
//
|
D2Csymload
(tknd,sym0,dptm) =>
( print("D2Csymload(")
; (print(tknd); print(";"); print(sym0); print(";"); print(dptm); print(")")))
//
|
D2Cinclude
(knd0,tknd
,gsrc,fopt,dopt) =>
(
print("D2Cinclude(");
(print(knd0); print(";"); print(tknd); print(";"); print(gsrc); print(";"); print(fopt); print(";"); print(dopt); print(")")))
//
|
D2Cstaload
(knd0,tknd
,gsrc,fopt,dopt) =>
(
print("D2Cstaload(");
(print(knd0); print(";"); print(tknd); print(";"); print(gsrc); print(";"); print(fopt); print(";"); print("..."); print(")")))
//
(* ****** ****** *)
//
(*
HX-2024-07-20:
Sat 20 Jul 2024 01:33:42 PM EDT
*)
//
|
D2Cdyninit(tknd,g1e1) =>
(
(print("D2Cdyninit("); print(tknd); print(";"); print(g1e1); print(")")))
|
D2Cextcode(tknd,g1e1) =>
(
(print("D2Cextcode("); print(tknd); print(";"); print(g1e1); print(")")))
//
(* ****** ****** *)
//
|
D2Cdatasort
( d1cl , s2cs ) =>
(print("D2Cdatasort("); print(d1cl); print(";"); print(s2cs); print(")"))
//
|
D2Cvaldclst
( tknd , d2vs ) =>
(print("D2Cvaldclst("); print(tknd); print(";"); print(d2vs); print(")"))
|
D2Cvardclst
( tknd , d2vs ) =>
(print("D2Cvardclst("); print(tknd); print(";"); print(d2vs); print(")"))
//
|
D2Cfundclst
(tknd
,tqas,d2cs,d2fs) =>
(
print("D2Cfundclst(");
(print(tknd); print(";"); print(tqas); print(";"); print(d2cs); print(";"); print(d2fs); print(")")))
//
|
D2Cimplmnt0
(tknd
,sqas,tqas
,dqid,tias
,farg,sres,body) =>
(
print("D2Cimplmnt0(");
(print(tknd); print(";"); print(sqas); print(";"); print(tqas); print(";"));
(print(dqid); print(";"); print(tias); print(";"); print(farg); print(";"); print(sres); print(";"); print(body); print(")")))
(*
|
D2Cimplmnt1
(tknd
,sqas,tqas
,dqid,tias
,farg,sres,body) =>
(
print("D2Cimplmnt1(");
prints(tknd,";",sqas,";",tqas,";");
prints(dqid,";",tias,";",farg,";",sres,";",body,")"))
*)
//
|
D2Cexcptcon
( d1cl , d2cs ) =>
(print("D2Cexcptcon("); print(d1cl); print(";"); print(d2cs); print(")"))
|
D2Cdatatype
( d1cl , s2cs ) =>
(print("D2Cdatatype("); print(d1cl); print(";"); print(s2cs); print(")"))
//
|
D2Cdynconst
(tknd,tqas,d2cs) =>
(print("D2Cdynconst("); print(tknd); print(";"); print(tqas); print(";"); print(d2cs); print(")"))
//
(* ****** ****** *)
//
|
D2Cnone0((*0*)) => (print("D2Cnone0("); print(")"))
//
|D2Cnone1(d1cl) => (print("D2Cnone1("); print(d1cl); print(")"))
|D2Cnone2(d2cl) => (print("D2Cnone2("); print(d2cl); print(")"))
//
(* ****** ****** *)
//
(*
HX-2025-04-20: for if-guarded declarations!
*)
|D2Cthen0(dcls) => (print("D2Cthen0("); print(dcls); print(")"))
|D2Celse1(dcls) => (print("D2Celse1("); print(dcls); print(")"))
//
(* ****** ****** *)
//
(*
HX-2025-12-31:
Wed Dec 31 06:05:30 PM EST 2025
*)
//
|
D2Cerrck // HX: generated by
( lvl1, d2cl) => // by [tread23]
if // if
(lvl1 >= 2)
then
(
  (print("D2Cerrck("); print(lvl1); print(";"); print(d2cl); print(")")))
else // (lvl1<=1)
let
val loc0 = dcl0.lctn() in//let
(
  (print("D2Cerrck("); print(loc0); print(";"); print(lvl1); print(";"); print(d2cl); print(")")))
end (*let*) // end-of-[ D2Cerrck(lvl1,d2cl) ]
//
end (*let*) // end of [ d2ecl_fprint(dcl0,out0) ]
//
(* ****** ****** *)
//
#implfun
s2qag_fprint
(sqag, out0) =
let
#impltmp
g_print$out<>() = out0
in//in-of-let
  (print("S2QAG("); print(sqag.s2vs()); print(")"))
end (*let*) // end of [ s2qag_fprint(sqag,out0) ]
//
(* ****** ****** *)
//
#implfun
t2qag_fprint
(tqag, out0) =
let
#impltmp
g_print$out<>() = out0
in//in-of-let
  (print("T2QAG("); print(tqag.s2vs()); print(")"))
end (*let*) // end of [ t2qag_fprint(tqag,out0) ]
//
(* ****** ****** *)
//
#implfun
t2iag_fprint
(tiag, out0) =
let
#impltmp
g_print$out<>() = out0
in//in-of-let
  (print("T2IAG("); print(tiag.s2es()); print(")"))
end (*let*) // end of [ t2iag_fprint(tiag,out0) ]
//
(* ****** ****** *)
//
#implfun
t2jag_fprint
(tjag, out0) =
let
#impltmp
g_print$out<>() = out0
in//in-of-let
  (print("T2JAG("); print(tjag.t2ps()); print(")"))
end (*let*) // end of [ t2jag_fprint(tjag,out0) ]
//
(* ****** ****** *)
//
#implfun
a2tdf_fprint
(atdf, out0) =
let
#impltmp
g_print$out<>() = out0
//
in//let
//
case+ atdf of
|
A2TDFsome() =>
(print("A2TDFsome("); print(")"))
|
A2TDFlteq(s2e1) =>
(print("A2TDFlteq("); print(s2e1); print(")"))
|
A2TDFeqeq(s2e1) =>
(print("A2TDFeqeq("); print(s2e1); print(")"))
|
A2TDFdefn(s2e1) =>
(print("A2TDFdefn("); print(s2e1); print(")"))
//
end (*let*) // end-of-[ a2tdf_fprint(atdf,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
s2eff_fprint
(seff, out0) =
let
#implfun
g_print$out<>() = out0
in//let
case+ seff of
|
S2EFFnone() =>
(
  (print("S2EFFnone("); print(")")))
|
S2EFFsome(s2fs) =>
(
  (print("S2EFFsome("); print(s2fs); print(")")))
end (*let*) // end-of-[ s2eff_fprint(seff,out0) ]
//
(* ****** ****** *)
//
#implfun
s2res_fprint
(sres, out0) =
let
#implfun
g_print$out<>() = out0
in//let
case+ sres of
|
S2RESnone() =>
(print("S2RESnone("); print(")"))
|
S2RESsome(seff, s2e1) =>
(print("S2RESsome("); print(seff); print(";"); print(s2e1); print(")"))
end (*let*) // end-of-[ s2res_fprint(sres,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
simpl_fprint
(simp, out0) =
let
#implfun
g_print$out<>() = out0
in//let
case+
simp.node() of
|
SIMPLone1(s2c1) =>
(print("SIMPLone1("); print(s2c1); print(")"))
|
SIMPLall1
(sqid,s2cs) =>
(print("SIMPLall1("); print(sqid); print(";"); print(s2cs); print(")"))
|
SIMPLopt2
(sqid,scs1,scs2) =>
(print("SIMPLopt2("); print(sqid); print(";"); print(scs1); print(";"); print(scs2); print(")"))
end (*let*) // end of [ simpl_fprint(simp,out0) ]
//
(* ****** ****** *)
//
#implfun
dimpl_fprint
(dimp, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
in//let
//
case+
dimp.node() of
|DIMPLnon1
(  dqid  ) =>
(
  (print("DIMPLnon1("); print(dqid); print(")")))
|DIMPLone1
(  d2c1  ) =>
(
  (print("DIMPLone1("); print(d2c1); print(")")))
|
DIMPLone2
(d2c1, svts) =>
( (print("DIMPLone2("); print(d2c1); print(";"); print(svts); print(")")))
//
end (*let*) // end-of-[ dimpl_fprint(dimp,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d2arg_fprint
(darg, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case
darg.node() of
| // dpid:s2exp
D2ARGdyn1
(   dpid   ) =>
(print("D2ARGdyn1("); print(dpid); print(")"))
|
D2ARGdyn2
(npf1, s2es) =>
(print("D2ARGdyn2("); print(npf1); print(";"); print(s2es); print(")"))
//
|
D2ARGsta0
(s2vs, s2ps) =>
(print("D2ARGsta0("); print(s2vs); print(";"); print(s2ps); print(")"))
//
end (*let*) // end-of-[ d2arg_fprint(darg,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d2valdcl_fprint
 (dval, out0) = let
//
val dpat =
d2valdcl_get_dpat(dval)
val tdxp =
d2valdcl_get_tdxp(dval)
val wsxp =
d2valdcl_get_wsxp(dval)
//
#impltmp
g_print$out<>() = (  out0  )
//
in//let
(
(print("D2VALDCL("); print(dpat); print(";"); print(tdxp); print(";"); print(wsxp); print(")")))
end (*let*) // end-of-[d2valdcl_fprint(dval,out0)]
//
(* ****** ****** *)
//
#implfun
d2vardcl_fprint
 (dvar, out0) = let
//
val dpid =
d2vardcl_get_dpid(dvar)
val vpid =
d2vardcl_get_vpid(dvar)
val sres =
d2vardcl_get_sres(dvar)
val dini =
d2vardcl_get_dini(dvar)
//
#impltmp
g_print$out<>() = (  out0  )
//
in//let
(
print("D2VARDCL(");
(print(dpid); print(";"); print(vpid); print(";"); print(sres); print(";"); print(dini); print(")")))
end (*let*) // end-of-[d2vardcl_fprint(dvar,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d2fundcl_fprint
 (dfun, out0) = let
//
val dpid =
d2fundcl_get_dpid(dfun)
val farg =
d2fundcl_get_farg(dfun)
val sres =
d2fundcl_get_sres(dfun)
val tdxp =
d2fundcl_get_tdxp(dfun)
val wsxp =
d2fundcl_get_wsxp(dfun)
//
#impltmp
g_print$out<>() = (  out0 )
//
in//let
(
(print("D2FUNDCL("); print(dpid); print(";"));
(print(farg); print(";"); print(sres); print(";"); print(tdxp); print(";"); print(wsxp); print(")")))
end (*let*) // end-of-[d2fundcl_fprint(dfun,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d2cstdcl_fprint
 (dcst, out0) = let
//
val dpid =
d2cstdcl_get_dpid(dcst)
val darg =
d2cstdcl_get_darg(dcst)
val sres =
d2cstdcl_get_sres(dcst)
val dres =
d2cstdcl_get_dres(dcst)
//
#impltmp
g_print$out<>() = (  out0  )
//
in//let
(
print("D2CSTDCL(");
(print(dpid); print(";"); print(darg); print(";"); print(sres); print(";"); print(dres); print(")")))
end (*let*) // end-of-[d2cstdcl_fprint(dcst,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d2parsed_fprint
 (dpar, out0) = let
//
val
stadyn =
d2parsed_get_stadyn(dpar)
val
nerror =
d2parsed_get_nerror(dpar)
val
source =
d2parsed_get_source(dpar)
val
parsed =
d2parsed_get_parsed(dpar)
//
#impltmp
g_print$out<>() = (  out0  )
//
in//let
(
print("D2PARSED(");
(print(stadyn); print(";"); print(nerror); print(";"); print(source); print(";"); print(parsed); print(")")))
end (*let*) // end-of-[d2parsed_fprint(dpar,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_dynexp2_print0.dats] *)
(***********************************************************************)
