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
Start Time: May 28th, 2022
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#staload "./xbasics.sats"
(* ****** ****** *)
#staload LOC = "./locinfo.sats"
(* ****** ****** *)
#typedef loc_t = $LOC.loc_t
(* ****** ****** *)
//
datatype tnode =
//
| T_EOF of ((*void*))
| T_ERR of ((*void*))
//
| T_EOL of () // end-of-line
//
| T_BLANK of (strn) // blank
| T_CLNLT of (strn) // ( :< )
| T_DOTLT of (strn) // ( .< )
//
(*
// HX-2020-10-21:
// for internal names
*)
| T_IDENT of (strn) // string
//
| T_IDALP of (strn) // alnuml
| T_IDSYM of (strn) // symbol
//
| T_IDSRP of (strn) // #alnuml
| T_IDDLR of (strn) // $alnuml
//
| T_IDQUA of (strn) // $alnuml.
//
| T_INT01 of (strn(*rep*)) // base=10
| T_INT02 of (sint(*bas*), strn(*rep*))
| T_INT03 of (sint(*bas*), strn(*rep*), sint(*sfx*))
//
| T_FLT01 of (strn(*rep*)) // base=10
| T_FLT02 of (sint(*bas*), strn(*rep*))
| T_FLT03 of (sint(*bas*), strn(*rep*), sint(*sfx*))
//
| T_CHAR1_nil0 of (strn) // null: ''
| T_CHAR2_char of (strn) // regular: '?'
| T_CHAR3_blsh of (strn) // backslash: '\...'
//
| T_STRN1_clsd of (strn) // closed: utf-8 // for text
| T_STRN2_ncls of (strn) // unclosed: utf-8 // for text
//
| T_CMNT1_line of
  ( strn(*init*), strn ) // line-style // init: '//'
| T_CMNT2_rest of
  ( strn(*init*), strn ) // rest-style // init: '////'
| T_CMNT3_ccbl of (sint(*level*), strn) // of cc-style
| T_CMNT4_mlbl of (sint(*level*), strn) // of ml-style
//
// fn0, fnx, fn1, fun, praxi,
| T_FUN of (funkind) // prfn0, prfn1, prfun, fcast
| T_VAL of (valkind) // val, val+, val-, prval, (mcval)
| T_VAR of (varkind) // var // there may be more kinds
//
| T_CASE of (caskind) // case, case+, case- // some more?
//
// end-of-(datatype tnode)
//
(* ****** ****** *)
#abstbox token_tbox // ptr
#typedef token = token_tbox
(* ****** ****** *)
#typedef tokenlst = list(token)
#typedef tokenopt = optn(token)
(* ****** ****** *)
//
fun//<>
tnode_fprint(FILR, tnode): void
fun//<>
token_fprint(FILR, token): void
//
(* ****** ****** *)
//
fun//{}
token_get_lctn: token -> loc_t
fun//{}
token_get_node: token -> tnode
//
fun//{}
token_make_node
(loc: loc_t, tnd: tnode): token
//
#symload lctn with token_get_lctn
#symload node with token_get_node
#symload token with token_make_node
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_lexing0.sats] *)
