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
Sat 27 Aug 2022 02:13:22 AM EDT
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
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
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
(* ****** ****** *)
#staload
_(*?*) = "./lexing0_print0.dats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp1.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
(* ****** ****** *)
(* ****** ****** *)
#symload name with s2cst_get_name
#symload lctn with s2cst_get_lctn
(* ****** ****** *)
#symload node with s2arg_get_node
(* ****** ****** *)
#symload node with s2exp_get_node
#symload sort with s2exp_get_sort
(* ****** ****** *)
#symload node with l2s2e_get_node
(* ****** ****** *)
(* ****** ****** *)

#implfun
t2abs_fprint
( tabs, out ) =
let
//
#impltmp
g_print$out<>() = out
//
val sym =
  t2abs_get_name(tabs)
val tmp =
  t2abs_get_stmp(tabs)
//
in//let
  (print(sym); print("("); print(tmp); print(")"))
end(*let*)//end-of-[t2abs_fprint(tabs,out)]

(* ****** ****** *)

#implfun
t2dat_fprint
( tdat, out ) =
let
//
#impltmp
g_print$out<>() = out
//
val sym =
  t2dat_get_name(tdat)
val tmp =
  t2dat_get_stmp(tdat)
//
in//let
  (print(sym); print("("); print(tmp); print(")"))
end(*let*)//end-of-[t2dat_fprint(tdat,out)]

(* ****** ****** *)

