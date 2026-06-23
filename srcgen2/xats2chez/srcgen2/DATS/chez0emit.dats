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
chez0emit (milestone M2) — the intrep0 -> Chez Scheme emitter.
//
Real IR-driven walk over intrep0 (the expression-shaped IR), emitting Chez
Scheme between the ;;==XATS2CHEZ-BEGIN==/;;==XATS2CHEZ-END== sentinels.
Coverage so far: top-level val/fun decls, local let/where, integer/bool/
float/char/string literals, applications (template-instance constants erased
to their monomorphic name), if, sequencing.  Native Chez proper tail calls +
lexical closures mean self-recursion and captured vars need no special work.
Unhandled IR nodes degrade to a ";; UNHANDLED:" comment + a stderr note.
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
( filr: FILR, s0: strn): void =
(
  prints(s0)) where { #impltmp g_print$out<>() = filr }
//
(* cz_sym: write a symbol's chars to [filr].  (M2: verbatim; a Scheme-safe
   mangler + stamp suffix for user names follows in a later increment.) *)
fun
cz_sym
( filr: FILR, xsym: sym_t): void =
(
  cz_str(filr, symbl_get_name(xsym)))
//
(* ****** ****** *)
//
(* cz_strlit: emit a string-literal token as a Scheme string literal.  The
   token rep INCLUDES the surrounding quotes and uses the same escape syntax
   (\n \t \r \" \\) Scheme accepts, so it is emitted verbatim. *)
fun
cz_strlit
( filr: FILR, tstr: token): void =
(
case- tstr.node() of
| T_STRN1_clsd(rep1, _) => cz_str(filr, rep1)
| T_STRN2_ncls(rep1, _) => cz_str(filr, rep1))
//
(* ****** ****** *)
//
(* cz_raw_char: write one char glyph to [filr] verbatim. *)
fun
cz_raw_char
( filr: FILR, c0: char): void =
(
  prints(c0)) where { #impltmp g_print$out<>() = filr }
//
(* cz_char_esc: emit one char into a Scheme string body, escaped.  (A char
   is its integer code at runtime; the emitter mirrors the JS backend's
   XATSCHR0("<glyph>") form so the runtime computes char->integer.) *)
fun
cz_char_esc
( filr: FILR, c0: char): void =
(
case+ c0 of
| '\n' => cz_str(filr, "\\n")
| '\t' => cz_str(filr, "\\t")
| '\r' => cz_str(filr, "\\r")
| '\"' => cz_str(filr, "\\\"")
| '\\' => cz_str(filr, "\\\\")
| _(*else*) => cz_raw_char(filr, c0))
//
(* cz_chrtok: emit a char-literal TOKEN as (XATSCHR0 "<body>"), where <body>
   is the source char between the single quotes (escapes pass through to the
   Scheme string verbatim; a lone double-quote is escaped). *)
fun
cz_chr_body
( filr: FILR, rep: strn): void =
let
val n0 = strn_length(rep)
fun
loop(i0: sint): void =
if (i0 >= n0-1) then () else
let
val c0 = strn_get$at(rep, i0)
val () =
(if (c0 = '\"') then cz_str(filr, "\\\"") else cz_raw_char(filr, c0))
in loop(i0+1) end
in//let
(cz_str(filr, "(XATSCHR0 \""); loop(1); cz_str(filr, "\")"))
end//let
//
fun
cz_chrtok
( filr: FILR, tchr: token): void =
(
case- tchr.node() of
| T_CHAR1_nil0 _ => cz_str(filr, "0")
| T_CHAR2_char(rep) => cz_chr_body(filr, rep)
| T_CHAR3_blsh(rep) => cz_chr_body(filr, rep))
//
(* cz_inttok: emit an integer-literal token's decimal rep. *)
fun
cz_inttok
( filr: FILR, tint: token): void =
(
case- tint.node() of
| T_INT01(rep) => cz_str(filr, rep)
| T_INT02(_, rep) => cz_str(filr, rep)
| T_INT03(_, rep, _) => cz_str(filr, rep))
//
(* cz_pat_test: a boolean Scheme expr testing the scrutinee [czscrut] against
   a pattern.  M3b: flat patterns (literal / var / wildcard); nested
   constructor/tuple patterns follow in M3c. *)
fun
cz_pat_test
( filr: FILR, pat: i0pat): void =
(
case+ pat.node() of
| I0Pany() => cz_str(filr, "#t")
| I0Pvar(_) => cz_str(filr, "#t")
| I0Pint(t0) => (cz_str(filr, "(= czscrut "); cz_inttok(filr, t0); cz_str(filr, ")"))
| I0Pchr(t0) => (cz_str(filr, "(= czscrut "); cz_chrtok(filr, t0); cz_str(filr, ")"))
| I0Pstr(t0) => (cz_str(filr, "(string=? czscrut "); cz_strlit(filr, t0); cz_str(filr, ")"))
| _(*else*) =>
  (cz_str(filr, "#f"); prerrsln("[chez0emit] UNHANDLED pat-test")))
//
(* cz_pat_binds: emit the let-binding-list CONTENT for a pattern (a var
   pattern binds czscrut; flat literals bind nothing). *)
fun
cz_pat_binds
( filr: FILR, pat: i0pat): void =
(
case+ pat.node() of
| I0Pvar(dvar) =>
  (cz_str(filr, "("); cz_sym(filr, d2var_get_name(dvar)); cz_str(filr, " czscrut)"))
| _(*else*) => ())
//
(* ldrop / ldrop_pat: drop the first [n] (proof) elements of an arg/pat list. *)
fun
ldrop
( xs: i0explst, n: sint): i0explst =
if (n <= 0) then xs else
(case+ xs of list_nil() => xs | list_cons(_, xs) => ldrop(xs, n-1))
//
fun
ldrop_pat
( xs: i0patlst, n: sint): i0patlst =
if (n <= 0) then xs else
(case+ xs of list_nil() => xs | list_cons(_, xs) => ldrop_pat(xs, n-1))
//
(* ****** ****** *)
//
(* function parameter emission: flatten the dynamic (FIARGdapp) param groups
   into a single Scheme arg list; static (FIARGsapp) / metric (FIARGmets)
   groups are erased.  Each param emits as " <name>". *)
fun
cz_param_pat
( filr: FILR, ipat: i0pat): void =
(
case+ ipat.node() of
| I0Pvar(dvar) =>
  (cz_str(filr, " "); cz_sym(filr, d2var_get_name(dvar)))
| I0Pany() => cz_str(filr, " _wild")
| _(*else*) =>
  (cz_str(filr, " _unkp"); prerrsln("[chez0emit] UNHANDLED param-pat")))
//
fun
cz_param_patlst
( filr: FILR, pats: i0patlst): void =
(
case+ pats of
| list_nil() => ()
| list_cons(p0, pats) => (cz_param_pat(filr, p0); cz_param_patlst(filr, pats)))
//
fun
cz_fiarg
( filr: FILR, fia: fiarg): void =
(
case+ fia.node() of
| FIARGdapp(npf, pats) => cz_param_patlst(filr, ldrop_pat(pats, npf))
| _(*FIARGsapp/FIARGmets: erased*) => ())
//
fun
cz_fiarglst
( filr: FILR, fias: fiarglst): void =
(
case+ fias of
| list_nil() => ()
| list_cons(f0, fias) => (cz_fiarg(filr, f0); cz_fiarglst(filr, fias)))
//
(* ****** ****** *)
(* ****** ****** *)
//
(* The mutually-recursive walk: expressions contain declarations (let/where)
   and declarations contain expressions (val/fun bodies). *)
//
fun
i0exp_cz0
( filr: FILR, iexp: i0exp): void =
(
case+ iexp.node() of
//
(* literals *)
| I0Eint(tint) =>
  (
  case- tint.node() of
  | T_INT01(rep) => cz_str(filr, rep)
  | T_INT02(_, rep) => cz_str(filr, rep)
  | T_INT03(_, rep, _) => cz_str(filr, rep))
| I0Ei00(i00) => (prints(i00)) where { #impltmp g_print$out<>() = filr }
| I0Eflt(tflt) =>
  (
  case- tflt.node() of
  | T_FLT01(rep) => cz_str(filr, rep)
  | T_FLT02(_, rep) => cz_str(filr, rep)
  | T_FLT03(_, rep, _) => cz_str(filr, rep))
| I0Ef00(f00) => (prints(f00)) where { #impltmp g_print$out<>() = filr }
| I0Estr(tstr) => cz_strlit(filr, tstr)
| I0Es00(s00) => (cz_str(filr, "\""); cz_str(filr, s00); cz_str(filr, "\""))
| I0Ec00(c00) =>
  (cz_str(filr, "(XATSCHR0 \""); cz_char_esc(filr, c00); cz_str(filr, "\")"))
| I0Echr(tchr) => cz_chrtok(filr, tchr)
//
(* names *)
| I0Ecst(dcst) => cz_sym(filr, d2cst_get_name(dcst))
| I0Evar(ivar) => cz_sym(filr, d2var_get_name(i0var_dvar$get(ivar)))
| I0Etop(xsym) => cz_sym(filr, xsym)
//
(* erased wrappers: emit the inner expression *)
| I0Etimp(tapp, _) => i0exp_cz0(filr, tapp)
| I0Etapq(fexp, _) => i0exp_cz0(filr, fexp)
| I0Etapp(fexp, _) => i0exp_cz0(filr, fexp)
| I0Esapq(fexp, _) => i0exp_cz0(filr, fexp)
| I0Esapp(fexp, _) => i0exp_cz0(filr, fexp)
| I0Eannot(e0, _, _) => i0exp_cz0(filr, e0)
| I0Et2pck(e0, _) => i0exp_cz0(filr, e0)
| I0Et2ped(e0, _) => i0exp_cz0(filr, e0)
| I0Elabck(e0, _) => i0exp_cz0(filr, e0)
| I0Erturn(_, e0) => i0exp_cz0(filr, e0)
| I0Ecenv(e0, _) => i0exp_cz0(filr, e0)
//
(* application -> (f a b ...), dropping [npf] leading proof args *)
| I0Edap0(fexp) => (cz_str(filr, "("); i0exp_cz0(filr, fexp); cz_str(filr, ")"))
| I0Edapp(fexp, npf, args) =>
  (
  cz_str(filr, "(");
  i0exp_cz0(filr, fexp);
  i0exp_cz0_args(filr, ldrop(args, npf));
  cz_str(filr, ")"))
//
(* control *)
| I0Eift0(tst, thopt, elopt) =>
  (
  cz_str(filr, "(if ");
  i0exp_cz0(filr, tst);
  cz_str(filr, " ");
  i0expopt_cz0(filr, thopt);
  cz_str(filr, " ");
  i0expopt_cz0(filr, elopt);
  cz_str(filr, ")"))
| I0Eseqn(inits, last) =>
  (
  cz_str(filr, "(begin ");
  i0exp_cz0_seq(filr, inits);
  i0exp_cz0(filr, last);
  cz_str(filr, ")"))
//
(* lambda / recursive-lambda.  Scheme closures capture lexically, so the
   pre-computed free-var lists are ignored.  A fix is a letrec over itself. *)
| I0Elam0(_, _, fargs, body, _) =>
  (
  cz_str(filr, "(lambda (");
  cz_fiarglst(filr, fargs);
  cz_str(filr, ") ");
  i0exp_cz0(filr, body);
  cz_str(filr, ")"))
| I0Efix0(_, _, fid, fargs, body, _) =>
  (
  cz_str(filr, "(letrec ((");
  cz_sym(filr, d2var_get_name(fid));
  cz_str(filr, " (lambda (");
  cz_fiarglst(filr, fargs);
  cz_str(filr, ") ");
  i0exp_cz0(filr, body);
  cz_str(filr, "))) ");
  cz_sym(filr, d2var_get_name(fid));
  cz_str(filr, ")"))
| I0Elet0(decls, body) =>
  (
  cz_str(filr, "(let () ");
  i0dclist_cz0(filr, decls);
  i0exp_cz0(filr, body);
  cz_str(filr, ")"))
| I0Ewhere(body, decls) =>
  (
  cz_str(filr, "(let () ");
  i0dclist_cz0(filr, decls);
  i0exp_cz0(filr, body);
  cz_str(filr, ")"))
//
(* case/pattern-match.  Scrutinee bound once to [czscrut]; each clause is a
   [when] that, on a successful pattern (+ guard), escapes via [czret] with
   the clause body.  A failed guard falls through to the next clause; falling
   off the end is a match failure. *)
| I0Ecas0(_, scrut, clss) =>
  (
  cz_str(filr, "(call/1cc (lambda (czret) (let ((czscrut ");
  i0exp_cz0(filr, scrut);
  cz_str(filr, ")) ");
  cz_clslst(filr, clss);
  cz_str(filr, " (XATS000_cfail))))"))
//
| _(*else*) =>
  (
  cz_str(filr, "(begin #f) ;; UNHANDLED-i0exp\n");
  prerrsln("[chez0emit] UNHANDLED i0exp"))
)//endof[i0exp_cz0]
//
(* one match clause -> (when <test> (let (<binds>) [<when guards>] (czret <body>))) *)
and
cz_cls
( filr: FILR, cls: i0cls): void =
(
case+ cls.node() of
| I0CLScls(gpt, body) =>
  (
  case+ gpt.node() of
  | I0GPTpat(pat) =>
    (
    cz_str(filr, "(when ");
    cz_pat_test(filr, pat);
    cz_str(filr, " (let (");
    cz_pat_binds(filr, pat);
    cz_str(filr, ") (czret ");
    i0exp_cz0(filr, body);
    cz_str(filr, ")))"))
  | I0GPTgua(pat, guas) =>
    (
    cz_str(filr, "(when ");
    cz_pat_test(filr, pat);
    cz_str(filr, " (let (");
    cz_pat_binds(filr, pat);
    cz_str(filr, ") (when ");
    cz_gualst(filr, guas);
    cz_str(filr, " (czret ");
    i0exp_cz0(filr, body);
    cz_str(filr, "))))")))
| I0CLSgpt(_) => ()(*guarded pattern, no body*)
)
//
and
cz_clslst
( filr: FILR, clss: i0clslst): void =
(
case+ clss of
| list_nil() => ()
| list_cons(c0, clss) => (cz_cls(filr, c0); cz_str(filr, " "); cz_clslst(filr, clss)))
//
(* guards -> (and g0 g1 ...) ; an I0GUAexp is a bool condition. *)
and
cz_gualst
( filr: FILR, guas: i0gualst): void =
(cz_str(filr, "(and"); cz_gualst_in(filr, guas); cz_str(filr, ")"))
//
and
cz_gualst_in
( filr: FILR, guas: i0gualst): void =
(
case+ guas of
| list_nil() => ()
| list_cons(g0, guas) => (cz_str(filr, " "); cz_gua(filr, g0); cz_gualst_in(filr, guas)))
//
and
cz_gua
( filr: FILR, gua: i0gua): void =
(
case+ gua.node() of
| I0GUAexp(e0) => i0exp_cz0(filr, e0)
| I0GUAmat(_, _) =>
  (cz_str(filr, "#t"); prerrsln("[chez0emit] UNHANDLED I0GUAmat")))
//
(* emit each application argument, space-prefixed *)
and
i0exp_cz0_args
( filr: FILR, args: i0explst): void =
(
case+ args of
| list_nil() => ()
| list_cons(a0, args) =>
  (cz_str(filr, " "); i0exp_cz0(filr, a0); i0exp_cz0_args(filr, args)))
//
(* emit a sequence prefix (each followed by a space) for I0Eseqn *)
and
i0exp_cz0_seq
( filr: FILR, es: i0explst): void =
(
case+ es of
| list_nil() => ()
| list_cons(e0, es) =>
  (i0exp_cz0(filr, e0); cz_str(filr, " "); i0exp_cz0_seq(filr, es)))
//
(* an optional branch (missing -> the unit value) *)
and
i0expopt_cz0
( filr: FILR, eopt: i0expopt): void =
(
case+ eopt of
| optn_nil() => cz_str(filr, "(if #f #f)")
| optn_cons(e0) => i0exp_cz0(filr, e0))
//
(* ****** ****** *)
//
(* one val binding *)
and
i0valdcl_cz0
( filr: FILR, ivd0: i0valdcl): void =
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
    (i0exp_cz0(filr, iexp); cz_str(filr, "\n")))
end//let
//
and
i0valdclist_cz0
( filr: FILR, ivs0: i0valdclist): void =
(
case+ ivs0 of
| list_nil() => ()
| list_cons(ivd0, ivs1) => (i0valdcl_cz0(filr, ivd0); i0valdclist_cz0(filr, ivs1)))
//
(* one fun binding -> (define (name params...) body).  Self/mutual recursion
   is free (top-level + internal defines are recursive in Scheme). *)
and
i0fundcl_cz0
( filr: FILR, ifun: i0fundcl): void =
let
val dpid = ifun.dpid()
val farg = ifun.farg()
val tdxp = ifun.tdxp()
in//let
case+ tdxp of
| TEQI0EXPnone() => ()
| TEQI0EXPsome(_, body) =>
  (
  cz_str(filr, "(define (");
  cz_sym(filr, d2var_get_name(dpid));
  cz_fiarglst(filr, farg);
  cz_str(filr, ") ");
  i0exp_cz0(filr, body);
  cz_str(filr, ")\n"))
end//let
//
and
i0fundclist_cz0
( filr: FILR, ifs0: i0fundclist): void =
(
case+ ifs0 of
| list_nil() => ()
| list_cons(if0, ifs1) => (i0fundcl_cz0(filr, if0); i0fundclist_cz0(filr, ifs1)))
//
(* ****** ****** *)
//
(* one top-level (or nested) declaration *)
and
i0dcl_cz0
( filr: FILR, idcl: i0dcl): void =
(
case+ idcl.node() of
| I0Dvaldclst(_, ivs0) => i0valdclist_cz0(filr, ivs0)
| I0Dfundclst(_, _, _, _, ifs0) => i0fundclist_cz0(filr, ifs0)
| I0Ddclst0(idcls) => i0dclist_cz0(filr, idcls)
| I0Dlocal0(ihead, ibody) =>
  (i0dclist_cz0(filr, ihead); i0dclist_cz0(filr, ibody))
//
(* wrappers: unwrap to the inner declaration.  Top-level functions surface
   as I0Ddclenv(I0Dfundclst(..), freevars); templates as I0Dtmpsub(..). *)
| I0Ddclenv(idcl, _) => i0dcl_cz0(filr, idcl)
| I0Dtmpsub(_, idcl) => i0dcl_cz0(filr, idcl)
| I0Dstatic(_, idcl) => i0dcl_cz0(filr, idcl)
//
(* extern decls are FFI/runtime-provided: emit no Scheme. *)
| I0Dextern _ => ()
//
(* erased / not-yet-handled at top level: no Scheme *)
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
)//endof[i0dcl_cz0]
//
and
i0dclist_cz0
( filr: FILR, idcls: i0dclist): void =
(
case+ idcls of
| list_nil() => ()
| list_cons(idcl, idcls) => (i0dcl_cz0(filr, idcl); i0dclist_cz0(filr, idcls)))
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0parsed_chez0emit
(ipar, filr) =
let
val parsed = i0parsed_parsed$get(ipar)
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
//endof[i0parsed_chez0emit]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_DATS_chez0emit.dats] *)
(***********************************************************************)
