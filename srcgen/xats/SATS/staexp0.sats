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
//
#staload
LAB = "./label0.sats"
#staload
LOC = "./location.sats"
//
typedef label = $LAB.label
typedef loc_t = $LOC.location
//
staload LEX = "./lexing.sats"
staload SYM = "./symbol.sats"
//
typedef token = $LEX.token
typedef tokenlst = $LEX.tokenlst
typedef tokenopt = $LEX.tokenopt
//
typedef symbol = $SYM.symbol
typedef symbolist = $SYM.symbolist
typedef symbolopt = $SYM.symbolopt
//
(* ****** ****** *)
(*
//
typedef tkint = token // int
typedef tkchr = token // char
typedef tkflt = token // float
typedef tkstr = token // string
//
typedef tkintopt = Option(tkint)
typedef tkchropt = Option(tkchr)
typedef tkfltopt = Option(tkflt)
typedef tkstropt = Option(tkstr)
//
*)
(* ****** ****** *)
//
abstbox t0int_tbox = ptr
abstbox t0chr_tbox = ptr
abstbox t0flt_tbox = ptr
abstbox t0str_tbox = ptr
//
abstbox i0dnt_tbox = ptr
//
(* ****** ****** *)
//
typedef t0int = t0int_tbox
typedef t0chr = t0chr_tbox
typedef t0flt = t0flt_tbox
typedef t0str = t0str_tbox
//
typedef i0dnt = i0dnt_tbox
//
typedef s0tid = i0dnt_tbox
typedef s0eid = i0dnt_tbox
//
(* ****** ****** *)
//
datatype
t0int_node =
  | T0INTnone of token
  | T0INTsome of token
datatype
t0chr_node =
  | T0CHRnone of token
  | T0CHRsome of token
datatype
t0flt_node =
  | T0FLTnone of token
  | T0FLTsome of token
datatype
t0str_node =
  | T0STRnone of token
  | T0STRsome of token
//
(* ****** ****** *)
//
datatype
i0dnt_node =
  | I0DNTnone of token
  | I0DNTsome of token
//
(* ****** ****** *)
(*
typedef t0int = $rec
{
  t0int_loc= loc_t, t0int_node= symbol
} (* end of [t0int] *)
typedef t0chr = $rec
{
  t0chr_loc= loc_t, t0chr_node= symbol
} (* end of [t0chr] *)
typedef t0flt = $rec
{
  t0flt_loc= loc_t, t0flt_node= symbol
} (* end of [t0flt] *)
typedef t0str = $rec
{
  t0str_loc= loc_t, t0str_node= symbol
} (* end of [t0str] *)
//
typedef i0dnt = $rec
{
  i0dnt_loc= loc_t, i0dnt_node= symbol
} (* end of [i0dnt] *)
*)
(* ****** ****** *)
//
fun
t0int_get_loc : (t0int) -> loc_t
fun
t0int_get_node : (t0int) -> t0int_node
//
overload .loc with t0int_get_loc
overload .node with t0int_get_node
//
fun t0int_none : token -> t0int
fun t0int_some : token -> t0int
//
fun print_t0int : print_type(t0int)
fun prerr_t0int : prerr_type(t0int)
fun fprint_t0int : fprint_type(t0int)
//
overload print with print_t0int
overload prerr with prerr_t0int
overload fprint with fprint_t0int
//
(* ****** ****** *)
//
fun
t0chr_get_loc: (t0chr) -> loc_t
fun
t0chr_get_node: (t0chr) -> t0chr_node
//
overload .loc with t0chr_get_loc
overload .node with t0chr_get_node
//
fun t0chr_none : token -> t0chr
fun t0chr_some : token -> t0chr
//
fun print_t0chr : print_type(t0chr)
fun prerr_t0chr : prerr_type(t0chr)
fun fprint_t0chr : fprint_type(t0chr)
//
overload print with print_t0chr
overload prerr with prerr_t0chr
overload fprint with fprint_t0chr
//
(* ****** ****** *)
//
fun
t0flt_get_loc: (t0flt) -> loc_t
fun
t0flt_get_node: (t0flt) -> t0flt_node
//
overload .loc with t0flt_get_loc
overload .node with t0flt_get_node
//
fun t0flt_none : token -> t0flt
fun t0flt_some : token -> t0flt
//
fun print_t0flt : print_type(t0flt)
fun prerr_t0flt : prerr_type(t0flt)
fun fprint_t0flt : fprint_type(t0flt)
//
overload print with print_t0flt
overload prerr with prerr_t0flt
overload fprint with fprint_t0flt
//
(* ****** ****** *)
//
fun
t0str_get_loc: (t0str) -> loc_t
fun
t0str_get_node: (t0str) -> t0str_node
//
overload .loc with t0str_get_loc
overload .node with t0str_get_node
//
fun t0str_none : token -> t0str
fun t0str_some : token -> t0str
//
fun print_t0str : print_type(t0str)
fun prerr_t0str : prerr_type(t0str)
fun fprint_t0str : fprint_type(t0str)
//
overload print with print_t0str
overload prerr with prerr_t0str
overload fprint with fprint_t0str
//
(* ****** ****** *)
//
typedef i0dnt = i0dnt_tbox
typedef i0dntlst = List(i0dnt)
typedef i0dntopt = Option(i0dnt)
//
fun
i0dnt_get_loc
  : (i0dnt) -> loc_t
