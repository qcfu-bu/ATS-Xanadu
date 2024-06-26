(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2024 Hongwei Xi, ATS Trustful Software, Inc.
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
Fri 29 Mar 2024 04:04:08 PM EDT
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
(* ****** ****** *)
(* ****** ****** *)
//
#staload "./intrep0.sats"
#staload "./intrep1.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#absvwtp xatsenv_vtbx // p0tr
#vwtpdef xatsenv = xatsenv_vtbx
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
xatsenv_make_nil
(    (*nil*)    ): xatsenv
fun
xatsenv_free_top
( env0: ~xatsenv ): void//fun
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
xats2js_i1parsed(i1parsed): (void)
//
(* ****** ****** *)
//
fun
xats2js_i1dclistopt
(env0: !xatsenv, dopt: i1dclistopt): void
//
(* ****** ****** *)
(* ****** ****** *)

(***********************************************************************)
(* end of [ATS3/XANADU_srcgen1_xats2js_srcgen1_SATS_xats2js.sats] *)
(***********************************************************************)