#implfun
t2bas_fprint
( tbas, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ tbas of
T2Bpred(name) =>
(print("T2Bpred("); print(name); print(")"))
|
T2Btabs(tabs) =>
(print("T2Btabs("); print(tabs); print(")"))
|
T2Btdat(tdat) =>
(print("T2Btdat("); print(tdat); print(")"))
|
T2Bimpr(knd0, name) =>
(print("T2Bimpr("); print(knd0); print(";"); print(name); print(")"))
end (*let*)//end-of-[t2bas_fprint(tbas,out)]

(* ****** ****** *)

#implfun
sort2_fprint
( s2t0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+ s2t0 of
|
S2Tid0(tid) =>
(print("S2Tid0("); print(tid); print(")"))
|
S2Tint(int) =>
(print("S2Tint("); print(int); print(")"))
//
|
S2Tbas(t2b) =>
(print("S2Tbas("); print(t2b); print(")"))
//
|
S2Ttup(s2ts) =>
(print("S2Ttup("); print(s2ts); print(")"))
//
|
S2Tfun0(  ) =>
(print("S2Tfun0("); print(")"))
|
S2Tfun1(s2ts,s2t1) =>
(print("S2Tfun1("); print(s2ts); print(";"); print(s2t1); print(")"))
//
|
S2Tapps(s2f0,s2ts) =>
(print("S2Tapps("); print(s2f0); print(";"); print(s2ts); print(")"))
//
|
S2Tnone0() =>
(
  (print("S2Tnone0("); print(")")))
|
S2Tnone1(s1t1) =>
(
  (print("S2Tnone1("); print(s1t1); print(")")))
//
|
S2Terrck(lvl0,s2t1) =>
(
  (print("S2Terrck("); print(lvl0); print(";"); print(s2t1); print(")")))
//
end (*let*) // end of [sort2_fprint(s2t0,out)]

(* ****** ****** *)

#implfun
s2arg_fprint
( s2a0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s2a0.node() of
|S2Avar(s2v1) =>
(
  (print("S2Avar("); print(s2v1); print(")")))
|S2Atck(s2v1, s2t2) =>
(
  (print("S2Atck("); print(s2v1); print(";"); print(s2t2); print(")")))
//
end (*let*) // end of [s2arg_fprint(s2a0,out)]
//
(* ****** ****** *)

#implfun
s2tex_fprint
( s2tx, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+ s2tx of
|
S2TEXsrt(s2t1) =>
(print("S2TEXsrt("); print(s2t1); print(")"))
|
S2TEXsub(s2vs, s2ps) =>
(print("S2TEXsub("); print(s2vs); print(";"); print(s2ps); print(")"))
//
end (*let*) // end of [s2tex_fprint(s2tx,out)]

(* ****** ****** *)

#implfun
s2cst_fprint
( s2c0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
  print(s2cst_get_name(s2c0))
(*
; prints
  ("(", s2cst_get_stmp(s2c0), ")")
; prints(":", s2cst_get_sort(s2c0))
*)
end (*let*)//end of [s2cst_fprint(s2c0,out)]

(* ****** ****** *)

#implfun
s2var_fprint
( s2v0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
  print(s2var_get_name(s2v0))
; (print("["); print(s2v0.stmp()); print("]"))
(*
; prints("[", s2v0.sort(), "]")
*)
end (*let*) // end of [s2var_fprint(s2v0,out)]

(* ****** ****** *)

#implfun
s2exp_fprint
( s2e0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s2e0.node() of
//
|S2Eint(int) =>
(print("S2Eint("); print(int); print(")"))
|S2Ebtf(btf) =>
(print("S2Ebtf("); print(btf); print(")"))
|S2Echr(chr) =>
(print("S2Echr("); print(chr); print(")"))
|S2Estr(str) =>
(print("S2Estr("); print(str); print(")"))
//
|S2Ecst(s2c) =>
(print("S2Ecst("); print(s2c); print(")"))
|S2Evar(s2v) =>
(print("S2Evar("); print(s2v); print(")"))
//
|
S2Eany(knd) =>
(print("S2Eany("); print(knd); print(")"))
//
|S2Etop0(s2e) =>
(print("S2Etop0("); print(s2e); print(")"))
|S2Etop1(s2e) =>
(print("S2Etop1("); print(s2e); print(")"))
//
|
S2Ecsts(s2cs) =>
(
(print("S2Ecsts("); print(s2cs); print(")"))
) where
{
#impltmp
g_print<s2cst>(x) =
(print(x.name()); print("("); print(x.lctn()); print(")"))
}
//
|
S2Earg1(knd0,s2e1) =>
(print("S2Earg1("); print(knd0); print(";"); print(s2e1); print(")"))
|
S2Eatx2(s2e1,s2e2) =>
(print("S2Eatx2("); print(s2e1); print(";"); print(s2e2); print(")"))
//
|
S2Eapps(s2f0,s2es) =>
(print("S2Eapps("); print(s2f0); print(";"); print(s2es); print(")"))
|
S2Elam1(s2vs,s2e1) =>
(print("S2Elam1("); print(s2vs); print(";"); print(s2e1); print(")"))
//
|
S2Efun1
( f2cl
, npf1, s2es, s2r0) =>
(
(print("S2Efun1("); print(f2cl); print(";"));
(print(npf1); print(";"); print(s2es); print(";"); print(s2r0); print(")")) )
//
|
S2Emet0(s2es,s2e1) =>
(print("S2Emet0("); print(s2es); print(";"); print(s2e1); print(")"))
//
|
S2Eexi0
(s2vs, s2ps, s2e1) =>
( print("S2Eexi0(")
; (print(s2vs); print(";"); print(s2ps); print(";"); print(s2e1); print(")")))
|
S2Euni0
(s2vs, s2ps, s2e1) =>
( print("S2Euni0(")
; (print(s2vs); print(";"); print(s2ps); print(";"); print(s2e1); print(")")))
//
|
S2Elist(s2es) =>
(print("S2Elist("); print(s2es); print(")"))
|
S2Etype(s2tp) =>
(print("S2Etype("); print(s2tp); print(")"))
//
|
S2Etext(name, s2es) =>
(print("S2Etext("); print(name); print(";"); print(s2es); print(")"))
//
|
S2Etrcd
(knd0, npf1, lses) =>
(print("S2Etrcd("); print(knd0); print(";"); print(npf1); print(";"); print(lses); print(")"))
//
|
S2Eimpr(loc0,s2e1) =>
(print("S2Eimpr("); print(loc0); print(";"); print(s2e1); print(")"))
|
S2Eprgm(loc0,s2e1) =>
(print("S2Eprgm("); print(loc0); print(";"); print(s2e1); print(")"))
//
|
S2Ecast
(loc0, s2e1, s2t2) =>
let
val
s2t1 = s2e1.sort()
in
  prints // prints
  ("S2Ecast(",loc0,";")
; (print(s2e1); print(";"); print(s2t1); print(";"); print(s2t2); print(")"))
endlet
//
|
S2Enone0() => (print("S2Enone0("); print(")"))
|
S2Enone1(s1e1) => (print("S2Enone1("); print(s1e1); print(")"))
|
S2Enone2(s2e1) => (print("S2Enone2("); print(s2e1); print(")"))
//
|S2Eerrck // HX: tread-error
(lvl0,s2e1) => (print("S2Eerrck("); print(lvl0); print(";"); print(s2e1); print(")"))
//
end (*let*) // end of [ s2exp_fprint(s2e0,out) ]

(* ****** ****** *)
//
#implfun
s2itm_fprint
( s2i0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+ s2i0 of
//
|
S2ITMvar(s2v1) =>
(print("S2ITMvar("); print(s2v1); print(")"))
|
S2ITMcst(s2cs) =>
(print("S2ITMcst("); print(s2cs); print(")"))
//
|
S2ITMenv(envs) =>
(print("S2ITMenv("); print("..."); print(")"))
//
end (*let*) // end of [s2itm_fprint(s2i0,out)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_staexp2_print0.dats] *)
(***********************************************************************)
