(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Postiats - Unleashing the Potential of Types!
** Copyright (C) 2018 Hongwei Xi, ATS Trustful Software, Inc.
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
// Author: Hongwei Xi
// Start Time: April, 2018
// Authoremail: gmhwxiATgmailDOTcom
//
(* ****** ****** *)

#staload "./staexp0.sats"

(* ****** ****** *)

typedef d0eid = i0dnt_tbox

(* ****** ****** *)

abstype d0ecl_tbox = ptr
typedef d0ecl = d0ecl_tbox
typedef d0eclist = List0(d0ecl)
typedef d0eclopt = Option(d0ecl)

(* ****** ****** *)
//
datatype
dl0abeled
  (a:type) =
  DL0ABELED of (l0abl, token, a)
//
fun
{a:type}
fprint_dl0abeled
  (out: FILEref, x0: dl0abeled(a)): void
//
(* ****** ****** *)

abstype d0exp_tbox = ptr
typedef d0exp = d0exp_tbox
typedef d0explst = List0(d0exp)
typedef d0expopt = Option(d0exp)
typedef labd0exp = dl0abeled(d0exp)
typedef labd0explst = List0(labd0exp)

(* ****** ****** *)

datatype
d0exp_node =
//
| D0Eid of d0eid
//
| D0Eint of t0int
| D0Echr of t0chr
| D0Eflt of t0flt
| D0Estr of t0str
//
| D0Equal of d0exp // qualified
//
| D0Eapps of d0explst
//
| D0Elet of
  (token, d0eclist, token, d0explst, token)
| D0Ewhere of
  (d0exp, token, tokenopt, d0eclist, token)
//
| D0Enone of (token) // HX-2018-07-08: indicating error 
// end of [d0exp_node]

(* ****** ****** *)
//
fun
d0exp_get_loc(d0exp): loc_t
fun
d0exp_get_node(d0exp): d0exp_node
//
overload .loc with d0exp_get_loc
overload .node with d0exp_get_node
//
fun print_d0exp : (d0exp) -> void
fun prerr_d0exp : (d0exp) -> void
fun fprint_d0exp : fprint_type(d0exp)
//
overload print with print_d0exp
overload prerr with prerr_d0exp
overload fprint with fprint_d0exp
//
fun
d0exp_make_node
(loc: loc_t, node: d0exp_node): d0exp
//
(* ****** ****** *)

datatype
d0ecl_node =
//
| D0Cnone of token // HX: error indication
//
| D0Clocal of
  (token, d0eclist, token, d0eclist, token)
//
| D0Cstadef of
  ( token
  , s0eid, s0marglst, sort0opt, token, s0exp)
//
| D0Cabstype of (token, s0eid, s0marglst, abstdef)
//
(*
| D0Cfixity of
  (f0xty, i0dntlst) // HX: prefix, infix, postfix
*)
| D0Cnonfix of (token, i0dntlst) // HX: absolving fixity status
//
| D0Cfixity of (token, precopt, i0dntlst) // HX: attaching fixity status
//
// end of [d0ecl_node]

(* ****** ****** *)

and precopt =
| PRECOPTnil of ()
| PRECOPTsing of (token) // token is int
| PRECOPTlist of
  (token(*lparen*), tokenlst, token(*rparen*))

(* ****** ****** *)

and abstdef =
  | ABSTDEFnil of () // unspecified
  | ABSTDEFlteq of (token, s0exp)
  | ABSTDEFeqeq of (token, s0exp)

(* ****** ****** *)
//
fun
d0ecl_get_loc(d0ecl): loc_t
fun
d0ecl_get_node(d0ecl): d0ecl_node
//
overload .loc with d0ecl_get_loc
overload .node with d0ecl_get_node
//
fun print_d0ecl : (d0ecl) -> void
fun prerr_d0ecl : (d0ecl) -> void
fun fprint_d0ecl : fprint_type(d0ecl)
//
overload print with print_d0ecl
overload prerr with prerr_d0ecl
overload fprint with fprint_d0ecl
//
fun
d0ecl_make_node
(loc: loc_t, node: d0ecl_node): d0ecl
//
(* ****** ****** *)
//
fun
print_precopt : (precopt) -> void
fun
prerr_precopt : (precopt) -> void
fun
fprint_precopt : fprint_type(precopt)
//
overload print with print_precopt
overload prerr with prerr_precopt
overload fprint with fprint_precopt
//
(* ****** ****** *)
//
fun
print_abstdef : (abstdef) -> void
fun
prerr_abstdef : (abstdef) -> void
fun
fprint_abstdef : fprint_type(abstdef)
//
overload print with print_abstdef
overload prerr with prerr_abstdef
overload fprint with fprint_abstdef
//
(* ****** ****** *)

(* end of [xats_dynexp0.sats] *)
