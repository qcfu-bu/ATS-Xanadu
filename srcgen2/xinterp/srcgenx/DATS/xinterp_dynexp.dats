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
Tue Nov 28 12:33:03 EST 2023
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dats.hats"
(* ****** ****** *)
//
#include
"./../HATS/libxinterp.hats"
//
(* ****** ****** *)
//
#include
"./../HATS/xinterp_dats.hats"
//
(* ****** ****** *)
#staload "./../SATS/intrep0.sats"
(* ****** ****** *)
#staload "./../SATS/xinterp.sats"
(* ****** ****** *)
#staload
_(*DATS*)="./../DATS/xinterp.dats"
(* ****** ****** *)
#symload lctn with irpat_get_lctn
#symload node with irpat_get_node
(* ****** ****** *)
#symload lctn with irexp_get_lctn
#symload node with irexp_get_node
(* ****** ****** *)
#symload lctn with irdcl_get_lctn
#symload node with irdcl_get_node
(* ****** ****** *)
(* ****** ****** *)
//
fun
irexp_lam0
( loc0
: loctn
, tknd
: token
, fias
: fiarglst
, ire1: irexp): irexp =
(
case+ fias of
|
list_nil() => ire1
|
list_cons _ =>
irexp_make_node
( loc0
, IRElam0(tknd, fias, ire1)))
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
xinterp_irexp
  (env0, ire0) =
