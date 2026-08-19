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
Sat Apr 11 02:32:04 PM EDT 2026
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
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
(* ****** ****** *)
#include
"./../HATS/mytmplib00.hats"
(* ****** ****** *)
(* ****** ****** *)
#staload // D2E =
"./../../../SATS/dynexp2.sats"
(* ****** ****** *)
(* ****** ****** *)
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
#staload "./../SATS/intrep1.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1let_fprint
(ilet, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+ ilet of
|I1LETnew0(iins) =>
(
(print("I1LETnew0("); print(iins); print(")")))
|I1LETnew1(itnm, iins) =>
(
(print("I1LETnew1("); print(itnm); print(";"); print(iins); print(")")))
//
end(*let*)//end-of-[i1let_fprint(ilet,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1bnd_fprint
(ibnd, out0) =
let
//
#impltmp
g_print$out
<(*0*)>((*0*)) = out0
//
#impltmp
g_print
<d2var>( dvar ) =
d2var_fprint(dvar, out0)
//
in//let
//
case+ ibnd of
|I1BNDcons
(itnm, ipat, dsub) =>
(
print("I1BNDcons(");
(print(itnm); print(";"); print(ipat); print(";"); print(dsub); print(")")))
//
end(*let*)//end-of-[i1bnd_fprint(ibnd,out0)]
//
(* ****** ****** *)
//
#implfun
i1cmp_fprint
(icmp, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+ icmp of
|I1CMPcons(ilts, ival) =>
(print("I1CMPcons("); print(ilts); print(";"); print(ival); print(")"))
//
end(*let*)//end-of-[i1cmp_fprint(icmp,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1val_fprint
(i1v0, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
i1v0.node() of
//
(* ****** ****** *)
//
|I1Vnil() =>
(
(print("I1Vnil("); print(")")))
//
(* ****** ****** *)
//
|I1Vint(int) =>
(print("I1Vint("); print(int); print(")"))
|I1Vbtf(btf) =>
(print("I1Vbtf("); print(btf); print(")"))
|I1Vchr(chr) =>
(print("I1Vchr("); print(chr); print(")"))
|I1Vflt(flt) =>
(print("I1Vflt("); print(flt); print(")"))
|I1Vstr(str) =>
(print("I1Vstr("); print(str); print(")"))
//
(* ****** ****** *)
//
|I1Vi00(i00) =>
(print("I1Vi00("); print(i00); print(")"))
|I1Vb00(b00) =>
(print("I1Vb00("); print(b00); print(")"))
|I1Vc00(c00) =>
(print("I1Vc00("); print(c00); print(")"))
|I1Vf00(f00) =>
(print("I1Vf00("); print(f00); print(")"))
|I1Vs00(s00) =>
(print("I1Vs00("); print(s00); print(")"))
//
(* ****** ****** *)
//
|I1Vtop(sym) =>
(print("I1Vtop("); print(sym); print(")"))
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
|I1Varg(iarg) =>
prints("I1Varg(",iarg,")")
*)
//
|I1Venv(ienv) =>
(print("I1Venv("); print(ienv); print(")"))
//
(* ****** ****** *)
//
|I1Vtnm(itnm) =>
(print("I1Vtnm("); print(itnm); print(")"))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I1Vcon(dcon) =>
(print("I1Vcon("); print(dcon); print(")"))
|I1Vcst(dcst) =>
(print("I1Vcst("); print(dcst); print(")"))
//
(* ****** ****** *)
//
|
I1Vfid(dvar) =>
(print("I1Vfid("); print(dvar); print(")"))
(*
|
I1Vfid(dvar) =>
let
val name = dvar.name()
in//end
prints("I1Vfid(",name,")")
end//let//end-[I1Vfid(dvar)]
*)
//
(* ****** ****** *)
(* ****** ****** *)
|
I1Vaexp(iexp) =>
(print("I1Vaexp("); print(iexp); print(")"))
|
I1Vaddr(ival) =>
(print("I1Vaddr("); print(ival); print(")"))
(* ****** ****** *)
(* ****** ****** *)
//
|I1Vfenv
(d2v1, i1vs) =>
(
print("I1Vfenv(");
(print(d2v1); print(";"); print(i1vs); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I1Vp0rj
(i1v1, idx2) =>
(
print("I1Vp0rj(");
(print(i1v1); print(";"); print(idx2); print(")")))
//
|I1Vp1cn
(i0f0
,i1v1, idx2) =>
(
print("I1Vp1cn(");
(print(i0f0); print(";"); print(i1v1); print(";"); print(idx2); print(")")))
//
|I1Vp1rj
(tknd
,i1v1, idx2) =>
(
print("I1Vp1rj(");
(print(tknd); print(";"); print(i1v1); print(";"); print(idx2); print(")")))
//
|I1Vp2rj
(tknd
,i1v1, lab2) =>
(
print("I1Vp2rj(");
(print(tknd); print(";"); print(i1v1); print(";"); print(lab2); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I1Vextnam
(tknd
,i1v1, g1ns) =>
( print("I1Vextnam(")
; (print(tknd); print(";"); print(i1v1); print(";"); print(g1ns); print(")")))
//
(* ****** ****** *)
(* ****** ****** *)
//
|I1Vnone0() => (print("I1Vnone0("); print(")"))
|I1Vnone1(i0e1) => (print("I1Vnone1("); print(i0e1); print(")"))
//
(* ****** ****** *)
//
end(*let*)//end-of-[i1val_fprint(i1v0,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1ins_fprint
(iins, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+ iins of
//
(* ****** ****** *)
//
|I1INSopr
( iopr, i1vs) =>
(
print("I1INSopr(");
(print(iopr); print(";"); print(i1vs); print(")")))
//
(* ****** ****** *)
//
|I1INSdapp
( i1f0, i1vs) =>
(
print("I1INSdapp(");
(print(i1f0); print(";"); print(i1vs); print(")")))
//
(* ****** ****** *)
//
|I1INStimp
( i0e1,timp ) =>
(
print("I1INStimp(");
(print(i0e1); print(";"); print("..."); print(")")))
where
{
val
i0e1 =
(
  detapq(i0e1)) where
{
fun
detapq
( i0e1
: i0exp): i0exp =
(
case+
i0e1.node() of
|
I0Etapq
(i0e1, _) => detapq(i0e1)
|
_(*otherwise*) => ( i0e1 ))}
}(*where*)//end-of(I1INStimp)
//
(* ****** ****** *)
//
|I1INStup0
(   i1vs   ) =>
(
(print("I1INStup0("); print(i1vs); print(")")))
//
|I1INStup1
(tknd, i1vs) =>
( print("I1INStup1(")
; (print(tknd); print(";"); print(i1vs); print(")")))
//
|I1INSrcd2
(tknd, livs) =>
( print("I1INSrcd2(")
; (print(tknd); print(";"); print(livs); print(")")))
//
(* ****** ****** *)
//
|I1INSpcon
(dlab, icon) =>
( print("I1INSpcon(")
; (print(dlab); print(";"); print(icon); print(")")))
//
|I1INSpflt
(dlab, itup) =>
( print("I1INSpflt(")
; (print(dlab); print(";"); print(itup); print(")")))
//
|I1INSproj
(dlab, itup) =>
( print("I1INSproj(")
; (print(dlab); print(";"); print(itup); print(")")))
//
(* ****** ****** *)
//
|I1INSlet0
(dcls, icmp) =>
( print("I1INSlet0(")
; (print(dcls); print(";"); print(icmp); print(")")))
//
(* ****** ****** *)
//
|I1INSift0
(test
,ithn, iels) =>
(
print("I1INSift0(");
(print(test); print(";"); print(ithn); print(";"); print(iels); print(")")))
//
|I1INScas0
(cask
,i1v1, icls) =>
(
print("I1INScas0(");
(print(cask); print(";"); print(i1v1); print(";"); print(icls); print(")")))
//
(* ****** ****** *)
//
|I1INSlam0
(tknd
,fjas, icmp) =>
( print
( "I1INSlam0(" )
; (print(tknd); print(";"); print(fjas); print(";"); print(icmp); print(")")))
//
|I1INSfix0
(tknd, dvar
,fjas, icmp) =>
( print
( "I1INSfix0(" )
; (print(tknd); print(";"); print(dvar); print(";"); print(fjas); print(";"); print(icmp); print(")")))
//
(* ****** ****** *)
//
|I1INStry0
(tknd
,icmp
,iexn, icls) =>
( print
( "I1INStry0(" )
; (print(tknd); print(";"); print(icmp); print(";"); print(iexn); print(";"); print(icls); print(")")))
//
(* ****** ****** *)
//
|I1INSflat
(   i1v0   ) =>
((print("I1INSflat("); print(i1v0); print(")")))
//
(* ****** ****** *)
//
|I1INSfold
(   i1v0   ) =>
((print("I1INSfold("); print(i1v0); print(")")))
//
|I1INSfree
(   i1v0   ) =>
((print("I1INSfree("); print(i1v0); print(")")))
//
(* ****** ****** *)
//
|I1INSrturn
(ical, icmp) =>
( print("I1INSrturn(")
; (print(ical); print(";"); print(icmp); print(")")))
//
(* ****** ****** *)
//
|I1INSdp2tr
(   iptr   ) =>
(
(print("I1INSdp2tr("); print(iptr); print(")")))
//
(* ****** ****** *)
//
|I1INSdl0az
(   i1f0   ) =>
(
(print("I1INSdl0az("); print(i1f0); print(")")))
|I1INSdl1az
(   i1f0   ) =>
(
(print("I1INSdl1az("); print(i1f0); print(")")))
//
(* ****** ****** *)
//
|I1INSl0azy
(dknd, icmp) =>
( print("I1INSl0azy(")
; (print(dknd); print(";"); print(icmp); print(")")))
//
|I1INSl1azy
(dknd, icmp, i1fs) =>
(
print("I1INSl1azy(");
(print(dknd); print(";"); print(icmp); print(";"); print(i1fs); print(")")))
//
(* ****** ****** *)
//
|I1INSraise
(tknd, iexn) => // iexp: i1val
(
 (print("I1INSraise("); print(iexn); print(")")))
//
(* ****** ****** *)
//
|I1INSassgn
(i1vl, i1vr) =>
(
(print("I1INSassgn("); print(i1vl); print(";"); print(i1vr); print(")")))
//
(* ****** ****** *)
//
end(*let*)//end-of-[i1ins_fprint(iins,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
fjarg_fprint
(farg, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
farg.node() of
|FJARGdarg(i1bs) =>
(
  (print("FJARGdarg("); print(i1bs); print(")")))
//
end(*let*)//end-of-[fjarg_fprint(farg,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1gua_fprint
(igua, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
igua.node() of
|I1GUAexp(icmp) =>
(
(print("I1GUAexp("); print(icmp); print(")")))
|I1GUAmat(icmp,ibnd) =>
(
(print("I1GUAmat("); print(icmp); print(";"); print(ibnd); print(")")))
//
end(*let*)//end-of-[i1gua_fprint(igua,out0)]
//
(* ****** ****** *)
//
#implfun
i1gpt_fprint
(igpt, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
igpt.node() of
|I1GPTpat(ibnd) =>
(
(print("I1GPTpat("); print(ibnd); print(")")))
|I1GPTgua(ibnd,i1gs) =>
(
(print("I1GPTgua("); print(ibnd); print(";"); print(i1gs); print(")")))
//
end(*let*)//end-of-[i1gpt_fprint(igpt,out0)]
//
#implfun
i1cls_fprint
(icls, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
icls.node() of
|I1CLSgpt(igpt) =>
(
(print("I1CLSgpt("); print(igpt); print(")")))
|I1CLScls(igpt,icmp) =>
(
(print("I1CLScls("); print(igpt); print(";"); print(icmp); print(")")))
//
end(*let*)//end-of-[i1cls_fprint(icls,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
t1imp_fprint
(timp, out0) =
let
#implfun
g_print$out<>() = out0
in//let
case+
timp.node() of
//
(*
|T1IMPone1
(   dcl1   ) =>
prints("T1IMPone1(", dcl1 ,")")
*)
//
|T1IMPall1
(d2c1
,t2js, dopt) =>
(print("T1IMPall1("); print(d2c1); print(";"); print(t2js); print(";"); print(dopt); print(")"))
//
|T1IMPallx
(d2c1
,t2js, dopt) =>
(print("T1IMPallx("); print(d2c1); print(";"); print(t2js); print(";"); print(dopt); print(")"))
//
end(*let*)//end-of-[t1imp_fprint(timp,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1dcl_fprint
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
|I1Di0dcl
(  dcl1  ) =>
(
(print("I1Di0dcl("); print(dcl1); print(")")))
//
(* ****** ****** *)
//
|I1Dextern
(tknd, dcl1) =>
(print("I1Dextern("); print(tknd); print(";"); print(dcl1); print(")"))
|I1Dstatic
(tknd, dcl1) =>
(print("I1Dstatic("); print(tknd); print(";"); print(dcl1); print(")"))
//
(* ****** ****** *)
//
|I1Ddclst0
(   dcls   ) =>
(
  (print("I1Ddclst0("); print(dcls); print(")")))
//
|I1Dlocal0
(head, body) =>
(print("I1Dlocal0("); print(head); print(";"); print(body); print(")"))
//
(* ****** ****** *)
//
|I1Ddclenv
(idcl, i0ws) =>
(print("I1Ddclenv("); print(idcl); print(";"); print(i0ws); print(")"))
//
|I1Dtmpsub
(svts, idcl) =>
(print("I1Dtmpsub("); print(svts); print(";"); print(idcl); print(")"))
//
(* ****** ****** *)
//
|I1Dinclude
( knd0, tknd
, gsrc, fopt, dopt ) =>
(
print("I1Dinclude(");
(print(knd0); print(";"); print(tknd); print(";"); print(gsrc); print(";"); print(fopt); print(";"); print("..."); print(")")))
//
(* ****** ****** *)
//
|
I1Dvaldclst
(tknd, i1vs) =>
(print("I1Dvaldclst("); print(tknd); print(";"); print(i1vs); print(")"))
|
I1Dvardclst
(tknd, i1vs) =>
(print("I1Dvardclst("); print(tknd); print(";"); print(i1vs); print(")"))
//
|
I1Dfundclst
( tknd
, lvl0, tqas
, d2cs, i1fs) =>
(
print("I1Dfundclst(");
(print(tknd); print(";"); print(lvl0); print(";"));
(print(tqas); print(";"); print(d2cs); print(";"); print(i1fs); print(")")))
//
(* ****** ****** *)
//
|
I1Dimplmnt0
(tknd
,lvl0
,stmp, dimp
,farg, body) =>
( print("I1Dimplmnt0(")
; (print(tknd); print(";"); print(lvl0); print(";"); print(stmp); print(";"))
; (print(dimp); print(";"); print(farg); print(";"); print(body); print(")")))
//
(* ****** ****** *)
//
|I1Dnone0() => (print("I1Dnone0("); print(")"))
|I1Dnone1(dcl1) => (print("I1Dnone1("); print(dcl1); print(")"))
//
(* ****** ****** *)
//
end(*let*)//end-of-[i1dcl_fprint(dcl0,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1valdcl_fprint
  (ival, out0) = let
//
val dpat =
i1valdcl_dpat$get(ival)
val tdxp =
i1valdcl_tdxp$get(ival)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("I1VALDCL("); print(dpat); print(";"); print(tdxp); print(")")))
end(*let*)//end-of-[i1valdcl_fprint(ival,out0)]
//
(* ****** ****** *)
//
#implfun
i1vardcl_fprint
  (ivar, out0) = let
//
val dpid =
i1vardcl_dpid$get(ivar)
val dini =
i1vardcl_dini$get(ivar)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("I1VARDCL("); print(dpid); print(";"); print(dini); print(")")))
end(*let*)//end-of-[i1vardcl_fprint(ivar,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1fundcl_fprint
  (ifun, out0) = let
//
val dpid =
i1fundcl_dpid$get(ifun)
val farg =
i1fundcl_farg$get(ifun)
val tdxp =
i1fundcl_tdxp$get(ifun)
//
#impltmp g_print$out<>() = out0
//
in//let
(
(print("I1FUNDCL("); print(dpid); print(";"); print(farg); print(";"); print(tdxp); print(")")))
end(*let*)//end-of-[i1fundcl_fprint(ifun,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1parsed_fprint
  (ipar, out0) = let
//
val
stadyn =
i1parsed_stadyn$get(ipar)
val
nerror =
i1parsed_nerror$get(ipar)
val
source =
i1parsed_source$get(ipar)
val
parsed =
i1parsed_parsed$get(ipar)
//
#impltmp g_print$out<>() = out0
//
in//let
(
print("I1PARSED(");
(print(stadyn); print(";"); print(nerror); print(";"); print(source); print(";"); print(parsed); print(")")))
end(*let*)//end-of-[i1parsed_fprint(ipar,out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2js_srcgen2_DATS_intrep1_print0.dats] *)
(***********************************************************************)
