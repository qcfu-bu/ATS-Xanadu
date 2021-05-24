(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2021 Hongwei Xi, ATS Trustful Software, Inc.
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
// Start Time: March 27, 2021
// Authoremail: gmhwxiATgmailDOTcom
//
(* ****** ****** *)
#staload "./xbasics.sats"
(* ****** ****** *)
#staload "./locinfo.sats"
(* ****** ****** *)
#staload S2E = "./staexp2.sats"
#staload S2T = "./statyp2.sats"
(* ****** ****** *)
typedef s2var = $S2E.s2var
typedef s2exp = $S2E.s2exp
(* ****** ****** *)
//
abstbox c1str_tbox = ptr
typedef c1str = c1str_tbox
typedef c1strlst = List0(c1str)
//
(* ****** ****** *)
//
datatype c1itm =
| C1Isvar of s2var
| C1Icstr of c1str
| C1Idisj of c1strlst
and c1str_node =
| C1Sprop of s2exp
| C1Sitms of c1itmlst
and c1hyp_node =
| C1Hprop of s2exp
| C1Hbind of (s2var, s2exp)
| C1Heqeq of (s2exp, s2exp)
//
where c1itmlst = List0(c1itm)
//
(* ****** ****** *)
//
fun
c1str_get_loc
( c1s: c1str ): loc_t
fun
c1str_get_node
( c1s: c1str ): c1str_node
//
overload .loc with c1str_get_loc
overload .node with c1str_get_node
//
fun
print_c1str : print_type(c1str)
fun
prerr_c1str : prerr_type(c1str)
fun
fprint_c1str : fprint_type(c1str)
//
overload print with print_c1str
overload prerr with prerr_c1str
overload fprint with fprint_c1str
//
fun
c1str_make_node
( loc0
: loc_t, node: c1str_node): c1str
//
(* ****** ****** *)

(* end of [xats_cstrnt1.sats] *)