fun
i0dnt_get_node
  : (i0dnt) -> i0dnt_node
//
overload .loc with i0dnt_get_loc
overload .node with i0dnt_get_node
//
fun i0dnt_none : token -> i0dnt
fun i0dnt_some : token -> i0dnt
//
(* ****** ****** *)
//
fun print_i0dnt : print_type(i0dnt)
fun prerr_i0dnt : prerr_type(i0dnt)
fun fprint_i0dnt : fprint_type(i0dnt)
//
overload print with print_i0dnt
overload prerr with prerr_i0dnt
overload fprint with fprint_i0dnt
//
(* ****** ****** *)

//
abstbox l0abl_tbox = ptr
typedef l0abl = l0abl_tbox
//
datatype
l0abl_node =
  | L0ABsome of label // valid
  | L0ABnone of (token) // invalid
//
fun
l0abl_get_loc(l0abl): loc_t
fun
l0abl_get_node(l0abl): l0abl_node
//
overload .loc with l0abl_get_loc
overload .node with l0abl_get_node
//
fun print_l0abl : print_type(l0abl)
fun prerr_l0abl : prerr_type(l0abl)
fun fprint_l0abl : fprint_type(l0abl)
//
overload print with print_l0abl
overload prerr with prerr_l0abl
overload fprint with fprint_l0abl
//
fun
l0abl_make_int1(tok: token): l0abl
fun
l0abl_make_name(tok: token): l0abl
fun
l0abl_make_none(tok: token): l0abl
//
fun
l0abl_make_node
(loc: loc_t, node: l0abl_node): l0abl
//
(* ****** ****** *)
//
datatype
sl0abeled
  (a:type) =
  SL0ABELED of (l0abl, token, a)
//
fun
{a:type}
fprint_sl0abeled
  (out: FILEref, x0: sl0abeled(a)): void
//
(* ****** ****** *)
//
abstbox sort0_tbox = ptr
typedef sort0 = sort0_tbox
typedef sort0lst = List0(sort0)
typedef sort0opt = Option(sort0)
//
datatype
sort0_node =
//
| S0Tid of (s0tid)
//
| S0Tapp of (sort0lst) // HX: unsupported
//
| S0Tlist of (token, sort0lst, token) (* for temporary use *)
//
| S0Tqual of (token, sort0) // HX: qualified
(*
| S0Ttype of int (* prop/view/type/t0ype/viewtype/viewt0ype *)
*)
| S0Tnone of (token)
// end of [sort0_node]

(* ****** ****** *)
//
fun
sort0_get_loc(sort0): loc_t
fun
sort0_get_node(sort0): sort0_node
//
overload .loc with sort0_get_loc
overload .node with sort0_get_node
//
fun print_sort0 : print_type(sort0)
fun prerr_sort0 : prerr_type(sort0)
fun fprint_sort0 : fprint_type(sort0)
//
overload print with print_sort0
overload prerr with prerr_sort0
overload fprint with fprint_sort0
//
fun
sort0_make_node
(loc: loc_t, node: sort0_node): sort0
//
(* ****** ****** *)
//
abstbox s0arg_tbox = ptr
typedef s0arg = s0arg_tbox
typedef s0arglst = List0(s0arg)
//
datatype
s0arg_node =
  | S0ARGnone of token
  | S0ARGsome of (s0eid, sort0opt)
