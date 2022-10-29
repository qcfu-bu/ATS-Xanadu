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
(*
Tue 25 Oct 2022 05:29:15 PM EDT
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
#staload "./../SATS/xbasics.sats"
(* ****** ****** *)
#staload "./../SATS/xsymbol.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
(* ****** ****** *)

local
//
val
s2tb_int =
T2Bpred($SYM.INT_symbl)
val
s2tb_bool =
T2Bpred($SYM.BOOL_symbl)
val
s2tb_addr =
T2Bpred($SYM.ADDR_symbl)
val
s2tb_char =
T2Bpred($SYM.CHAR_symbl)
//
val
s2tb_prop =
T2Bimpr
(PROPSORT, $SYM.PROP_symbl)
val
s2tb_type =
T2Bimpr
(TYPESORT, $SYM.TYPE_symbl)
//
val
s2tb_view =
T2Bimpr
(VIEWSORT, $SYM.VIEW_symbl)
val
s2tb_vwtp =
T2Bimpr
(VWTPSORT, $SYM.VWTP_symbl)
//
in(*local*)
//
#implval
the_sort2_int = S2Tbas(s2tb_int)
#implval
the_sort2_addr = S2Tbas(s2tb_addr)
#implval
the_sort2_bool = S2Tbas(s2tb_bool)
#implval
the_sort2_char = S2Tbas(s2tb_char)
//
#implval
the_sort2_prop = S2Tbas(s2tb_prop)
#implval
the_sort2_type = S2Tbas(s2tb_type)
#implval
the_sort2_view = S2Tbas(s2tb_view)
#implval
the_sort2_vwtp = S2Tbas(s2tb_vwtp)
//
endloc (*local*) // end of [local(predefined)]

(* ****** ****** *)

(* end of [ATS3/XATSOPT_srcgen2_staexp2_inits0.dats] *)