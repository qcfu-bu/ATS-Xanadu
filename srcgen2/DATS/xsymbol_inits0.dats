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
//
(*
Author: Hongwei Xi
Start Time: June 07th, 2022
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
#include
"./../HATS/xatsopt_dats.hats"
(* ****** ****** *)
#staload "./../SATS/xsymbol.sats"
(* ****** ****** *)
//
#implval AMP_symbl = symbl("&")
#implval BAR_symbl = symbl("|")
#implval CLN_symbl = symbl(":")
#implval DOT_symbl = symbl(".")
//
#implval DLR_symbl = symbl("$")
#implval SRP_symbl = symbl("#")
//
#implval SMCLN_symbl = symbl(";")
#implval TILDA_symbl = symbl("~")
//
(* ****** ****** *)
//
#implval ADD_symbl = symbl("+")
#implval SUB_symbl = symbl("-")
#implval MUL_symbl = symbl("*")
#implval DIV_symbl = symbl("/")
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_xsymbol_inits0.dats] *)