//
fun
s0arg_get_loc(s0arg): loc_t
fun
s0arg_get_node(s0arg): s0arg_node
//
overload .loc with s0arg_get_loc
overload .node with s0arg_get_node
//
fun print_s0arg : print_type(s0arg)
fun prerr_s0arg : prerr_type(s0arg)
fun fprint_s0arg : fprint_type(s0arg)
//
overload print with print_s0arg
overload prerr with prerr_s0arg
overload fprint with fprint_s0arg
//
fun
s0arg_make_node
(loc: loc_t, node: s0arg_node): s0arg
//
(* ****** ****** *)
//
abstbox s0marg_tbox = ptr
typedef s0marg = s0marg_tbox
typedef s0marglst = List0(s0marg)
//
datatype
s0marg_node =
  | S0MARGnone of token
  | S0MARGsing of (s0eid)
  | S0MARGlist of (token, s0arglst, token)
//
fun
s0marg_get_loc(s0marg): loc_t
fun
s0marg_get_node(s0marg): s0marg_node
//
overload .loc with s0marg_get_loc
overload .node with s0marg_get_node
//
fun print_s0marg : print_type(s0marg)
fun prerr_s0marg : prerr_type(s0marg)
fun fprint_s0marg : fprint_type(s0marg)
//
overload print with print_s0marg
overload prerr with prerr_s0marg
overload fprint with fprint_s0marg
//
fun
s0marg_make_node
(loc: loc_t, node: s0marg_node): s0marg
//
(* ****** ****** *)
//
abstbox s0exp_tbox = ptr
//
typedef s0exp = s0exp_tbox
typedef s0explst = List0(s0exp)
typedef s0expopt = Option(s0exp)
//
typedef labs0exp = sl0abeled(s0exp)
typedef labs0explst = List0(labs0exp)
//
(* ****** ****** *)

datatype
s0exp_node =
//
| S0Eid of (s0eid)
//
| S0Eint of (t0int)
| S0Echr of (t0chr)
| S0Eflt of (t0flt)
| S0Estr of (t0str)
//
| S0Eapps of s0explst
//
| S0Ebrack of
    (token, s0explst, token)
//
| S0Eparen of
    (token, s0explst, s0exp_RPAREN)
| S0Ebrace of
    (token, labs0explst, labs0exp_RBRACE)
//
| S0Elam of
  (token, s0marglst, sort0opt, token, s0exp)
//
| S0Eanno of (s0exp, sort0) // sort annotation
//
| S0Equal of (token, s0exp) // qualified staexp
//
| S0Enone of (token) // HX-2018-07-08: indicating error 
// end of [s0exp_node]
//
and
s0exp_RPAREN =
| s0exp_RPAREN_cons0 of token
| s0exp_RPAREN_cons1 of (token, s0explst, token)
//
and
labs0exp_RBRACE =
| labs0exp_RBRACE_cons0 of token
| labs0exp_RBRACE_cons1 of (token, labs0explst, token)
//
(* ****** ****** *)
//
fun
s0exp_get_loc(s0exp): loc_t
fun
s0exp_get_node(s0exp): s0exp_node
//
overload .loc with s0exp_get_loc
overload .node with s0exp_get_node
//
fun print_s0exp : print_type(s0exp)
fun prerr_s0exp : prerr_type(s0exp)
fun fprint_s0exp : fprint_type(s0exp)
//
overload print with print_s0exp
overload prerr with prerr_s0exp
overload fprint with fprint_s0exp
//
fun
s0exp_make_node
(loc: loc_t, node: s0exp_node): s0exp
//
(* ****** ****** *)
//
fun
s0exp_RPAREN_loc(s0exp_RPAREN): loc_t
//
fun
print_s0exp_RPAREN: print_type(s0exp_RPAREN)
fun
prerr_s0exp_RPAREN: print_type(s0exp_RPAREN)
fun
fprint_s0exp_RPAREN: fprint_type(s0exp_RPAREN)
//
overload print with print_s0exp_RPAREN
overload prerr with prerr_s0exp_RPAREN
overload fprint with fprint_s0exp_RPAREN
//
(* ****** ****** *)
//
fun
labs0exp_RBRACE_loc(labs0exp_RBRACE): loc_t
//
fun
print_labs0exp_RBRACE: print_type(labs0exp_RBRACE)
fun
prerr_labs0exp_RBRACE: prerr_type(labs0exp_RBRACE)
fun
fprint_labs0exp_RBRACE: fprint_type(labs0exp_RBRACE)
//
overload print with print_labs0exp_RBRACE
overload prerr with prerr_labs0exp_RBRACE
overload fprint with fprint_labs0exp_RBRACE
//
(* ****** ****** *)

(* end of [xats_staexp0.sats] *)
