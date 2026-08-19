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
Start Time: June 08th, 2022
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
#staload "./../SATS/staexp0.sats"
(* ****** ****** *)

#implfun
t0int_fprint
( int, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ int of
|
T0INTnone(tok) =>
(print("T0INTnone("); print(tok); print(")"))
|
T0INTsome(tok) =>
(print("T0INTsome("); print(tok); print(")"))
end (*let*) // end of [t0int_fprint]

(* ****** ****** *)

#implfun
t0chr_fprint
( chr, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ chr of
|
T0CHRnone(tok) =>
(print("T0CHRnone("); print(tok); print(")"))
|
T0CHRsome(tok) =>
(print("T0CHRsome("); print(tok); print(")"))
end (*let*) // end of [t0chr_fprint]

(* ****** ****** *)

#implfun
t0flt_fprint
( flt, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ flt of
|
T0FLTnone(tok) =>
(print("T0FLTnone("); print(tok); print(")"))
|
T0FLTsome(tok) =>
(print("T0FLTsome("); print(tok); print(")"))
end (*let*) // end of [t0flt_fprint]

(* ****** ****** *)

#implfun
t0str_fprint
( str, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ str of
|
T0STRnone(tok) =>
(print("T0STRnone("); print(tok); print(")"))
|
T0STRsome(tok) =>
(print("T0STRsome("); print(tok); print(")"))
end (*let*) // end of [t0str_fprint]

(* ****** ****** *)

#implfun
i0dnt_fprint
( id0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+
id0.node() of
|
I0DNTnone(tok) =>
(print("I0DNTnone("); print(tok); print(")"))
|
I0DNTsome(tok) =>
(print("I0DNTsome("); print(tok); print(")"))
end (*let*) // end of [i0dnt_fprint]

(* ****** ****** *)

#implfun
l0abl_fprint
( lab, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+
lab.node() of
|
L0ABLnone(tok) =>
(print("L0ABLnone("); print(tok); print(")"))
|
L0ABLsome(lab) =>
(print("L0ABLsome("); print(lab); print(")"))
end (*let*) // end of [l0abl_fprint]

(* ****** ****** *)

#implfun
s0ymb_fprint
( sym, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+
sym.node() of
|
S0YMBi0dnt(id0) =>
(print("S0YMBi0dnt("); print(id0); print(")"))
(*
|
S0YMBdtlab of (token, l0abl)
*)
|
S0YMBbrckt(tk1, tk2) =>
(print("S0YMBbrckt("); print(tk1); print(";"); print(tk2); print(")"))
end (*let*) // end of [s0ymb_fprint]

(* ****** ****** *)

(*
fun
<x0:type>
s0lab_fprint
(out: FILR, lab: s0lab(x0)): void
*)

(* ****** ****** *)
//
#implfun
s0qid_fprint
( qid, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ qid of
|
S0QIDnone(id0) =>
(print("S0QIDnone("); print(id0); print(")"))
|
S0QIDsome(tok, id0) =>
(print("S0QIDsome("); print(tok); print(";"); print(id0); print(")"))
end (*let*) // end of [s0qid_fprint]
//
#implfun
d0qid_fprint
( qid, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ qid of
|
D0QIDnone(id0) =>
(print("D0QIDnone("); print(id0); print(")"))
|
D0QIDsome(tok, id0) =>
(print("D0QIDsome("); print(tok); print(";"); print(id0); print(")"))
end (*let*) // end of [d0qid_fprint]
//
(* ****** ****** *)

#implfun
g0nam_fprint
( g0n, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
g0n.node() of
//
|
G0Nid0(id0) =>
(print("G0Nid0("); print(id0); print(")"))
//
|
G0Nint(tok) =>
(print("G0Nint("); print(tok); print(")"))
|
G0Nchr(tok) =>
(print("G0Nchr("); print(tok); print(")"))
|
G0Nflt(tok) =>
(print("G0Nflt("); print(tok); print(")"))
|
G0Nstr(tok) =>
(print("G0Nstr("); print(tok); print(")"))
//
|
G0Nlist(tk1, gns, tk2) =>
(
print("G0Nlist(");
(print(tk1); print(";"); print(gns); print(";"); print(tk2); print(")")))
//
(*
|
G0Nnone0(   ) => prints("G0Nnone0(", ")")
*)
|
G0Ntkerr(tok) =>
(
  (print("G0Ntkerr("); print(tok); print(")")))//G0Ntkerr
//
end (*let*) // end of [g0nam_fprint(g0n,out)]

(* ****** ****** *)

#implfun
g0exp_fprint
( g0e, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
g0e.node() of
|
G0Eid0(id0) =>
(print("G0Eid0("); print(id0); print(")"))
//
|
G0Eint(tok) =>
(print("G0Eint("); print(tok); print(")"))
|
G0Echr(tok) =>
(print("G0Echr("); print(tok); print(")"))
|
G0Eflt(tok) =>
(print("G0Eflt("); print(tok); print(")"))
|
G0Estr(tok) =>
(print("G0Estr("); print(tok); print(")"))
//
|
G0Eapps(ges) =>
(print("G0Eapps("); print(ges); print(")"))
|
G0Elpar(tkb, ges, tke) =>
(
print("G0Elpar(");
(print(tkb); print(";"); print(ges); print(","); print(tke); print(")")))
//
|
G0Eift0
(tknd,g0e1,g0e2,g0e3,topt) =>
(
(print("G0Eift0("); print(tknd); print(";"));
(print(g0e1); print(";"); print(g0e2); print(";"); print(g0e3); print(";"); print(topt); print(")")))
//
|
G0Etkerr(tok) =>
(
  (print("G0Etkerr("); print(tok); print(")")))//tkerr
//
|
G0Eerrck
(lvl(*err*),ge1) =>
(
(print("G0Eerrck("); print(lvl); print(";"); print(ge1); print(")")))//errck
//
end (*let*) // end of [g0exp_fprint(g0e,out)]

(* ****** ****** *)

#implfun
g0mag_fprint
( gma, out ) =
(
case+
gma.node() of
|
G0MAGnone(tok) =>
(print("G0MAGnone("); print(tok); print(")"))
|
G0MAGsarg
(tbeg,g0as,tend) =>
(print("G0MAGsarg("); print(tbeg); print(";"); print(g0as); print(";"); print(tend); print(")"))
|
G0MAGdarg
(tbeg,g0as,tend) =>
(print("G0MAGdarg("); print(tbeg); print(";"); print(g0as); print(";"); print(tend); print(")"))
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [g0mag_fprint(gma,out)]

(* ****** ****** *)

#implfun
sort0_fprint
( s0t, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s0t.node() of
|
S0Tid0(id0) =>
(print("S0Tid0("); print(id0); print(")"))
//
|
S0Tint(int) =>
(print("S0Tint("); print(int); print(")"))
//
// HX: qualified
|
S0Tqid(tk1,st2) =>
(print("S0Tqid("); print(tk1); print(";"); print(st2); print(")"))
//
|
S0Tapps(sts) =>
(print("S0Tapps("); print(sts); print(")"))
//
|
S0Tlpar(tkb,sts,tke) =>
(print("S0Tlpar("); print(tkb); print(";"); print(sts); print(";"); print(tke); print(")"))
//
(*
|
S0Ttype of int(*kind*)
// prop/view/type/tbox/tflt/vwtp/vtbx/vtft
*)
|
S0Ttkerr(tok) =>
(
  (print("S0Ttkerr("); print(tok); print(")")))
|
S0Terrck
(lvl(*err*),st1) =>
(
  (print("S0Terrck("); print(lvl); print(";"); print(st1); print(")")))
//
end (*let*)//end-of-[sort0_fprint(s0t,out)]

(* ****** ****** *)

#implfun
s0tcn_fprint
( stcn, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
stcn.node() of
|
S0TCNnode(id0, stq) =>
(print("S0TCNnode("); print(id0); print(";"); print(stq); print(")"))
end (*let*) // end of [s0tcn_fprint(...)]

(* ****** ****** *)

#implfun
d0tst_fprint
( dtst, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
dtst.node() of
|
D0TSTnode(tid0,teq1,topt,stcs) =>
(
(print("D0TSTnode("); print(tid0));
(print(";"); print(teq1); print(";"); print(topt); print(";"); print(stcs); print(")")))
end (*let*) // end of [d0tst_fprint(...)]

(* ****** ****** *)

#implfun
s0arg_fprint
( s0a, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s0a.node() of
|
S0ARGnone(tok) =>
(print("S0ARGnone("); print(tok); print(")"))
|
S0ARGsome(id0, tres) =>
(print("S0ARGsome("); print(id0); print(";"); print(tres); print(")"))
//
end (*let*) // end of [s0arg_fprint]

(* ****** ****** *)

#implfun
t0arg_fprint
( t0a, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
t0a.node() of
|
T0ARGnone(tok) =>
(print("T0ARGnone("); print(tok); print(")"))
|
T0ARGsome(s0t1, topt) =>
(print("T0ARGsome("); print(s0t1); print(";"); print(topt); print(")"))
//
end (*let*) // end of [t0arg_fprint(out,t0a)]

(* ****** ****** *)

#implfun
s0mag_fprint
( s0m, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s0m.node() of
|
S0MAGnone(tok) =>
(print("S0MAGnone("); print(tok); print(")"))
|
S0MAGsing(id0) =>
(print("S0MAGsing("); print(id0); print(")"))
|
S0MAGlist(tbeg, s0as, tend) =>
(print("S0MAGlist("); print(tbeg); print(";"); print(s0as); print(";"); print(tend); print(")"))
//
end (*let*)//end of [s0mag_fprint(s0m,out)]

(* ****** ****** *)

#implfun
t0mag_fprint
( t0m, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
t0m.node() of
|
T0MAGnone(tok) =>
(print("T0MAGnone("); print(tok); print(")"))
(*
|
T0MAGsing(id0) =>
prints("T0MAGsing(", id0, ")")
*)
|
T0MAGlist(tbeg, t0as, tend) =>
(print("T0MAGlist("); print(tbeg); print(";"); print(t0as); print(";"); print(tend); print(")"))
//
end (*let*)//end of [t0mag_fprint(t0m,out)]

(* ****** ****** *)

#implfun
s0qua_fprint
( s0q, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s0q.node() of
|
S0QUAprop(s0e) =>
(print("S0QUAprop("); print(s0e); print(")"))
|
S0QUAvars(ids, tres) =>
(print("S0QUAvars("); print(ids); print(";"); print(tres); print(")"))
//
end (*let*)//end of [s0qua_fprint(s0q,out)]

(* ****** ****** *)
//
#implfun
s0uni_fprint
( s0u, out ) =
let
//
#impltmp
g_print$out<>() = out
//
in//let
//
case+
s0u.node() of
|S0UNInone(tok) =>
(
(print("S0UNInone("); print(tok); print(")")))
|S0UNIsome(tbeg, s0qs, tend) =>
(
(print("S0UNIsome("); print(tbeg); print(";"); print(s0qs); print(";"); print(tend); print(")")))
//
end (*let*) // end of [s0uni_fprint(s0u,out)]
//
(* ****** ****** *)
//
#implfun
s0exp_fprint
( s0e, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s0e.node() of
|
S0Eid0(id0) =>
(print("S0Eid0("); print(id0); print(")"))
//
|
S0Eop1(tok) =>
(print("S0Eop1("); print(tok); print(")"))
|
S0Eop2(tok) =>
(print("S0Eop2("); print(tok); print(")"))
|
S0Eop3(tkb,id0,tke) =>
(
(print("S0Eop3("); print(tkb); print(";"); print(id0); print(";"); print(tke); print(")")))
//
|
S0Eint(int) => (print("S0Eint("); print(int); print(")"))
|
S0Echr(chr) => (print("S0Echr("); print(chr); print(")"))
|
S0Eflt(flt) => (print("S0Eflt("); print(flt); print(")"))
|
S0Estr(str) => (print("S0Estr("); print(str); print(")"))
//
|
S0Eapps(ses) => (print("S0Eapps("); print(ses); print(")"))
//
|
S0Efimp
(tkb,ses,tke) =>
(
(print("S0Efimp("); print(tkb); print(";"); print(ses); print(";"); print(tke); print(")")))
//
|
S0Elpar
(tkb,ses,srp) =>
(
(print("S0Elist("); print(tkb); print(";"); print(ses); print(";"); print(srp); print(")")))
//
|
S0Etup1
(tkb,opt,ses,srp) =>
(
print("S0Etup1(");
(print(tkb); print(";"); print(opt); print(";"); print(ses); print(";"); print(srp); print(")")))
//
|
S0Ercd2
(tkb,opt,lses,lsrb) =>
(
print("S0Ercd2(");
(print(tkb); print(";"); print(opt); print(";"); print(lses); print(";"); print(lsrb); print(")")))
//
|
S0Elams
(tlam,s0ms
,tres,arrw,body,tend) =>
(
print("S0Elams(");
(print(tlam); print(";"); print(s0ms); print(";"));
(print(tres); print(";"); print(arrw); print(";"); print(body); print(";"); print(tend); print(")")))
//
|
S0Euni0(tkb,sqs,tbe) =>
(
(print("S0Euni0("); print(tkb); print(";"); print(sqs); print(";"); print(tbe); print(")")))
|
S0Eexi0(tkb,sqs,tbe) =>
(
(print("S0Eexi0("); print(tkb); print(";"); print(sqs); print(";"); print(tbe); print(")")))
|
S0Eannot(se1,st2) =>
(
// HX: annotation
  (print("S0Eannot("); print(se1); print(";"); print(st2); print(")")))
|
S0Equal0(tok,se1) =>
(
// HX: qual-s0exp
  (print("S0Equal0("); print(tok); print(";"); print(se1); print(")")))
//
|
S0Etkerr(tok) =>
(
  (print("S0Etkerr("); print(tok(*error*)); print(")")))
|
//
// HX: [S0Eerrck]:
// syntax error confirmed by checking
//
S0Eerrck
(lvl(*err-level*),se1) =>
(
  (print("S0Eerrck("); print(lvl); print(";"); print(se1); print(")")))
//
end (*let*) // end-of-[ s0exp_fprint(s0e,out) ]
//
(* ****** ****** *)
//
#implfun
s0tdf_fprint
( stdf, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
stdf.node() of
|
S0TDFsort(s0t1) =>
(
(print("S0TDFsort("); print(s0t1); print(")")))
|
S0TDFtsub
(tbeg,s0a1
,tbar,s0es,tend) =>
(
print("S0TDFtsub(");
(print(tbeg); print(";"); print(s0a1); print(";"));
(print(tbar); print(";"); print(s0es); print(";"); print(tend); print(")")) )
//
end (*let*) // end of [s0tdf_fprint(stdf,out)]
//
(* ****** ****** *)
//
#implfun
g0exp_THEN_fprint
  ( gthn, out ) =
(
case+ gthn of
|
g0exp_THEN(tok, g0e) =>
(print("g0exp_THEN("); print(tok); print(";"); print(g0e); print(")"))
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [g0exp_THEN_fprint(gthn,out)]
#implfun
g0exp_ELSE_fprint
  ( gels, out ) =
(
case+ gels of
|
g0exp_ELSE(tok, g0e) =>
(print("g0exp_ELSE("); print(tok); print(";"); print(g0e); print(")"))
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [g0exp_ELSE_fprint(gels,out)]
//
(* ****** ****** *)
//
#implfun
s0exp_RPAREN_fprint
  ( srp, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ srp of
|s0exp_RPAREN_cons0(tbar) =>
(
 (print("s0exp_RPAREN_cons0("); print(tbar); print(")")))
|s0exp_RPAREN_cons1(tok1, s0es, tok2) =>
(
 (print("s0exp_RPAREN_cons1("); print(tok1); print(";"); print(s0es); print(";"); print(tok2); print(")")))
end (*let*) // end of [s0exp_RPAREN_fprint(srp,out)]
//
(* ****** ****** *)
//
#implfun
l0s0e_RBRACE_fprint
  ( lsrb, out ) =
let
//
#impltmp
g_print$out<>() = out
//
in//let
case+ lsrb of
|l0s0e_RBRACE_cons0(tbar) =>
(
 (print("l0s0e_RBRACE_cons0("); print(tbar); print(")")))
|l0s0e_RBRACE_cons1(tok1, lses, tok2) =>
(
 (print("l0s0e_RBRACE_cons1("); print(tok1); print(";"); print(lses); print(";"); print(tok2); print(")")))
end (*let*) // end of [l0s0e_RBRACE_fprint(lsrb,out)]
//
(* ****** ****** *)
//
#implfun
d0tcn_fprint
( dtcn, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
dtcn.node() of
|D0TCNnode
(s0us, deid, s0is, tres) =>
(
print("D0TCNnode(");
(print(s0us); print(";"); print(deid); print(";"); print(s0is); print(";"); print(tres); print(")")))
end (*let*) // end of [d0tcn_fprint(dtcn,out)]
//
(* ****** ****** *)
//
#implfun
d0typ_fprint
( dtyp, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
dtyp.node() of
|D0TYPnode
(deid, tmas, tres, teq1, dtcs) =>
(
(print("D0TYPnode("); print(deid); print(";"));
(print(tmas); print(";"); print(tres); print(";"); print(teq1); print(";"); print(dtcs); print(")")))
end (*let*) // end of [d0typ_fprint(dtyp,out)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_staexp0_print0.dats] *)
(***********************************************************************)
