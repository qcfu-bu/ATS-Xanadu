(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2023 Hongwei Xi, ATS Trustful Software, Inc.
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
//
(*
Author: Hongwei Xi
(*
Tue 14 Feb 2023 08:27:19 PM EST
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
#staload "./../SATS/dynexp3.sats"
(* ****** ****** *)
(* ****** ****** *)
#symload lctn with d3pat_get_lctn
#symload node with d3pat_get_node
#symload styp with d3pat_get_styp
(* ****** ****** *)
#symload lctn with d3exp_get_lctn
#symload node with d3exp_get_node
#symload styp with d3exp_get_styp
(* ****** ****** *)
#symload lctn with f3arg_get_lctn
#symload node with f3arg_get_node
(* ****** ****** *)
#symload lctn with d3gua_get_lctn
#symload lctn with d3gpt_get_lctn
#symload lctn with d3cls_get_lctn
#symload node with d3gua_get_node
#symload node with d3gpt_get_node
#symload node with d3cls_get_node
(* ****** ****** *)
#symload lctn with d3ecl_get_lctn
#symload node with d3ecl_get_node
(* ****** ****** *)
#symload stmp with timpl_get_stmp
#symload node with timpl_get_node
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d3pat_fprint
(d3p0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
d3p0.node() of
//
|D3Pany() =>
(print("D3Pany("); print(")"))
//
|D3Pvar(d2v) =>
(print("D3Pvar("); print(d2v); print(")"))
//
(* ****** ****** *)
//
|D3Pint(tok) =>
(print("D3Pint("); print(tok); print(")"))
|D3Pbtf(sym) =>
(print("D3Pbtf("); print(sym); print(")"))
|D3Pchr(tok) =>
(print("D3Pchr("); print(tok); print(")"))
|D3Pflt(tok) =>
(print("D3Pflt("); print(tok); print(")"))
|D3Pstr(tok) =>
(print("D3Pstr("); print(tok); print(")"))
//
(* ****** ****** *)
//
|D3Pcon(d2c) =>
(print("D3Pcon("); print(d2c); print(")"))
//
(* ****** ****** *)
//
|
D3Pbang(d3p1) =>
(print("D3Pbang("); print(d3p1); print(")"))
|
D3Pflat(d3p1) =>
(print("D3Pflat("); print(d3p1); print(")"))
|
D3Pfree(d3p1) =>
(print("D3Pfree("); print(d3p1); print(")"))
//
(* ****** ****** *)
//
|
D3Psapp
(d3f0, s2vs) =>
(print("D3Psapp("); print(d3f0); print(";"); print(s2vs); print(")"))
|
D3Psapq
(d3f0, s2as) =>
(print("D3Psapq("); print(d3f0); print(";"); print(s2as); print(")"))
//
|
D3Ptapq
(d3p1, tjas) =>
(print("D3Ptapq("); print(d3p1); print(";"); print(tjas); print(")"))
//
(* ****** ****** *)
//
|
D3Pdap1(d3f0) =>
(
  (print("D3Pdap1("); print(d3f0); print(")")))
//
|
D3Pdapp
( d3f0
, npf1, d3ps) =>
(
print("D3Pdapp(");
(print(d3f0); print(";"); print(npf1); print(";"); print(d3ps); print(")")))
//
(* ****** ****** *)
//
|
D3Prfpt
( d3p1
, tkas, d3p2) =>
(
print("D3Prfpt(");
(print(d3p1); print(";"); print(tkas); print(";"); print(d3p2); print(")")))
//
(* ****** ****** *)
//
|
D3Ptup0
( npf1, d3ps) =>
(print("D3Ptup0("); print(npf1); print(";"); print(d3ps); print(")"))
|
D3Ptup1
( tknd
, npf1, d3ps ) =>
( print("D3Ptup1(")
; (print(tknd); print(";"); print(npf1); print(";"); print(d3ps); print(")")))
|
D3Prcd2
( tknd
, npf1, ldps ) =>
( print("D3Prcd2(")
; (print(tknd); print(";"); print(npf1); print(";"); print(ldps); print(")")))
//
(* ****** ****** *)
//
|D3Pargtp
( d3p1, t2p2) =>
(
(print("D3Pargtp("); print(d3p1); print(";"); print(t2p2); print(")")))
//
|D3Pannot
( d3p1
, s1e2, s2e2) =>
(print("D3Pannot("); print(d3p1); print(";"); print(s1e2); print(";"); print(s2e2); print(")"))
//
(* ****** ****** *)
//
|D3Pt2pck
( d3p1, t2p2) =>
(
  (print("D3Pt2pck("); print(d3p1); print(";"); print(t2p2); print(")")))
//
(* ****** ****** *)
//
|D3Pnone0() => (print("D3Pnone0("); print(")"))
|D3Pnone1(d2p1) => (print("D3Pnone1("); print(d2p1); print(")"))
|D3Pnone2(d3p1) => (print("D3Pnone2("); print(d3p1); print(")"))
//
(* ****** ****** *)
//
(*
HX-2025-12-31:
Wed Dec 31 06:05:30 PM EST 2025
*)
//
|D3Perrck // HX: generated
( lvl1, d3p2) => // by [tread23]
if // if
(lvl1 >= 2)
then
(
  (print("D3Perrck("); print(lvl1); print(";"); print(d3p2); print(")")))
else // (lvl1<=1)
let
val loc0 = d3p0.lctn() in//let
(
  (print("D3Perrck("); print(loc0); print(";"); print(lvl1); print(";"); print(d3p2); print(")")))
end (*let*) // end-of-[ D3Perrck(lvl1,d3p2) ]
//
(* ****** ****** *)
//
end (*let*) // end of [ d3pat_fprint(d3p0,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d3exp_fprint
(d3e0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
d3e0.node() of
//
(* ****** ****** *)
//
|D3Eint(tok) =>
(print("D3Eint("); print(tok); print(")"))
|D3Ebtf(sym) =>
(print("D3Ebtf("); print(sym); print(")"))
|D3Echr(tok) =>
(print("D3Echr("); print(tok); print(")"))
|D3Eflt(tok) =>
(print("D3Eflt("); print(tok); print(")"))
|D3Estr(tok) =>
(print("D3Estr("); print(tok); print(")"))
//
(* ****** ****** *)
//
|D3Ei00(int) =>
(print("D3Ei00("); print(int); print(")"))
|D3Eb00(btf) =>
(print("D3Eb00("); print(btf); print(")"))
|D3Ec00(chr) =>
(print("D3Ec00("); print(chr); print(")"))
|D3Ef00(flt) =>
(print("D3Ef00("); print(flt); print(")"))
|D3Es00(str) =>
(print("D3Es00("); print(str); print(")"))
//
(* ****** ****** *)
//
|D3Etop(sym) =>
(print("D3Etop("); print(sym); print(")"))
//
(* ****** ****** *)
//
|D3Evar(d2v) =>
(print("D3Evar("); print(d2v); print(")"))
//
(* ****** ****** *)
//
|D3Econ(d2c) =>
(print("D3Econ("); print(d2c); print(")"))
|D3Ecst(d2c) =>
(print("D3Ecst("); print(d2c); print(")"))
//
(* ****** ****** *)
//
|D3Etimp
(d2e1, timp) =>
(
(print("D3Etimp("); print(d2e1); print(";"); print(timp); print(")")))
//
|D3Etimq
(d2e1
,timp, tmps) =>
(print("D3Etimq(")
;(print(d2e1); print(";"); print(timp); print(";"); print(tmps); print(")")))
//
(* ****** ****** *)
//
|
D3Esapp
(d3e1, s2es) =>
(print("D3Esapp("); print(d3e1); print(";"); print(s2es); print(")"))
|
D3Esapq
(d3e1, t2ps) =>
(print("D3Esapq("); print(d3e1); print(";"); print(t2ps); print(")"))
//
(* ****** ****** *)
//
|
D3Etapp
(d3e1, s2es) =>
(print("D3Etapp("); print(d3e1); print(";"); print(s2es); print(")"))
|
D3Etapq
(d3e1, tjas) =>
(print("D3Etapq("); print(d3e1); print(";"); print(tjas); print(")"))
//
(* ****** ****** *)
//
|
D3Edap0(d3f0) =>
(print("D3Edap0("); print(d3f0); print(")"))
|
D3Edapp
(d3f0,npf1,d3es) =>
( print("D3Edapp(")
; (print(d3f0); print(";"); print(npf1); print(";"); print(d3es); print(")")))
//
(* ****** ****** *)
//
|
D3Epcon
(tknd,dlab,dtup) =>
( print("D3Epcon(")
; (print(tknd); print(";"); print(dlab); print(";"); print(dtup); print(")")))
|
D3Eproj
(tknd,dlab,dtup) =>
( print("D3Eproj(")
; (print(tknd); print(";"); print(dlab); print(";"); print(dtup); print(")")))
//
(* ****** ****** *)
//
|
D3Elet0
(dcls, d3e1) =>
(
(print("D3Elet0("); print(dcls); print(";"); print(d3e1); print(")")))
//
(* ****** ****** *)
//
|D3Eift0
(d3e1,dthn,dels) =>
( print("D3Eift0(")
; (print(d3e1); print(";"); print(dthn); print(";"); print(dels); print(")")))
//
|D3Ecas0
(tknd,d3e1,dcls) =>
( print("D3Ecas0(");
  (print(tknd); print(";"); print(d3e1); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
//
|D3Eseqn
(d3es, d3e1) =>
(
(print("D3Eseqn("); print(d3es); print(";"); print(d3e1); print(")")))
//
(* ****** ****** *)
//
|D3Etup0
(npf1, d3es) =>
(
(print("D3Etup0("); print(npf1); print(";"); print(d3es); print(")")))
|
D3Etup1
(tknd,npf1,d3es) =>
( print("D3Etup1(")
; (print(tknd); print(";"); print(npf1); print(";"); print(d3es); print(")")))
|
D3Ercd2
(tknd,npf1,ldes) =>
( print("D3Ercd2(")
; (print(tknd); print(";"); print(npf1); print(";"); print(ldes); print(")")))
//
(* ****** ****** *)
//
|
D3Elam0
(tknd,f3as
,sres,arrw,body) =>
(
(print("D3Elam0("); print(tknd); print(";"));
(print(f3as); print(";"); print(sres); print(";"); print(arrw); print(";"); print(body); print(")")))
//
|
D3Efix0
(tknd,dpid,f3as
,sres,arrw,body) =>
(
(print("D3Efix0("); print(tknd); print(";"); print(dpid); print(";"));
(print(f3as); print(";"); print(sres); print(";"); print(arrw); print(";"); print(body); print(")")))
//
(* ****** ****** *)
//
|
D3Etry0
( tknd
, d3e1, dcls) =>
(
print("D3Etry0(");
(print(tknd); print(";"); print(d3e1); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
//
|D3Eaddr
(   d3e1   ) =>
(print("D3Eaddr("); print(d3e1); print(")"))//lval:addr
|D3Eview
(   d3e1   ) =>
(print("D3Eview("); print(d3e1); print(")"))//lval:view
|D3Elval
(   d3e1   ) =>
(print("D3Elval("); print(d3e1); print(")"))//lval:both
//
|D3Eflat
(   d3e1   ) =>
(print("D3Eflat("); print(d3e1); print(")")) // left-val
//
(* ****** ****** *)
//
|D3Eeval
(   d3e1   ) =>
(print("D3Eeval("); print(d3e1); print(")")) // eval-fun
//
(* ****** ****** *)
//
|D3Efold
(   d3e1   ) =>
(print("D3Efold("); print(d3e1); print(")")) // open-con
|D3Efree
(   d3e1   ) =>
(print("D3Efree("); print(d3e1); print(")")) // free-con
//
(* ****** ****** *)
//
|D3Edp2tr
(   d3e1   ) =>
(print("D3Edp2tr("); print(d3e1); print(")")) // de-p2tr
//
|D3Edl0az
(   d3e1   ) =>
(print("D3Edl0az("); print(d3e1); print(")")) // de-l0az
|D3Edl1az
(   d3e1   ) =>
(print("D3Edl1az("); print(d3e1); print(")")) // de-l1az
|D3Edelaz
(   d3e1   ) =>
(print("D3Edelaz("); print(d3e1); print(")")) // de-elaz
//
(* ****** ****** *)
//
|D3Ewhere
(d3e1, dcls) =>
(
 (print("D3Ewhere("); print(d3e1); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
//
|D3Eassgn
(d3el, d3er) =>
(
 (print("D3Eassgn("); print(d3el); print(";"); print(d3er); print(")")))
|D3Exazgn
(d3el, d3er) =>
(
 (print("D3Exazgn("); print(d3el); print(";"); print(d3er); print(")")))
|D3Exchng
(d3el, d3er) =>
(
 (print("D3Exchng("); print(d3el); print(";"); print(d3er); print(")")))
//
(* ****** ****** *)
//
|D3Eraise
(tknd, d3e1) =>
(
 (print("D3Eraise("); print(tknd); print(";"); print(d3e1); print(")")))
//
(* ****** ****** *)
//
|D3El0azy
(dsym, d3e1) =>
(
 (print("D3El0azy("); print(dsym); print(";"); print(d3e1); print(")")))
|D3El1azy
(dsym
,d3e1, d3es) =>
(
  print("D3El1azy(")
; (print(dsym); print(";"); print(d3e1); print(";"); print(d3es); print(")")))
|D3Eelazy
(dsym
,d3e1, d3es) =>
(
  print("D3Eelazy(")
; (print(dsym); print(";"); print(d3e1); print(";"); print(d3es); print(")")))
//
(* ****** ****** *)
//
|D3Eannot
(d3e1
,s1e2, s2e2) =>
(
  print("D3Eannot(")
; (print(d3e1); print(";"); print(s1e2); print(";"); print(s2e2); print(")")))
//
(* ****** ****** *)
//
|D3Elabck
(d3e1, lab2) =>
let
val
t2p1 = d3e1.styp() in
(
print("D3Elabck(");
(print(d3e1); print("("); print(t2p1); print(");"); print(lab2); print(")")))
end(*let*)//end-of-[D3Elabck(d3e1, lab2)]
//
|D3Et2pck
(d3e1, t2p2) =>
let
val
t2p1 = d3e1.styp() in
(
print("D3Et2pck(");
(print(d3e1); print("("); print(t2p1); print(");"); print(t2p2); print(")")))
end(*let*)//end-of-[D3Et2pck(d3e1, t2p2)]
|D3Et2ped
(d3e1, t2p2) =>
let
val
t2p1 = d3e1.styp() in
(
print("D3Et2ped(");
(print(d3e1); print("("); print(t2p1); print(");"); print(t2p2); print(")")))
end(*let*)//end-of-[D3Et2ped(d3e1, t2p2)]
//
(* ****** ****** *)
//
|D3Eexists
(s2es, d3e1) =>
(
  (print("D3Eexists("); print(s2es); print(";"); print(d3e1); print(")")))
//
(* ****** ****** *)
//
|D3Eextnam
(tknd, gnam) =>
(
  (print("D3Eextnam("); print(tknd); print(";"); print(gnam); print(")")))
//
|D3Esynext
(tknd, gexp) =>
(
  (print("D3Esynext("); print(tknd); print(";"); print(gexp); print(")")))
//
(* ****** ****** *)
//
|D3Enone0() => (print("D3Enone0("); print(")"))
|D3Enone1(d2e1) => (print("D3Enone1("); print(d2e1); print(")"))
|D3Enone2(d3e1) => (print("D3Enone2("); print(d3e1); print(")"))
//
(* ****** ****** *)
//
(*
HX-2025-12-31:
Wed Dec 31 06:05:30 PM EST 2025
*)
//
|
D3Eerrck // HX: generated
( lvl1, d3e2) => // by [tread23]
if // if
(lvl1 >= 2)
then
(
  (print("D3Eerrck("); print(lvl1); print(";"); print(d3e2); print(")")))
else // (lvl1<=1)
let
val loc0 = d3e0.lctn() in//let
(
  (print("D3Eerrck("); print(loc0); print(";"); print(lvl1); print(";"); print(d3e2); print(")")))
end (*let*) // end-of-[ D3Eerrck(lvl1,d3e2) ]
//
end (*let*) // end of [ d3exp_fprint(d3e0,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
f3arg_fprint
(farg, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
farg.node() of
|
F3ARGdapp
(npf1,d3ps) =>
(print("F3ARGdapp("); print(npf1); print(";"); print(d3ps); print(")"))
|
F3ARGsapp
(s2vs,s2ps) =>
(print("F3ARGsapp("); print(s2vs); print(";"); print(s2ps); print(")"))
|
F3ARGmets
(   s2es   ) => (print("F3ARGmets("); print(s2es); print(")"))
(*
|
F3ARGsapq
(   s2vs   ) => prints("F3ARGsapq(",s2vs,")")
*)
//
end (*let*) // end-of-[ f3arg_fprint(farg,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d3gua_fprint
(dgua, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
dgua.node() of
|
D3GUAexp(d3e1) =>
(
  (print("D3GUAexp("); print(d3e1); print(")")))
|
D3GUAmat(d3e1,d3p2) =>
(
  (print("D3GUAmat("); print(d3e1); print(";"); print(d3p2); print(")")))
//
end (*let*) // end of [ d3gua_fprint(dgua,out0) ]
//
(* ****** ****** *)
//
#implfun
d3gpt_fprint
(dgpt, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
case+
dgpt.node() of
|
D3GPTpat(d3p1) =>
(
  (print("D3GPTpat("); print(d3p1); print(")")))
|
D3GPTgua(d3p1,d3gs) =>
(
  (print("D3GPTgua("); print(d3p1); print(";"); print(d3gs); print(")")))
end (*let*) // end of [ d3gpt_fprint(dgpt,out0) ]
//
#implfun
d3cls_fprint
(dcls, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
case+
dcls.node() of
|
D3CLSgpt(dgpt) =>
(
  (print("D3CLSgpt("); print(dgpt); print(")")))
|
D3CLScls(d3g1,d3e2) =>
(
  (print("D3CLScls("); print(d3g1); print(";"); print(d3e2); print(")")))
end (*let*) // end of [ d3cls_fprint(dcls,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
timpl_fprint
(timp, out0) =
let
#implfun
g_print$out<>() = out0
in//let
case+
timp.node() of
//
(*
|TIMPLone1
(  dcl1  ) =>
prints("TIMPLone1(", dcl1 ,")")
*)
//
|TIMPLall1
(d2c1, t2js, dcls) =>
(*
prints
("TIMPLall1(",d2c1,";",t2js,";",dcls,")")
*)
(print("TIMPLall1("); print(d2c1); print(";"); print(t2js); print(";"); print("..."); print(")"))
//
|TIMPLallx
(d2c1, t2js, dcls) =>
(*
prints
("TIMPLallx(",d2c1,";",t2js,";",dcls,")")
*)
(print("TIMPLallx("); print(d2c1); print(";"); print(t2js); print(";"); print("..."); print(")"))
//
end (*let*) // end of [ timpl_fprint(dimp,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d3ecl_fprint
(dcl0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
dcl0.node() of
//
(* ****** ****** *)
//
|D3Cd2ecl(d2cl) =>
(
  (print("D3Cd2ecl("); print(d2cl); print(")")))
//
(* ****** ****** *)
//
|
D3Cstatic(tknd,dcl1) =>
(print("D3Cstatic("); print(tknd); print(";"); print(dcl1); print(")"))
|
D3Cextern(tknd,dcl1) =>
(print("D3Cextern("); print(tknd); print(";"); print(dcl1); print(")"))
//
(* ****** ****** *)
//
|
D3Ctmpsub(svts,dcl1) =>
(print("D3Ctmpsub("); print(svts); print(";"); print(dcl1); print(")"))
//
(* ****** ****** *)
//
|D3Cdclst0(  dcls  ) =>
(
(print("D3Cdclst0("); print(dcls); print(")")))
|
D3Clocal0(head,body) =>
(print("D3Clocal0("); print(head); print(";"); print(body); print(")"))
//
(* ****** ****** *)
//
|
D3Cabsopen
( tknd , simp ) =>
(print("D3Cabsopen("); print(tknd); print(";"); print(simp); print(")"))
|
D3Cabsimpl
(tknd,simp,sdef) =>
(
print("D3Cabsimpl(");
(print(tknd); print(";"); print(simp); print(";"); print(sdef); print(")"))
)
//
(* ****** ****** *)
//
|
D3Cinclude
(knd0,tknd
,gsrc,fopt,dopt) =>
(
print("D3Cinclude(");
(print(knd0); print(";"); print(tknd); print(";"); print(gsrc); print(";"); print(fopt); print(";"); print("..."); print(")")))
//
|
D3Cstaload
(knd0,tknd
,gsrc,fopt,dopt) =>
(
print("D3Cstaload(");
(print(knd0); print(";"); print(tknd); print(";"); print(gsrc); print(";"); print(fopt); print(";"); print("..."); print(")")))
//
(* ****** ****** *)
//
(*
HX-2024-07-20:
Sat 20 Jul 2024 02:18:49 PM EDT
*)
//
|
D3Cdyninit(tknd,g1e1) =>
(
(print("D3Cdyninit("); print(tknd); print(";"); print(g1e1); print(")")))
|
D3Cextcode(tknd,g1e1) =>
(
(print("D3Cextcode("); print(tknd); print(";"); print(g1e1); print(")")))
//
(* ****** ****** *)
//
|
D3Cvaldclst
(  tknd, d3vs  ) =>
(
(print("D3Cvaldclst("); print(tknd); print(";"); print(d3vs); print(")")))
|
D3Cvardclst
(  tknd, d3vs  ) =>
(
(print("D3Cvardclst("); print(tknd); print(";"); print(d3vs); print(")")))
//
|
D3Cfundclst
(tknd
,tqas,d2cs,d3fs) =>
(
print("D3Cfundclst(");
(print(tknd); print(";"); print(tqas); print(";"); print(d2cs); print(";"); print(d3fs); print(")")))
//
|
D3Cimplmnt0
(tknd
,stmp
,sqas,tqas
,dqid,tias
,farg,sres,body) =>
(
print("D3Cimplmnt0(");
(print(tknd); print(";"); print(stmp); print(";"));
(print(sqas); print(";"); print(tqas); print(";"));
(print(dqid); print(";"); print(tias); print(";"); print(farg); print(";"); print(sres); print(";"); print(body); print(")")))
//
|
D3Ctmplocal
(  dtmp, dcls ) =>
(
(print("D3Ctmplocal("); print(dtmp); print(";"); print(dcls); print(")")))
//
|
D3Cimpltmpr(dcl1,t2js) =>
(
(print("D3Cimpltmpr("); print(dcl1); print(";"); print(t2js); print(")")))
//
|D3Cnone0() => (print("D3Cnone0("); print(")"))
|D3Cnone1(d2cl) => (print("D3Cnone1("); print(d2cl); print(")"))
|D3Cnone2(d3cl) => (print("D3Cnone2("); print(d3cl); print(")"))
//
|
D3Cerrck // HX: generated
( lvl1, d3cl) => // by [tread23]
if // if
(lvl1 >= 2)
then
(
  (print("D3Cerrck("); print(lvl1); print(";"); print(d3cl); print(")")))
else // (lvl1<=1)
let
val loc0 = dcl0.lctn() in//let
(
  (print("D3Cerrck("); print(loc0); print(";"); print(lvl1); print(";"); print(d3cl); print(")")))
end (*let*) // end-of-[ D3Cerrck(lvl1,d3cl) ]
//
end (*let*) // end of [ d3ecl_fprint(dcl0,out0) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
d3valdcl_fprint
 (dval, out0) = let
//
val dpat =
d3valdcl_get_dpat(dval)
val tdxp =
d3valdcl_get_tdxp(dval)
val wsxp =
d3valdcl_get_wsxp(dval)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("D3VALDCL("); print(dpat); print(";"); print(tdxp); print(";"); print(wsxp); print(")")))
end(*let*)//end-of-[d3valdcl_fprint(dval,out0)]
//
(* ****** ****** *)
//
#implfun
d3vardcl_fprint
 (dvar, out0) = let
//
val dpid =
d3vardcl_get_dpid(dvar)
val vpid =
d3vardcl_get_vpid(dvar)
val sres =
d3vardcl_get_sres(dvar)
val dini =
d3vardcl_get_dini(dvar)
//
#impltmp g_print$out<>() = out0
//
in//let
(
print("D3VARDCL(");
(print(dpid); print(";"); print(vpid); print(";"); print(sres); print(";"); print(dini); print(")")))
end(*let*)//end-of-[d3vardcl_fprint(dvar,out0)]
//
(* ****** ****** *)

#implfun
d3fundcl_fprint
 (dfun, out0) = let
//
val dpid =
d3fundcl_get_dpid(dfun)
val farg =
d3fundcl_get_farg(dfun)
val sres =
d3fundcl_get_sres(dfun)
val tdxp =
d3fundcl_get_tdxp(dfun)
val wsxp =
d3fundcl_get_wsxp(dfun)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("D3FUNDCL("); print(dpid); print(";"));
(print(farg); print(";"); print(sres); print(";"); print(tdxp); print(";"); print(wsxp); print(")")))
end(*let*)//end-of-[d3fundcl_fprint(dfun,out0)]

(* ****** ****** *)
(* ****** ****** *)

#implfun
d3parsed_fprint
 (dpar, out0) = let
//
val
stadyn =
d3parsed_get_stadyn(dpar)
val
nerror =
d3parsed_get_nerror(dpar)
val
source =
d3parsed_get_source(dpar)
val
parsed =
d3parsed_get_parsed(dpar)
//
#impltmp g_print$out<>() = out0
//
in//let
(
print("D3PARSED(");
(print(stadyn); print(";"); print(nerror); print(";"); print(source); print(";"); print(parsed); print(")")))
end (*let*) // end-of-[d3parsed_fprint(dpar,out0)]

(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_dynexp3_print0.dats] *)
(***********************************************************************)
