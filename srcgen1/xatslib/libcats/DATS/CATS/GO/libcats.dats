(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
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
The GO analog of
DATS/CATS/JS/NODE/libcats.dats:
per-target concrete <> impls that
alias the channel/fprint leaves to
XATS2GO_-named externs; the runtime
(xatsgo) provides the extern images.
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#staload
"./../../../SATS/libcats.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#extern
fun
XATS2GO_g_stdout
  ((*void*)): FILR = $extnam()
#extern
fun
XATS2GO_g_stderr
  ((*void*)): FILR = $extnam()
//
#impltmp
g_stdout<> = XATS2GO_g_stdout
#impltmp
g_stderr<> = XATS2GO_g_stderr
//
(* ****** ****** *)
(* ****** ****** *)
//
#extern
fun
XATS2GO_bool_fprint:
(bool, FILR) -> void = $extnam()
#impltmp
bool_fprint<> = XATS2GO_bool_fprint
//
#extern
fun
XATS2GO_char_fprint:
(char, FILR) -> void = $extnam()
#impltmp
char_fprint<> = XATS2GO_char_fprint
//
#extern
fun
XATS2GO_strn_fprint:
(strn, FILR) -> void = $extnam()
#impltmp
strn_fprint<> = XATS2GO_strn_fprint
//
#extern
fun
XATS2GO_gint_fprint$sint:
(sint, FILR) -> void = $extnam()
#impltmp
gint_fprint$sint<> = XATS2GO_gint_fprint$sint
#extern
fun
XATS2GO_gint_fprint$uint:
(uint, FILR) -> void = $extnam()
#impltmp
gint_fprint$uint<> = XATS2GO_gint_fprint$uint
//
#extern
fun
XATS2GO_gflt_fprint$sflt:
(sflt, FILR) -> void = $extnam()
#impltmp
gflt_fprint$sflt<> = XATS2GO_gflt_fprint$sflt
#extern
fun
XATS2GO_gflt_fprint$dflt:
(dflt, FILR) -> void = $extnam()
#impltmp
gflt_fprint$dflt<> = XATS2GO_gflt_fprint$dflt
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen1_xatslib_libcats_DATS_CATS_GO_libcats.dats] *)
(***********************************************************************)