(
case+
ire0.node() of
//
|IREint(tok) =>
(
 IRVint(token2dint(tok)))
|IREbtf(sym) =>
(
 IRVbtf(symbl2dbtf(sym)))
|IREchr(tok) =>
(
 IRVchr(token2dchr(tok)))
|IREstr(tok) =>
(
 IRVstr(token2dstr(tok)))
//
|IREvar _ => f0_var(env0, ire0)
|IREcon _ => f0_con(env0, ire0)
|IREcst _ => f0_cst(env0, ire0)
//
|IREtimp _ => f0_timp(env0, ire0)
//
|IREdapp _ => f0_dapp(env0, ire0)
//
|IRElet0 _ => f0_let0(env0, ire0)
//
|IREift0 _ => f0_ift0(env0, ire0)
//
|IREtup0 _ => f0_tup0(env0, ire0)
|IREtup1 _ => f0_tup1(env0, ire0)
//
|IRElam0 _ => f0_lam0(env0, ire0)
|IREfix0 _ => f0_fix0(env0, ire0)
//
|
IREwhere _ => f0_where(env0, ire0)
//
|
_(*otherwise*) =>
(
  $raise XINTERP_IREXP(ire0)
) where
{
//
val loc0 = ire0.lctn((*void*))
val (  ) = prerrln
("xinterp_irexp: loc0 = ", loc0)
val (  ) = prerrln
("xinterp_irexp: ire0 = ", ire0) }//whr
//
) where // end of [ case+of(ire0.node()) ]
{
//
(* ****** ****** *)
excptcon
XINTERP_IREXP of irexp
(* ****** ****** *)
//
fun
f0_var
( env0:
! xintenv
, ire0: irexp): irval =
let
val-
IREvar(d2v0) = ire0.node()
in//let
//
(
case+ opt0 of
| ~
optn_nil((*0*)) =>
the_irvar_search(d2v0)
| ~
optn_cons(irv0) => irv0) where
{
val opt0 =
xintenv_d2vrch_opt(env0, d2v0) }
//
end(*let*)//end-of-[f0_var(env0,ire0)]
//
(* ****** ****** *)
//
fun
f0_con
( env0:
! xintenv
, ire0: irexp): irval =
(
IRVcon(d2c0) ) where
{
val-
IREcon(d2c0) = ire0.node()
}
//
(* ****** ****** *)
//
fun
f0_cst
( env0:
! xintenv
, ire0: irexp): irval =
let
val-
IREcst(d2c0) = ire0.node()
in//let
//
(
case+ opt0 of
| ~
optn_nil((*0*)) =>
the_ircst_search(d2c0)
| ~
optn_cons(irv0) => irv0) where
{
val opt0 =
xintenv_d2crch_opt(env0, d2c0) }
//
end(*let*)//end-of-[f0_cst(env0,ire0)]
//
(* ****** ****** *)
//
fun
f0_timp
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREtimp
(dcst, ird0) = ire0.node()
//
in//let
//
(
f1_impl(env0, ird0)) where
{
//
fun
f1_impl
( env0:
! xintenv
, ird0: irdcl): irval =
(
case+
ird0.node() of
//
|IRDtmpsub
(svts, ird1) =>
f1_impl(env0, ird1)
|IRDimplmnt0 _ =>
f2_impl(env0, ird0)
//
|_(*otherise*) => IRVnone0(*0*))
//
and
f2_impl
( env0:
! xintenv
, ird0: irdcl): irval =
let
val
IRDimplmnt0
( tknd
, stmp
, sqas, tqas
, dimp, t2is
, fias, ire1) = ird0.node()
in//let
//
case+ fias of
|
list_nil() =>
(
xinterp_irexp(env0, ire1))
|
list_cons(fia1, fias) =>
let
//
val
fenv = xintenv_snap(env0)
in//let
//
(
IRVlam0(fia1, body, fenv)) where
{
//
val loc0 = ird0.lctn()
val body =
  irexp_lam0(loc0,tknd,fias,ire1)
} endlet // end-of-[list_cons( ... )]
//
end(*let*)//end-of-[f2_impl(env0,ire0)]
//
}
//
end(*let*)//end-of-[f0_timp(env0,ire0)]
//
(* ****** ****** *)
//
fun
f0_dapp
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREdapp
( irf0, ires) = ire0.node()
//
val irf0 =
(
  xinterp_irexp(env0, irf0))
val irvs =
(
  xinterp_irexplst(env0, ires))
//
in//let
//
case+ irf0 of
//
|IRVfun _ => f1_fun(irf0, irvs)
//
|IRVcon _ => f1_con(irf0, irvs)
//
|IRVlam0 _ => f1_lam0(irf0, irvs)
|IRVfix0 _ => f1_fix0(irf0, irvs)
//
|_(*otherwise*) =>
(
$raise XINTERP_IREXP(ire0)) where
{
//
val () =
prerrln
("\
xinterp_irexp:f0_dapp: irf0 = ", irf0)
val () =
prerrln
("\
xinterp_irexp:f0_dapp: ire0 = ", ire0)
//
}
//
end where
{
//
(* ****** ****** *)
//
fun
f1_fun
( irf0: irval
, irvs: irvalist): irval =
let
val-
IRVfun
(fopr) = irf0 in fopr(irvs)//val-
end(*let*)//end-of-[f1_con(irf0,irvs)]
//
(* ****** ****** *)
//
fun
f1_con
( irf0: irval
, irvs: irvalist): irval =
let
val-
IRVcon(d2c1) = irf0
in//let
(
  IRVcapp(d2c1, irvs)) where
{
val irvs = a1rsz_make_list(irvs) }
end(*let*)//end-of-[f1_fun(irf0,irvs)]
//
(* ****** ****** *)
//
fun
f1_lam0
( irf0: irval
, irvs: irvalist): irval =
let
//
val-
IRVlam0
( farg
, body, fenv) = irf0
//
val
env1 =
xintenv_make_dapp(env0, fenv)
//
val () =
fiarg_match(env1, farg, irvs)
//
in//let
//
let
val
dres =
xinterp_irexp
( env1, body )
val () =
xintenv_free_dapp(env1) in dres end
//
end(*let*)//end-of-[f1_lam0(irf0,irvs)]
//
(* ****** ****** *)
//
fun
f1_fix0
( irf0: irval
, irvs: irvalist): irval =
let
//
val-
IRVfix0
( dpid
, farg
, body, fenv) = irf0
//
val
env1 =
xintenv_make_dapp(env0, fenv)
//
val () =
irvar_match(env1, dpid, irf0)
val () =
fiarg_match(env1, farg, irvs)
//
in//let
//
let
val
dres =
xinterp_irexp
( env1, body )
val () =
xintenv_free_dapp(env1) in dres end
//
end(*let*)//end-of-[f1_fix0(irf0,irvs)]
//
(* ****** ****** *)
(* ****** ****** *)
//
}(*where*)//end-of-[f0_dapp(env0,d3e0)]
//
(* ****** ****** *)
//
fun
f0_let0
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IRElet0
( irds, ire1) = ire0.node()
//
val () =
xintenv_pshlet0(env0)
val () =
xinterp_irdclist(env0, irds)
//
in//let
let
val
dres =
xinterp_irexp
(env0 , ire1)
val () =
xintenv_poplet0(env0) in dres end
end(*let*)//end-of-[f0_let0(env0,d3e0)]
//
(* ****** ****** *)
//
fun
f0_ift0
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREift0
( ire1
, ithn, iels) = ire0.node()
val irv1 =
(
  xinterp_irexp(env0, ire1))
//
in//let
//
case- irv1 of
|IRVbtf(btf) =>
(
case+ dopt of
|
optn_nil() =>
IRVnil( (*0*) ) // HX: for void
|
optn_cons(ire2) =>
xinterp_irexp(env0, ire2)) where
{
val
dopt = bool_ifval(btf,ithn,iels) }
//
end(*let*)//end-of-[f0_ift0(env0,d3e0)]
//
(* ****** ****** *)
//
fun
f0_tup0
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREtup0(ires) = ire0.node()
//
in//let
(
  IRVtup0(irvs)) where
{
val
irvs =
xinterp_irexplst(env0, ires)
val irvs = a1rsz_make_list(irvs) }
//
end(*let*)//end-of-[f0_tup0(env0,d3e0)]
//
(* ****** ****** *)
//
fun
f0_tup1
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREtup1
(trec, ires) = ire0.node()
//
in//let
(
IRVtup1(trec, irvs)) where
{
val
irvs =
xinterp_irexplst(env0, ires)
val irvs = a1rsz_make_list(irvs) }
//
end(*let*)//end-of-[f0_tup1(env0,d3e0)]
//
(* ****** ****** *)
//
fun
f0_lam0
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IRElam0
( tknd
, fias, ire1) = ire0.node()
//
in//let
//
case+ fias of
|
list_nil() =>
xinterp_irexp(env0, ire1)
|
list_cons
(fia1, fias) =>
let
//
val
fenv = xintenv_snap(env0)
//
in//let
(
  IRVlam0(fia1, body, fenv)
) where
{
val loc0 = ire0.lctn()
val body =
  irexp_lam0(loc0,tknd,fias,ire1)
} endlet//end-of-[list_cons( ... )]
//
end(*let*)//end-of-[f0_lam0(env0,ire0)]
//
(* ****** ****** *)
//
fun
f0_fix0
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREfix0
( tknd
, d2v0
, fias, ire1) = ire0.node()
//
in//let
//
case+ fias of
|
list_nil() =>
(*
HX-2023-12-14:
this should not happen!
*)
xinterp_irexp(env0, ire1)
|
list_cons
(fia1, fias) =>
let
//
val
fenv = xintenv_snap(env0)
//
in//let
(
  IRVfix0
  (d2v0, fia1, body, fenv)
) where
{
val loc0 = ire0.lctn()
val body =
  irexp_lam0(loc0,tknd,fias,ire1)
} endlet//end-of-[list_cons( ... )]
//
end(*let*)//end-of-[f0_fix0(env0,ire0)]
//
(* ****** ****** *)
//
fun
f0_where
( env0:
! xintenv
, ire0: irexp): irval =
let
//
val-
IREwhere
( ire1, irds) = ire0.node()
//
val () =
xintenv_pshlet0(env0)
val () =
xinterp_irdclist(env0, irds)
//
in//let
let
val
dres =
xinterp_irexp
(env0 , ire1)
val () =
xintenv_poplet0(env0) in dres end
end(*let*)//end-of-[f0_where(env0,d3e0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
val loc0 = ire0.lctn()
val (  ) =
prerrln("xinterp_irexp: loc0 = ", loc0)
val (  ) =
prerrln("xinterp_irexp: ire0 = ", ire0)
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
} (*where*)//end of [xinterp_irexp(env0,ire0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
xinterp_irexplst
( env0, ires ) =
(
list_xinterp_fnp
(env0, ires, xinterp_irexp))//xinterp_irexplst
//
#implfun
xinterp_irexpopt
( env0, dopt ) =
(
optn_xinterp_fnp
(env0, dopt, xinterp_irexp))//xinterp_irexpopt
//
(* ****** ****** *)
(* ****** ****** *)

(* end of [ATS3/XANADU_srcgen2_xinterp_srcgen1_DATS_xintrep_dynexp.dats] *)
