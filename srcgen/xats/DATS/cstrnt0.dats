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
// Start Time: March, 2021
// Authoremail: gmhwxiATgmailDOTcom
//
(* ****** ****** *)
//
#include
"share/atspre_staload.hats"
#staload
UN = "prelude/SATS/unsafe.sats"
//
(* ****** ****** *)
#staload "./../SATS/locinfo.sats"
(* ****** ****** *)
//
#staload "./../SATS/cstrnt0.sats"
//
(* ****** ****** *)

local

absimpl
c0str_tbox = $rec
{ c0str_loc= loc_t
, c0str_node= c0str_node
}

in (* in-of-local *)

(* ****** ****** *)
//
implement
c0str_get_loc
  (c0s) = c0s.c0str_loc
implement
c0str_get_node
  (c0s) = c0s.c0str_node
//
(* ****** ****** *)
//
implement
c0str_make_node
( loc0
, node) = $rec
{ c0str_loc= loc0
, c0str_node= node
} (*$rec*) // c0str_make_node
//
(* ****** ****** *)

end // end of [local]

(* ****** ****** *)
//
implement
c0str_make_tasmp
( loc0
, s2e1(*src*)
, s2e2(*dst*)) =
(
  c0str_make_node
  (loc0, C0Seqeq(s2e1, s2e2))
)
//
(* ****** ****** *)
//
implement
c0str_make_tcast
( loc0
, s2e1(*src*)
, s2e2(*dst*)) =
(
  c0str_make_node
  (loc0, C0Stsub(s2e1, s2e2))
)
//
(* ****** ****** *)

(* end of [xats_cstrnt0.dats] *)