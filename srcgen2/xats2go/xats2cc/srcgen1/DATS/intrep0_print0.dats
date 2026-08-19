(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
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
//
Mon Mar  9 02:57:23 PM EDT 2026
//
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
(* ****** ****** *)
(*
#define
XATSOPT "./../../.."
*)
(* ****** ****** *)
#include
"./../../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
(* ****** ****** *)
#include
"./../HATS/mytmplib00.hats"
(* ****** ****** *)
//
#staload
"./../../../../SATS/staexp1.sats"
#staload
"./../../../../SATS/dynexp1.sats"
//
#staload
"./../../../../SATS/staexp2.sats"
#staload
"./../../../../SATS/statyp2.sats"
#staload
"./../../../../SATS/dynexp2.sats"
#staload
"./../../../../SATS/dynexp3.sats"
//
(* ****** ****** *)
//
#staload "./../SATS/intrep0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#symload node with i0typ_node$get
#symload node with i0pat_node$get
#symload node with i0exp_node$get
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0typ_fprint
(ityp, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
in//let
//
case+
ityp.node() of
(* ****** ****** *)
//
|I0Tcst(s2c) =>
(print("I0Tcst("); print(s2c); print(")"))
|I0Tvar(s2v) =>
(print("I0Tvar("); print(s2v); print(")"))
//
(* ****** ****** *)
//
|I0Tlft
(   i0t1   ) =>
(
(print("I0Tlft("); print(i0t1); print(")")))
//
(* ****** ****** *)
//
|I0Ttop0
(   i0t1   ) =>
(print("I0Ttop0("); print(i0t1); print(")"))
|I0Ttop1
(   i0t1   ) =>
(print("I0Ttop1("); print(i0t1); print(")"))
//
(* ****** ****** *)
//
|I0Tapps
(i0f0, i0ts) =>
(print("I0Tapps("); print(i0f0); print(";"); print(i0ts); print(")"))
|I0Tlam1
(s2vs, i0t1) =>
(print("I0Tlam1("); print(s2vs); print(";"); print(i0t1); print(")"))
//
(* ****** ****** *)
//
|I0Texi0
(s2vs, i0t1) =>
(print("I0Texi0("); print(s2vs); print(";"); print(i0t1); print(")"))
|I0Tuni0
(s2vs, i0t1) =>
(print("I0Tuni0("); print(s2vs); print(";"); print(i0t1); print(")"))
//
(* ****** ****** *)
//
|I0Ttcon
(d2c1, i0ts) =>
(print("I0Ttcon("); print(d2c1); print(";"); print(i0ts); print(")"))
|I0Ttrcd
(tknd
,npf1, lits) =>
(
(print("I0Ttcon("); print(tknd); print(";"); print(npf1); print(";"); print(lits); print(")")))
//
(* ****** ****** *)
//
|I0Ttext
(name, i0ts) =>
(
(print("I0Ttext("); print(name); print(";"); print(i0ts); print(")")))
//
(* ****** ****** *)
//
|I0Tnone0() =>
(
  (print("I0Tnone0("); print(")")))
|I0Tnone1
(   t2p1   ) =>
(
  (print("I0Tnone1("); print(t2p1); print(")")))
//
(* ****** ****** *)
//
end(*let*)//end-of-[i0typ_fprint(ityp,out0)]
//
(* ****** ****** *)
//
#implfun
s2typ_fpprnt
(styp, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
in//let
//
case+
styp.node() of
//
|
_(*otherwise*) => s2typ_fprint(styp, out0)
//
end(*let*)//end-of-[s2typ_fpprnt(styp,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0jag_fprint
(ijag, out0) =
let
#impltmp
g_print$out<>() = out0
in//in-of-let
  (print("I0JAG("); print(ijag.i0ts()); print(")"))
end (*let*) // end of [ i0jag_fprint(ijag,out0) ]
//
(* ****** ****** *)
//
#implfun
i0pat_fprint
(ipat, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
in//let
//
case+
ipat.node() of
(* ****** ****** *)
//
|I0Pany() =>
(print("I0Pany("); print(")"))
|I0Pvar(d2v) =>
(print("I0Pvar("); print(d2v); print(")"))
//
(* ****** ****** *)
//
|I0Pint(tok) =>
(print("I0Pint("); print(tok); print(")"))
|I0Pbtf(sym) =>
(print("I0Pbtf("); print(sym); print(")"))
|I0Pchr(tok) =>
(print("I0Pchr("); print(tok); print(")"))
|I0Pstr(tok) =>
(print("I0Pstr("); print(tok); print(")"))
//
(* ****** ****** *)
|I0Pcon(d2c) =>
(print("I0Pcon("); print(d2c); print(")"))
(* ****** ****** *)
//
|I0Pbang
(   i0p1   ) =>
(print("I0Pbang("); print(i0p1); print(")"))
|I0Pflat
(   i0p1   ) =>
(print("I0Pflat("); print(i0p1); print(")"))
|I0Pfree
(   i0p1   ) =>
(print("I0Pfree("); print(i0p1); print(")"))
//
(* ****** ****** *)
//
|I0Ptapq
(i0p1, ijas) =>
(
(print("\
I0Ptapq("); print(i0p1); print(";"); print(ijas); print(")")))
//
(* ****** ****** *)
//
|I0Pdap1
(   i0f0   ) =>
(print("I0Pdap1("); print(i0f0); print(")"))
|I0Pdapp
(i0f0
,npf1, i0ps) =>
(
print("I0Pdapp(");
(print(i0f0); print(";"); print(npf1); print(";"); print(i0ps); print(")")))
//
(* ****** ****** *)
//
|I0Pdprf
(   dpat   ) =>
(
(print("I0Pdprf("); print(dpat); print(")")))
//
|I0Ptup0
(npf1, i0ps) =>
(print("I0Ptup0("); print(npf1); print(";"); print(i0ps); print(")"))
//
|I0Ptup1
(tknd
,npf1, i0ps) =>
(
print("I0Ptup1(");
(print(tknd); print(";"); print(npf1); print(";"); print(i0ps); print(")")))
//
|I0Prcd2
(tknd
,npf1,lips) =>
(
print("I0Prcd2(");
(print(tknd); print(";"); print(npf1); print(";"); print(lips); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Pnone0() =>
(
  (print("I0Pnone0("); print(")")))
//
|I0Pnone1(d3p1) =>
let
val loc0 = d3p1.lctn() in//let
(
(print("I0Pnone1("); print(loc0); print(";"); print(d3p1); print(")"))) end
//
(* ****** ****** *)
(* ****** ****** *)
//
end(*let*)//end-of-[i0pat_fprint(ipat,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0cal_fprint
(ical, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
in//let
//
case+ ical of
//
|I0CALnil() =>
(
(print("I0CALnil("); print(")")))
//
|I0CALlam() =>
(
(print("I0CALlam("); print(")")))
|I0CALfix(d2v1) =>
(
(print("I0CALfix("); print(d2v1); print(")")))
//
|I0CALimp(dimp) =>
(
(print("I0CALimp("); print(dimp); print(")")))
//
|I0CALfun(d2v1, d2vs) =>
(
(print("I0CALfun("); print(d2v1); print(";"); print(d2vs); print(")")))
//
end(*let*)//end-of-[i0cal_fprint(ical,out0)]
//
(* ****** ****** *)
//
#implfun
i0var_fprint
(ivar, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
val dvar = ivar.dvar()
val lvl0 = ivar.lvl0()
val bvk0 = ivar.bvk0()
val ityp = ivar.ityp()
//
in//let
(
print("I0VAR(");
(print(dvar); print(";"); print(lvl0); print(";"); print(bvk0); print(";"); print("..."); print(")")))
end(*let*)//end-of-[i0var_fprint(ivar,out0)]
//
(* ****** ****** *)
//
#implfun
i0exp_fprint
(iexp, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
(*
val () =
prints("\
i0exp_fprint: \
loc0 = ", iexp.lctn())
*)
//
in//let
//
case+
iexp.node() of
//
(* ****** ****** *)
//
|I0Eint(int) =>
(
(print("I0Eint("); print(int); print(")")))
|I0Ebtf(btf) =>
(
(print("I0Ebtf("); print(btf); print(")")))
|I0Echr(chr) =>
(
(print("I0Echr("); print(chr); print(")")))
|I0Eflt(flt) =>
(
(print("I0Eflt("); print(flt); print(")")))
|I0Estr(str) =>
(
(print("I0Estr("); print(str); print(")")))
//
(* ****** ****** *)
//
|I0Ei00(i00) =>
(
(print("I0Ei00("); print(i00); print(")")))
|I0Eb00(b00) =>
(
(print("I0Eb00("); print(b00); print(")")))
|I0Ec00(c00) =>
(
(print("I0Ec00("); print(c00); print(")")))
|I0Ef00(f00) =>
(
(print("I0Ef00("); print(f00); print(")")))
|I0Es00(s00) =>
(
(print("I0Es00("); print(s00); print(")")))
//
(* ****** ****** *)
//
|I0Etop
(   sym   ) =>
(
(print("I0Etop("); print(sym); print(")")))
//
(* ****** ****** *)
//
|I0Evar
(   i0v1   ) =>
(
(print("I0Evar("); print(i0v1); print(")")))
//
(* ****** ****** *)
//
|I0Econ
(   d2c1   ) =>
(
(print("I0Econ("); print(d2c1); print(")")))
//
|I0Ecst
(   d2c1   ) =>
(
(print("I0Ecst("); print(d2c1); print(")")))
//
(* ****** ****** *)
//
|I0Etimp
(i0e1, timp) =>
(
(print("\
I0Etimp("); print(i0e1); print(";"); print(timp); print(")")))
//
(* ****** ****** *)
//
|I0Esapp
(i0f0, s2es) =>
(
(print("\
I0Esapp("); print(i0f0); print(";"); print(s2es); print(")")))
//
|I0Esapq
(i0f0, i0ts) =>
(
(print("\
I0Esapq("); print(i0f0); print(";"); print(i0ts); print(")")))
//
(* ****** ****** *)
//
|I0Etapp
(i0f0, s2es) =>
(
(print("I0Etapp("); print(i0f0); print(";"); print(s2es); print(")")))
//
|I0Etapq
(i0f0, ijgs) =>
(
(print("I0Etapq("); print(i0f0); print(";"); print(ijgs); print(")")))
//
(* ****** ****** *)
//
|I0Edap0
(   i0f0   ) =>
(print("I0Edap0("); print(")"))
//
|I0Edapp
(i0f0
,npf1, i0es) =>
(
print("I0Edapp(");
(print(i0f0); print(";"); print(npf1); print(";"); print(i0es); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Epcon
(tknd
,lab0, i0e1) =>
(
print("I0Epcon(");
(print(tknd); print(";"); print(lab0); print(";"); print(i0e1); print(")")))
//
|I0Epflt
(tknd
,lab0, i0e1) =>
(
print("I0Epflt(");
(print(tknd); print(";"); print(lab0); print(";"); print(i0e1); print(")")))
//
|I0Eproj
(tknd
,lab0, i0e1) =>
(
print("I0Eproj(");
(print(tknd); print(";"); print(lab0); print(";"); print(i0e1); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Elet0
(dcls, i0e1) =>
(
(print("I0Elet0("); print(dcls); print(";"); print(i0e1); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Eift0
(test
,ithn, iels) =>
(
print("I0Eift0(");
(print(test); print(";"); print(ithn); print(";"); print(iels); print(")")))
//
|I0Ecas0
(tknd
,i0e1, icls) =>
(
print("I0Ecas0(");
(print(tknd); print(";"); print(i0e1); print(";"); print(icls); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Eseqn
(i0es, i0e1) =>
(
(print("I0Eseqn("); print(i0es); print(";"); print(i0e1); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Edprf
(   dexp   ) =>
(
  (print("I0Edprf("); print(dexp); print(")")))
//
|I0Etup0
(npf1, i0es) =>
(
(print("I0Etup0("); print(npf1); print(";"); print(i0es); print(")")))
//
|I0Etup1
(tknd
,npf1, i0es) =>
(
print("I0Etup1(");
(print(tknd); print(";"); print(npf1); print(";"); print(i0es); print(")")))
//
|I0Ercd2
(tknd
,npf1, lies) =>
(
print("I0Ercd2(");
(print(tknd); print(";"); print(npf1); print(";"); print(lies); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
HX-2026-04-19:
FV(i0e1) = i0vs!
Sun Apr 19 02:45:21 AM EDT 2026
*)
|I0Ecenv
(i0e1, i0ws) =>
(
(print("I0Ecenv("); print(i0e1); print(";"); print(i0ws); print(")")))
//
|I0Elam0
(lvl0
,tknd
,fias
,body, denv) =>
(
print("I0Elam0(");
(print(lvl0); print(";"); print(tknd); print(";"));
(print(fias); print(";"); print(body); print(";"); print(denv); print(")")))
//
|I0Efix0
(lvl0
,tknd
,fid0, fias
,body, denv) =>
(
print("I0Efix0(");
(print(lvl0); print(";"); print(tknd); print(";"));
(print(fid0); print(";"); print(fias); print(";"); print(body); print(";"); print(denv); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Eaddr
( i0e1 ) =>
(
(print("I0Eaddr("); print(i0e1); print(")")) )//I0Eaddr
//
|I0Eflat
( i0e1 ) =>
(
(print("I0Eflat("); print(i0e1); print(")")) )//I0Eflat
//
|I0Eeval
( i0e1 ) =>
(
(print("I0Eeval("); print(i0e1); print(")")) )//I0Eeval
//
|I0Efold
( i0e1 ) =>
(
(print("I0Efold("); print(i0e1); print(")")) )//I0Efold
//
|I0Efree
( i0e1 ) =>
(
(print("I0Efree("); print(i0e1); print(")")) )//I0Efree
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Edp2tr
(   i0e1    ) =>
(
(print("I0Edp2tr("); print(i0e1); print(")")))//de-p2tr
//
|I0Edl0az
(   i0e1    ) =>
(
(print("I0Edl0az("); print(i0e1); print(")")))//de-l0az
|I0Edl1az
(   i0e1    ) =>
(
(print("I0Edl1az("); print(i0e1); print(")")))//de-l1az
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Ewhere
(i0e1, dcls) =>
(
(print("I0Ewhere("); print(i0e1); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Eassgn
(i0el, i0er) =>
(
(print("I0Eassgn("); print(i0el); print(";"); print(i0er); print(")")))
//
|I0Eraise
(tknd, iexn) =>
(
(print("I0Eraise("); print(tknd); print(";"); print(iexn); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Eannot
(i0e1
,s1e2, s2e2) =>
(
  print("I0Eannot(")
; (print(i0e1); print(";"); print(s1e2); print(";"); print(s2e2); print(")")))
//
(* ****** ****** *)
//
|I0Elabck
(i0e1, lab2) =>
let
val
i0t1 = i0e1.ityp() in
(
print("I0Elabck(");
(print(i0e1); print("("); print(i0t1); print(");"); print(lab2); print(")")))
end(*let*)//end-of-[I0Elabck(i0e1, lab2)]
//
|I0Et2pck
(i0e1, t2p2) =>
let
val
i0t1 = i0e1.ityp() in
(
print("I0Et2pck(");
(print(i0e1); print("("); print(i0t1); print(");"); print(t2p2); print(")")))
end(*let*)//end-of-[I0Et2pck(i0e1, t2p2)]
|I0Et2ped
(i0e1, t2p2) =>
let
val
i0t1 = i0e1.ityp() in
(
print("I0Et2ped(");
(print(i0e1); print("("); print(i0t1); print(");"); print(t2p2); print(")")))
end(*let*)//end-of-[I0Et2ped(i0e1, t2p2)]
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Erturn
(ical, i0e1) =>
(
(print("I0Erturn("); print(ical); print(";"); print(i0e1); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|
I0Enone0() =>
(
let
val
loc0 = iexp.lctn() in//let
(
(print("I0Enone0("); print(loc0); print(")"))) end)
//
|I0Enone1
(   d3e1   ) =>
(
let
val
loc0 = iexp.lctn() in//let
(
(print("I0Enone1("); print(loc0); print(";"); print(d3e1); print(")"))) end)
//
|I0Enone2
(   i0e1   ) =>
(
let
val
loc0 = iexp.lctn() in//let
(
(print("I0Enone2("); print(loc0); print(";"); print(i0e1); print(")"))) end)
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Eextnam
(tknd, gnam) =>
(
(print("I0Eextnam("); print(tknd); print(";"); print(gnam); print(")")))
//
(* ****** ****** *)
//
|I0Esynext
(tknd, gexp) =>
(
(print("I0Esynext("); print(tknd); print(";"); print(gexp); print(")")))
//
(* ****** ****** *)
//
// xats2go MIGRATION: print arm for the APPENDED [I0Etry0] node.
|I0Etry0
(tknd, i0e1, icls) =>
(
(print("I0Etry0("); print(tknd); print(";"); print(i0e1); print(";"); print(icls); print(")")))
//
// xats2go MIGRATION: print arms for the APPENDED lazy constructor nodes.
|I0El0azy
(dknd, i0e1) =>
(
(print("I0El0azy("); print(dknd); print(";"); print(i0e1); print(")")))
|I0El1azy
(dknd, i0e1, i0es) =>
(
print("I0El1azy(");
(print(dknd); print(";"); print(i0e1); print(";"); print(i0es); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
end(*let*)//end-of-[i0exp_fprint(iexp,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
fiarg_fprint
(farg, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
farg.node() of
|FIARGsapp
(s2vs, s2ps) =>
(
(print("\
FIARGsapp("); print(s2vs); print(";"); print(s2ps); print(")")))
|FIARGmets
(   s2es   ) =>
(
(print("FIARGmets("); print(s2es); print(")")))
//
|FIARGdapp
(npf1, i0ps) =>
(
(print("\
FIARGdapp("); print(npf1); print(";"); print(i0ps); print(")")))
//
end(*let*)//end-of-[fiarg_fprint(farg,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0gua_fprint
(dgua, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
dgua.node() of
|
I0GUAexp(i0e1) =>
(
  (print("I0GUAexp("); print(i0e1); print(")")))
|
I0GUAmat(i0e1,i0p2) =>
(
  (print("I0GUAmat("); print(i0e1); print(";"); print(i0p2); print(")")))
//
end(*let*)//end-of-[i0gua_fprint(dgua,out0)]
//
(* ****** ****** *)
//
#implfun
i0gpt_fprint
(igpt, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
igpt.node() of
|
I0GPTpat(i0p1) =>
(
  (print("I0GPTpat("); print(i0p1); print(")")))
|
I0GPTgua(i0p1,i0gs) =>
(
  (print("I0GPTgua("); print(i0p1); print(";"); print(i0gs); print(")")))
//
end(*let*)//end-of-[i0gpt_fprint(igpt,out0)]
//
#implfun
i0cls_fprint
(icls, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
icls.node() of
|
I0CLSgpt(igpt) =>
(
  (print("I0CLSgpt("); print(igpt); print(")")))
|
I0CLScls(i0g1,i0e2) =>
(
  (print("I0CLScls("); print(i0g1); print(";"); print(i0e2); print(")")))
//
end(*let*)//end-of-[i0cls_fprint(igua,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
t0imp_fprint
(timp, out0) =
let
#implfun
g_print$out<>() = out0
in//let
case+
timp.node() of
//
(*
|T0IMPone1
(  dcl1  ) =>
prints("T0IMPone1(", dcl1 ,")")
*)
//
|T0IMPall1
(d2c1
,t2js, i0ds) =>
(print("T0IMPall1("); print(d2c1); print(";"); print(t2js); print(";"); print(i0ds); print(")"))
//
|T0IMPallx
(d2c1
,t2js, i0ds) =>
(print("T0IMPallx("); print(d2c1); print(";"); print(t2js); print(";"); print(i0ds); print(")"))
//
end(*let*)//end-of-[t0imp_fprint(timp,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0dcl_fprint
(idcl, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
in//let
//
case+
idcl.node() of
(* ****** ****** *)
(* ****** ****** *)
//
|I0Dd3ecl(d3cl) =>
(
 (print("I0Dd3ecl("); print(d3cl); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Dstatic
(tknd, dcl1) =>
(print("\
I0Dstatic("); print(tknd); print(";"); print(dcl1); print(")"))
//
|I0Dextern
(tknd, dcl1) =>
(print("\
I0Dextern("); print(tknd); print(";"); print(dcl1); print(")"))
//
(* ****** ****** *)
//
|I0Ddclenv
(idcl, i0ws) =>
(print("\
I0Ddclenv("); print(idcl); print(";"); print(i0ws); print(")"))
//
(* ****** ****** *)
//
|I0Dtmpsub
(svts, idcl) =>
(print("\
I0Dtmpsub("); print(svts); print(";"); print(idcl); print(")"))
//
(* ****** ****** *)
//
|I0Ddclst0
(   dcls   ) =>
(
  (print("I0Ddclst0("); print(dcls); print(")")))
//
|I0Dlocal0
(head, body) =>
(print("I0Dlocal0("); print(head); print(";"); print(body); print(")"))
//
(* ****** ****** *)
//
|I0Dinclude
(knd0
,tknd, gsrc
,fopt, dopt) =>
(
print("I0Dinclude(");
(print(knd0); print(";"); print(tknd); print(";"); print(gsrc); print(";"); print(fopt); print(";"); print("..."); print(")")))
//
(*
|I0Dstaload _ => (*HX: I0Dd3ecl(...)*)
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Dvaldclst
( tknd, dcls) =>
(
(print("I0Dvaldclst("); print(tknd); print(";"); print(dcls); print(")")))
//
|I0Dvardclst
( tknd, dcls) =>
(
(print("I0Dvardclst("); print(tknd); print(";"); print(dcls); print(")")))
//
(* ****** ****** *)
//
|I0Dfundclst
( tknd
, lvl0, tqas
, d2cs, i0fs) =>
(
print("I0Dfundclst(");
(print(tknd); print(";"); print(lvl0); print(";"));
(print(tqas); print(";"); print(d2cs); print(";"); print(i0fs); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I0Dimplmnt0
( tknd
, lvl0, stmp
, dimp, fias
, iexp, i0vs) =>
( (print("I0Dimplmnt0("); print(tknd); print(";"))
; (print(lvl0); print(";"); print(stmp); print(";"); print(dimp); print(";"))
; (print(fias); print(";"); print(iexp); print(";"); print(i0vs); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|
I0Dnone0() =>
let
val
loc0 = idcl.lctn() in//let
(print("I0Dnone0("); print(loc0); print(")")) end//let
//
|I0Dnone1(d3cl) =>
(
let
val
loc0 = idcl.lctn() in//let
(
(print("I0Dnone1("); print(loc0); print(";"); print(d3cl); print(")"))) end)
//
|I0Dnone2(dcl1) =>
(
let
val
loc0 = idcl.lctn() in//let
(
(print("I0Dnone2("); print(loc0); print(";"); print(dcl1); print(")"))) end)
//
(* ****** ****** *)
(* ****** ****** *)
//
end(*let*)//end-of-[i0dcl_fprint(idcl,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0valdcl_fprint
  (ival, out0) = let
//
val ipat =
i0valdcl_ipat$get(ival)
val tdxp =
i0valdcl_tdxp$get(ival)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("I0VALDCL("); print(ipat); print(";"); print(tdxp); print(")")))
end(*let*)//end-of-[i0valdcl_fprint(ival,out0)]
//
(* ****** ****** *)
//
#implfun
i0vardcl_fprint
  (ivar, out0) = let
//
val dpid =
i0vardcl_dpid$get(ivar)
val dini =
i0vardcl_dini$get(ivar)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("I0VARDCL("); print(dpid); print(";"); print(dini); print(")")))
end(*let*)//end-of-[i0vardcl_fprint(ivar,out0)]
//
(* ****** ****** *)
//
#implfun
i0fundcl_fprint
  (ifun, out0) = let
//
val dpid =
i0fundcl_dpid$get(ifun)
val farg =
i0fundcl_farg$get(ifun)
val tdxp =
i0fundcl_tdxp$get(ifun)
val i0vs =
i0fundcl_i0vs$get(ifun)
//
#impltmp g_print$out<>() = out0
//
in//let
(
print("I0FUNDCL(");
(print(dpid); print(";"); print(farg); print(";"); print(tdxp); print(";"); print(i0vs); print(")")))
end(*let*)//end-of-[i0fundcl_fprint(ifun,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0varfst_fprint
(ivst, out0) =
(
strm_vt_print0(i0vs))
where
{
//
#impltmp
g_print$out<>() = out0
//
(*
HX-2026-04-03:
This works for srcgen1;
it does not work for srcgen2!
*)
#impltmp
strm_vt_print$len<>() = -1
#impltmp
strm_vt_print$beg<>
  ( (*0*) ) = strn_print("IVST(")
//
val i0vs =
(
  i0varfst_strmize(       ivst       ))
//
}(*where*)//end-of-(i0varfst_fprint(ivst,out0))
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0parsed_fprint
  (ipar, out0) = let
//
val
stadyn =
i0parsed_stadyn$get(ipar)
val
nerror =
i0parsed_nerror$get(ipar)
val
source =
i0parsed_source$get(ipar)
val
parsed =
i0parsed_parsed$get(ipar)
//
#impltmp g_print$out<>() = out0
//
in//let
(
print("I0PARSED(");
(print(stadyn); print(";"); print(nerror); print(";"); print(source); print(";"); print(parsed); print(")")))
end(*let*)//end-of-[i0parsed_fprint(ipar,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2cc_srcgen1_DATS_intrep0_print0.dats] *)
(***********************************************************************)
