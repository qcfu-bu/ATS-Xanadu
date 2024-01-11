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
Wed Dec 27 11:34:52 EST 2023
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
#include
"./../HATS/xatsopt_dats.hats"
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#staload "./../SATS/locinfo.sats"
(* ****** ****** *)
#staload "./../SATS/xsymmap.sats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
#staload "./../SATS/xglobal.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/statyp2.sats"
#staload "./../SATS/dynexp2.sats"
(* ****** ****** *)
(* ****** ****** *)
#staload "./../SATS/trans34.sats"
(* ****** ****** *)
(* ****** ****** *)

local
//
(* ****** ****** *)
//
datavwtp
linstk =
//
|
linstk_nil of ()
|
linstk_lam0 of linstk
|
linstk_let0 of linstk
|
linstk_dvar of
(d2var(*lin*), linstk)
|
linstk_cons of
(d2var(*lin*), d4lft, linstk)
//
#absimpl linstk_vtbx = linstk
//
(* ****** ****** *)
//
datavwtp
tr34env =
TR34ENV of
(
d2varlst, linstk(*void*))
//
(* ****** ****** *)
#absimpl tr34env_vtbx = tr34env
(* ****** ****** *)
(* ****** ****** *)
in//local
(* ****** ****** *)
(* ****** ****** *)
//
fun
linstk_free_nil
(stk0: ~linstk): void =
(
case-
stk0 of ~linstk_nil() => ())
//
(* ****** ****** *)
//
#implfun
linstk_lamvars
  (  stk0  ) =
(
loop(stk0, list_nil())
) where
{
fun
loop
( stk0:
! linstk
, res1: d2varlst): d2varlst =
(
case- stk0 of
(*
|
linstk_nil
 ( (*0*) ) => res1
|
linstk_let0
 (  stk1  ) => res1
*)
|
linstk_lam0
 (  stk1  ) => res1
|
linstk_dvar
(d2v0, stk1) =>
loop(stk1, list_cons(d2v0, res1))
|
linstk_cons
(d2v0, t2p0, stk1) => loop(stk1, res1)
)
}(*where*)//end-of-[linstk_lamvars(...)]
//
(* ****** ****** *)
//
#implfun
linstk_letvars
  (  stk0  ) =
(
loop(stk0, list_nil())
) where
{
fun
loop
( stk0:
! linstk
, res1: d2varlst): d2varlst =
(
case- stk0 of
(*
|
linstk_nil
 ( (*0*) ) => res1
|
linstk_lam0
 (  stk1  ) => res1
*)
|
linstk_let0
 (  stk1  ) => res1
|
linstk_dvar
(d2v0, stk1) =>
loop(stk1, list_cons(d2v0, res1))
|
linstk_cons
(d2v0, t2p0, stk1) => loop(stk1, res1)
)
}(*where*)//end-of-[linstk_letvars(...)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
tr34env_make_nil
  ((*nil*)) =
(
  TR34ENV
  (d2vs, linstk_nil)) where
{
  val d2vs = list_nil((*void*))
} (*where*)//end of [tr34env_make_nil(...)]
//
(* ****** ****** *)
//
#implfun
tr34env_free_top
  (  env0  ) =
(
case+ env0 of
| ~
TR34ENV
(d2vs, map2) => d2vs where
{
//
var
linstk = map2//local lin-proofs
//
(*
val nerr = linstk_poptop0(linstk)
*)
//
val (  ) = linstk_free_nil(linstk) }
//
)(*case+*)//end-of-(tr34env_free_top(env0))
//
(* ****** ****** *)
(* ****** ****** *)

endloc (*local*) // end of [ local(tr34env...) ]

(* ****** ****** *)
(* ****** ****** *)

(* end of [ATS3/XATSOPT_srcgen2_trans34_myenv0.dats] *)
