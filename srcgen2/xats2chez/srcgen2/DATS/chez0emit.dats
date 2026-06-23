(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(*
chez0emit (milestone M1.0) — the top-level intrep0 -> Chez Scheme emitter.
//
Real IR-driven walk: runs after frontend -> trxd3i0 -> tryd3i0, walks the
i0parsed declaration list and emits Chez Scheme between the
;;==XATS2CHEZ-BEGIN==/;;==XATS2CHEZ-END== sentinels.  M1.0 handles the
test00 surface: a top-level [val] group binding an integer literal ->
(define <name> <int>).  Unhandled IR nodes degrade to a ";; UNHANDLED:"
comment + a stderr note (never silently-wrong Scheme).  Broader coverage
(applications/templates/print-store, if/case/let, funs, data, ...) lands in
later M1 increments, eventually split into chez0emit_{utils0,dynexp,decl00}.
//
NOTE (stamp discipline): keep the SATS stable; DATS-only edits are safe.
*)
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
//
(* ****** ****** *)
//
#staload // SYM =
"./../../../SATS/xsymbol.sats"
#staload // LOC =
"./../../../SATS/locinfo.sats"
#staload // LEX =
"./../../../SATS/lexing0.sats"
#staload // BAS =
"./../../../SATS/xbasics.sats"
#staload // D2E =
"./../../../SATS/dynexp2.sats"
//
(* ****** ****** *)
//
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"
//
#staload "./../SATS/chez0emit.sats"
//
(* ****** ****** *)
//
#symload node with token_get_node
//
(* ****** ****** *)
(* ****** ****** *)
//
(* cz_str: write a (runtime) string to [filr] verbatim. *)
fun
cz_str
( filr: FILR
, s0: strn): void =
(
  prints(s0)) where
{ #impltmp g_print$out<>() = filr }
//
(* cz_sym: write a symbol's chars to [filr]. (M1.0: verbatim; a Scheme-safe
   mangler + stamp suffix follows in a later increment.) *)
fun
cz_sym
( filr: FILR
, xsym: sym_t): void =
(
  cz_str(filr, symbl_get_name(xsym)))
//
(* ****** ****** *)
(* ****** ****** *)
//
(* i0exp_cz0: emit an intrep0 expression (M1.0 subset). *)
fun
i0exp_cz0
( filr: FILR
, iexp: i0exp): void =
(
case+ iexp.node() of
//
| I0Eint(tint) =>
  (
  case- tint.node() of
  | T_INT01(rep) => cz_str(filr, rep)
  | T_INT02(_, rep) => cz_str(filr, rep)
  | T_INT03(_, rep, _) => cz_str(filr, rep))
//
| I0Ei00(i00) =>
  (
  prints(i00)) where
  { #impltmp g_print$out<>() = filr }
//
| _(*else*) =>
  (
  cz_str(filr, "(begin #f) ;; UNHANDLED-i0exp\n");
  prerrsln("[chez0emit] UNHANDLED i0exp"))
)//endof[i0exp_cz0(filr,iexp)]
//
(* ****** ****** *)
//
(* i0valdcl_cz0: emit one val binding.
   - I0Pvar(dvar)  = e   -> (define <name> <e>)
   - I0Ptup0()     = e   -> <e>          (effectful top-level [val () = e]) *)
fun
i0valdcl_cz0
( filr: FILR
, ivd0: i0valdcl): void =
let
val ipat = ivd0.ipat()
val tdxp = ivd0.tdxp()
in//let
case+ tdxp of
| TEQI0EXPnone() => ()
| TEQI0EXPsome(_, iexp) =>
  (
  case+ ipat.node() of
  | I0Pvar(dvar) =>
    (
    cz_str(filr, "(define ");
    cz_sym(filr, d2var_get_name(dvar));
    cz_str(filr, " ");
    i0exp_cz0(filr, iexp);
    cz_str(filr, ")\n"))
  | _(*effectful: val () = e*) =>
    (
    i0exp_cz0(filr, iexp);
    cz_str(filr, "\n")))
end//let//endof[i0valdcl_cz0(filr,ivd0)]
//
(* ****** ****** *)
//
fun
i0valdclist_cz0
( filr: FILR
, ivs0: i0valdclist): void =
(
case+ ivs0 of
| list_nil() => ()
| list_cons(ivd0, ivs1) =>
  (
  i0valdcl_cz0(filr, ivd0);
  i0valdclist_cz0(filr, ivs1)))
//
(* ****** ****** *)
(* ****** ****** *)
//
(* i0dcl_cz0: emit one top-level declaration (M1.0 subset). *)
fun
i0dcl_cz0
( filr: FILR
, idcl: i0dcl): void =
(
case+ idcl.node() of
//
| I0Dvaldclst(_, ivs0) =>
  i0valdclist_cz0(filr, ivs0)
//
| I0Ddclst0(idcls) =>
  i0dclist_cz0(filr, idcls)
| I0Dlocal0(ihead, ibody) =>
  (
  i0dclist_cz0(filr, ihead);
  i0dclist_cz0(filr, ibody))
//
(* erased / not-yet-handled at top level: a comment, no Scheme. *)
| I0Dd3ecl _ => ()
| I0Dinclude _ => ()
| I0Dnone0() => ()
| I0Dnone1 _ => ()
| I0Dnone2 _ => ()
//
| _(*else*) =>
  (
  cz_str(filr, ";; UNHANDLED-i0dcl\n");
  prerrsln("[chez0emit] UNHANDLED i0dcl"))
)//endof[i0dcl_cz0(filr,idcl)]
//
(* ****** ****** *)
//
and
i0dclist_cz0
( filr: FILR
, idcls: i0dclist): void =
(
case+ idcls of
| list_nil() => ()
| list_cons(idcl, idcls) =>
  (
  i0dcl_cz0(filr, idcl);
  i0dclist_cz0(filr, idcls)))
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0parsed_chez0emit
(ipar, filr) =
let
//
val parsed = i0parsed_parsed$get(ipar)
//
in//let
(
cz_str(filr, ";;==XATS2CHEZ-BEGIN==\n");
(
case+ parsed of
| optn_nil() => ()
| optn_cons(idcls) => i0dclist_cz0(filr, idcls));
cz_str(filr, ";;==XATS2CHEZ-END==\n")
)
end//let
//endof[i0parsed_chez0emit(ipar,filr)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_DATS_chez0emit.dats] *)
(***********************************************************************)
