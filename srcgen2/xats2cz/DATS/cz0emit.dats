(***********************************************************************)
(*                         Applied Type System                         *)
(***********************************************************************)
(*
xats2cz / cz0emit — intrep0 -> Chez Scheme emitter.

Emits Scheme expressions DIRECTLY from the expression-shaped intrep0 (no
intrep1/ANF).  Template instances (I0Etimp) are emitted INLINE as nested
lambdas at the use site (docs/03,04) — NO hoist/lift/seed.  A constant
reference (I0Ecst) is classified structurally (docs/04): $extnam -> bare
runtime name; non-template -> name_<decl-location>; a bare template is an
upstream bug.  Unhandled nodes FAIL LOUD.

M1 scope: scalars, val/decl, application, inline template instances,
$extnam primitives.  Compiled by the JS seed (defines _XATS2JS_ -> the
complete JS compile-time CATS resolves the prelude/templates).
*)
(* ****** ****** *)
#include
"./../../HATS/xatsopt_sats.hats"
#include
"./../../HATS/xatsopt_dpre.hats"
(* ****** ****** *)
#include
"./../HATS/libxatsopt.hats"
(* ****** ****** *)
#staload
"./../../xats2js/srcgen1/SATS/intrep0.sats"
(* ****** ****** *)
#staload
"./../SATS/cz0emit.sats"
(* ****** ****** *)
#symload node with token_get_node
(* ****** ****** *)
(* ===== output helpers (write to [filr] via the g_print$out hook) ===== *)
fun
cz_str
( filr: FILR, s0: strn): void =
( prints(s0)) where { #impltmp g_print$out<>() = filr }
//
fun
cz_int
( filr: FILR, i0: sint): void =
( prints(i0)) where { #impltmp g_print$out<>() = filr }
//
fun
cz_uint
( filr: FILR, u0: uint): void =
( prints(u0)) where { #impltmp g_print$out<>() = filr }
(* ****** ****** *)
(* cz_name: emit a symbol as a Scheme identifier.  (M1: the runtime/leaf names
   we touch are Scheme-safe; a full mangler — e.g. ' -> $ — comes with user
   symbols carrying special chars.) *)
fun
cz_name
( filr: FILR, xsym: sym_t): void =
cz_str(filr, symbl_get_name(xsym))
(* ****** ****** *)
(* cz_dvar: a dynamic variable -> <name>_<stamp> (stamp disambiguates same-named
   vars across scopes; same d2var renders identically at binding and use). *)
fun
cz_dvar
( filr: FILR, dvar: d2var): void =
(
cz_name(filr, d2var_get_name(dvar));
cz_str(filr, "_");
cz_uint(filr, stamp_get_uint(d2var_get_stmp(dvar))))
(* ****** ****** *)
(* cz_dcst: a constant reference, classified per docs/04.
   $extnam (X2NAMsome)        -> bare runtime name (the leaf primitive).
   else (non-template / none) -> <name>_<decl-location-stamp> (a top-level define
                                  materializes it; cross-file-safe via the canonical
                                  declaration location). *)
fun
cz_dcst_loc
( filr: FILR, dcst: d2cst): void =
(
cz_name(filr, d2cst_get_name(dcst));
cz_str(filr, "_");
fprint_loctn_as_stamp(filr, dcst.lctn((*0*))))
//
fun
cz_dcst
( filr: FILR, dcst: d2cst): void =
let
val xopt = the_d2cstmap_xnmfind(d2cst_get_stmp(dcst))
in//let
case+ xopt of
| ~optn_vt_nil() => cz_dcst_loc(filr, dcst)
| ~optn_vt_cons(xnam) =>
  (
  case+ xnam of
  | X2NAMnone() => cz_dcst_loc(filr, dcst)
  | X2NAMsome(_) => cz_name(filr, d2cst_get_name(dcst)))
end//let
(* ****** ****** *)
(* int / string literal tokens. *)
fun
cz_int_token
( filr: FILR, tok: token): void =
(
case+ tok.node() of
| T_INT01(rep) => cz_str(filr, rep)
| T_INT02(_, rep) => cz_str(filr, rep)
| _ (*else*) => cz_str(filr, "0"))
//
fun
cz_str_token
( filr: FILR, tok: token): void =
(
case- tok.node() of
| T_STRN1_clsd(rep, _) => cz_str(filr, rep)
| T_STRN2_ncls(rep, _) => cz_str(filr, rep))
//
fun
cz_flt_token
( filr: FILR, tok: token): void =
(
case+ tok.node() of
| T_FLT01(rep) => cz_str(filr, rep)
| T_FLT02(_, rep) => cz_str(filr, rep)
| _ (*else*) => cz_str(filr, "0.0"))
//
(* char literals (value rep = integer code).  A regular char -> (XATSCHR0 "<body>")
   (runtime maps the 1-char string to its code); escapes resolve to numeric codes.
   Reused from xats2chez's char machinery — correct emission logic, not a hack. *)
fun
cz_raw_char
( filr: FILR, c0: char): void =
( prints(c0)) where { #impltmp g_print$out<>() = filr }
//
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
cz_chr_blsh
( filr: FILR, rep: strn): void =
let
val n0 = strn_length(rep)
val c2 = strn_get$at(rep, 2)
in//let
if (c2 >= '0') * (c2 <= '9') then
  let
  fun loop(i0: sint): void =
  if (i0 >= n0-1) then () else (cz_raw_char(filr, strn_get$at(rep, i0)); loop(i0+1))
  in loop(2) end
else
(
case+ c2 of
| 'n' => cz_str(filr, "10")
| 't' => cz_str(filr, "9")
| 'r' => cz_str(filr, "13")
| 'b' => cz_str(filr, "8")
| 'f' => cz_str(filr, "12")
| 'v' => cz_str(filr, "11")
| 'a' => cz_str(filr, "7")
| '\\' => cz_str(filr, "92")
| '\'' => cz_str(filr, "39")
| '\"' => cz_str(filr, "34")
| _(*else: '\X' = literal X*) =>
  (cz_str(filr, "(XATSCHR0 \"");
   (if (c2 = '\"') then cz_str(filr, "\\\"") else cz_raw_char(filr, c2));
   cz_str(filr, "\")")))
end//let
//
fun
cz_chrtok
( filr: FILR, tchr: token): void =
(
case- tchr.node() of
| T_CHAR1_nil0 _ => cz_str(filr, "0")
| T_CHAR2_char(rep) => cz_chr_body(filr, rep)
| T_CHAR3_blsh(rep) => cz_chr_blsh(filr, rep))
//
(* ===== datatypes: value rep is datacon=#(ctag fields..) / tuple=#(fields..) ===== *)
(* cz_ctag: a constructor's tag as an int (exception ctag<0 -> its unique stamp,
   keeping construction/match/proj uniform; the tag is never printed). *)
fun
cz_ctag
( filr: FILR, dcon: d2con): void =
let val ct = d2con_get_ctag(dcon) in
  if (ct < 0)
  then (prints(stamp_get_uint(d2con_get_stmp(dcon)))) where { #impltmp g_print$out<>() = filr }
  else (prints(ct)) where { #impltmp g_print$out<>() = filr }
end
//
(* cz_lab_idx: a positional label as an int index (record symbol labels are the
   deferred hard case — no per-node type in xats2js intrep0 — emit 0 + warn). *)
fun
cz_lab_idx
( filr: FILR, lab: label): void =
(
case+ lab of
| LABint(i0) => (prints(i0)) where { #impltmp g_print$out<>() = filr }
| LABsym(_) => (cz_str(filr, "0"); prerrsln("[cz0emit] UNHANDLED record (symbol) label -> 0")))
//
(* cz_unwrap_con: if [iexp] is a (possibly type/fold-wrapped) data constructor,
   yield it — so an application of a constructor builds #(ctag fields..). *)
fun
cz_unwrap_con
( iexp: i0exp): optn(d2con) =
(
case+ iexp.node() of
| I0Econ(dcon) => optn_cons(dcon)
| I0Etapp(f0) => cz_unwrap_con(f0)
| I0Etapq(f0, _) => cz_unwrap_con(f0)
| I0Efold(f0) => cz_unwrap_con(f0)
| _ (*else*) => optn_nil())
//
(* cz_funpat_ctag: the ctag of the constructor in a (wrapped) datacon pattern. *)
fun
cz_funpat_ctag
( filr: FILR, fpat: i0pat): void =
(
case+ fpat.node() of
| I0Pcon(dcon) => cz_ctag(filr, dcon)
| I0Pdap1(p0) => cz_funpat_ctag(filr, p0)
| _ (*else*) => (cz_str(filr, "0"); prerrsln("[cz0emit] funpat ctag unresolved -> 0")))
//
(* field access against [czscrut]: datacon field (skip ctag, XATSPCON) or tuple
   field (vector-ref). *)
fun
cz_field_acc
( filr: FILR, iscon: bool, idx: sint): void =
(
if iscon
then (cz_str(filr, "(XATSPCON czscrut "); cz_int(filr, idx); cz_str(filr, ")"))
else (cz_str(filr, "(vector-ref czscrut "); cz_int(filr, idx); cz_str(filr, ")")))
//
(* sub-pattern tests/binds (ONE level: flat var/wildcard/literal/con sub-pats). *)
fun
cz_subtest1
( filr: FILR, iscon: bool, idx: sint, p0: i0pat): void =
(
case+ p0.node() of
| I0Pany() => () | I0Pvar(_) => ()
| I0Pint(t0) => (cz_str(filr, " (= "); cz_field_acc(filr, iscon, idx); cz_str(filr, " "); cz_int_token(filr, t0); cz_str(filr, ")"))
| I0Pchr(t0) => (cz_str(filr, " (= "); cz_field_acc(filr, iscon, idx); cz_str(filr, " "); cz_chrtok(filr, t0); cz_str(filr, ")"))
| I0Pbtf(s0) => (cz_str(filr, " (eq? "); cz_field_acc(filr, iscon, idx);
                 cz_str(filr, if strn_eq(symbl_get_name(s0), "true") then " #t)" else " #f)"))
| I0Pcon(dcon) => (cz_str(filr, " (XATS000_ctgeq "); cz_field_acc(filr, iscon, idx); cz_str(filr, " "); cz_ctag(filr, dcon); cz_str(filr, ")"))
| I0Pfree(q0) => cz_subtest1(filr, iscon, idx, q0)
| I0Pbang(q0) => cz_subtest1(filr, iscon, idx, q0)
| I0Pflat(q0) => cz_subtest1(filr, iscon, idx, q0)
| _ (*else*) => prerrsln("[cz0emit] UNHANDLED sub-pattern (test); deeper nesting TODO"))
//
fun
cz_subtests
( filr: FILR, iscon: bool, idx: sint, pats: i0patlst): void =
(
case+ pats of
| list_nil() => ()
| list_cons(p0, ps) => (cz_subtest1(filr, iscon, idx, p0); cz_subtests(filr, iscon, idx+1, ps)))
//
fun
cz_subbind1
( filr: FILR, iscon: bool, idx: sint, p0: i0pat): void =
(
case+ p0.node() of
| I0Pvar(dvar) => (cz_str(filr, "("); cz_dvar(filr, dvar); cz_str(filr, " "); cz_field_acc(filr, iscon, idx); cz_str(filr, ")"))
| I0Pfree(q0) => cz_subbind1(filr, iscon, idx, q0)
| I0Pbang(q0) => cz_subbind1(filr, iscon, idx, q0)
| I0Pflat(q0) => cz_subbind1(filr, iscon, idx, q0)
| _ (*else: any/literal/nested-con bind nothing at this level (M4)*) => ())
//
fun
cz_subbinds
( filr: FILR, iscon: bool, idx: sint, pats: i0patlst): void =
(
case+ pats of
| list_nil() => ()
| list_cons(p0, ps) => (cz_subbind1(filr, iscon, idx, p0); cz_subbinds(filr, iscon, idx+1, ps)))
//
(* cz_pat_test: a boolean Scheme expr testing the scrutinee [czscrut] against a
   pattern.  Flat literals + var/wildcard + one-level con/tuple patterns. *)
fun
cz_pat_test
( filr: FILR, pat: i0pat): void =
(
case+ pat.node() of
| I0Pany() => cz_str(filr, "#t")
| I0Pvar(_) => cz_str(filr, "#t")
| I0Pint(t0) => (cz_str(filr, "(= czscrut "); cz_int_token(filr, t0); cz_str(filr, ")"))
| I0Pchr(t0) => (cz_str(filr, "(= czscrut "); cz_chrtok(filr, t0); cz_str(filr, ")"))
| I0Pstr(t0) => (cz_str(filr, "(string=? czscrut "); cz_str_token(filr, t0); cz_str(filr, ")"))
| I0Pbtf(s0) =>
  cz_str(filr, if strn_eq(symbl_get_name(s0), "true") then "(eq? czscrut #t)" else "(eq? czscrut #f)")
| I0Pcon(dcon) =>
  (cz_str(filr, "(XATS000_ctgeq czscrut "); cz_ctag(filr, dcon); cz_str(filr, ")"))
| I0Pdap1(p0) =>
  (cz_str(filr, "(XATS000_ctgeq czscrut "); cz_funpat_ctag(filr, p0); cz_str(filr, ")"))
| I0Pdapp(fpat, argpats) =>
  (cz_str(filr, "(and (XATS000_ctgeq czscrut "); cz_funpat_ctag(filr, fpat); cz_str(filr, ")");
   cz_subtests(filr, true, 0, argpats); cz_str(filr, ")"))
| I0Ptup0(pats) =>
  (cz_str(filr, "(and #t"); cz_subtests(filr, false, 0, pats); cz_str(filr, ")"))
| I0Ptup1(_, pats) =>
  (cz_str(filr, "(and #t"); cz_subtests(filr, false, 0, pats); cz_str(filr, ")"))
| I0Pfree(p0) => cz_pat_test(filr, p0)
| I0Pbang(p0) => cz_pat_test(filr, p0)
| I0Pflat(p0) => cz_pat_test(filr, p0)
| _ (*else*) =>
  (
  cz_str(filr, "#f");
  prerrsln("[cz0emit] UNHANDLED-pat-test-NODE:");
  i0pat_fprint(pat, g_stderr((*0*))); prerrsln("")))
//
(* cz_pat_binds: the let-binding list CONTENT for a pattern (M2: var only). *)
fun
cz_pat_binds
( filr: FILR, pat: i0pat): void =
(
case+ pat.node() of
| I0Pvar(dvar) => (cz_str(filr, "("); cz_dvar(filr, dvar); cz_str(filr, " czscrut)"))
| I0Pdapp(_, argpats) => cz_subbinds(filr, true, 0, argpats)
| I0Ptup0(pats) => cz_subbinds(filr, false, 0, pats)
| I0Ptup1(_, pats) => cz_subbinds(filr, false, 0, pats)
| I0Pfree(p0) => cz_pat_binds(filr, p0)
| I0Pbang(p0) => cz_pat_binds(filr, p0)
| I0Pflat(p0) => cz_pat_binds(filr, p0)
| _ (*else*) => ())
(* ****** ****** *)
(* ===== the expression / decl walk (one mutually-recursive group) ===== *)
fun
i0exp_cz0
( filr: FILR, i0e0: i0exp): void =
(
case+ i0e0.node() of
//
| I0Ei00(i0) => cz_int(filr, i0)
| I0Eint(tok) => cz_int_token(filr, tok)
| I0Es00(s0) => (cz_str(filr, "\""); cz_str(filr, s0); cz_str(filr, "\""))
| I0Estr(tok) => cz_str_token(filr, tok)
//
(* bool: ATS bool = Scheme #t/#f (comparison prims return Scheme booleans). *)
| I0Eb00(b0) => cz_str(filr, if b0 then "#t" else "#f")
| I0Ebtf(sym) =>
  cz_str(filr, if strn_eq(symbl_get_name(sym), "true") then "#t" else "#f")
(* float: Scheme flonum, emitted from the token rep (e.g. "10.0"). *)
| I0Eflt(tok) => cz_flt_token(filr, tok)
(* char literal -> integer code (via XATSCHR0 / numeric escape). *)
| I0Echr(tok) => cz_chrtok(filr, tok)
//
(* if/then/else: optional branches -> _xunit when absent (ATS unit). *)
| I0Eift0(test, thopt, elopt) =>
  (cz_str(filr, "(if "); i0exp_cz0(filr, test); cz_str(filr, " ");
   cz_branchopt(filr, thopt); cz_str(filr, " ");
   cz_branchopt(filr, elopt); cz_str(filr, ")"))
//
(* lambda -> (lambda (params) body).  Native lexical capture on Chez. *)
| I0Elam0(_, fargs, body) =>
  (cz_str(filr, "(lambda ("); cz_params(filr, fargs); cz_str(filr, ") ");
   i0exp_cz0(filr, body); cz_str(filr, ")"))
(* fix (recursive lambda) -> (letrec ((fid (lambda (params) body))) fid). *)
| I0Efix0(_, fid, fargs, body) =>
  (cz_str(filr, "(letrec (("); cz_dvar(filr, fid); cz_str(filr, " (lambda (");
   cz_params(filr, fargs); cz_str(filr, ") "); i0exp_cz0(filr, body);
   cz_str(filr, "))) "); cz_dvar(filr, fid); cz_str(filr, ")"))
//
(* case: scrutinee bound once to czscrut; each clause is a (when <pat-test> (let
   (<binds>) [(when <guard>)] (czret <body>))).  A failed pattern/guard falls
   through; falling off the end is a match failure (XATS000_cfail).  call/1cc
   gives the first-match early exit. *)
| I0Ecas0(_, scrut, clss) =>
  (cz_str(filr, "(call/1cc (lambda (czret) (let ((czscrut ");
   i0exp_cz0(filr, scrut); cz_str(filr, ")) ");
   cz_clslst(filr, clss); cz_str(filr, " (XATS000_cfail))))"))
//
| I0Evar(dvar) => cz_dvar(filr, dvar)
| I0Ecst(dcst) => cz_dcst(filr, dcst)
| I0Etop(sym) => cz_name(filr, sym)
(* nullary data constructor -> #(ctag). *)
| I0Econ(dcon) => (cz_str(filr, "(vector "); cz_ctag(filr, dcon); cz_str(filr, ")"))
//
(* template instance: emit its impl INLINE as a nested lambda (docs/04). *)
| I0Etimp(_tapp, timp) => cz_timp_inline(filr, timp)
| I0Etapp(i0f) => i0exp_cz0(filr, i0f)
| I0Etapq(i0f, _) => i0exp_cz0(filr, i0f)
| I0Efold(e0) => i0exp_cz0(filr, e0)  (* linear fold: identity in the uniform vector rep *)
//
(* application: a data constructor builds #(ctag fields..); else a normal call. *)
| I0Edapp(i0f, args) =>
  (case+ cz_unwrap_con(i0f) of
   | optn_cons(dcon) =>
     (cz_str(filr, "(vector "); cz_ctag(filr, dcon); cz_args(filr, args); cz_str(filr, ")"))
   | optn_nil() =>
     (cz_str(filr, "("); i0exp_cz0(filr, i0f); cz_args(filr, args); cz_str(filr, ")")))
| I0Edap0(i0f) =>
  (case+ cz_unwrap_con(i0f) of
   | optn_cons(dcon) => (cz_str(filr, "(vector "); cz_ctag(filr, dcon); cz_str(filr, ")"))
   | optn_nil() => (cz_str(filr, "("); i0exp_cz0(filr, i0f); cz_str(filr, ")")))
//
(* tuples / records -> #(fields..) (uniform vector rep). *)
| I0Etup0(es) => (cz_str(filr, "(vector"); cz_args(filr, es); cz_str(filr, ")"))
| I0Etup1(_, es) => (cz_str(filr, "(vector"); cz_args(filr, es); cz_str(filr, ")"))
| I0Ercd2(_, lies) => (cz_str(filr, "(vector"); cz_l0i0e_vec(filr, lies); cz_str(filr, ")"))
(* projections: datacon field (XATSPCON, skips ctag) / tuple field (vector-ref). *)
| I0Epcon(lab, con) =>
  (cz_str(filr, "(XATSPCON "); i0exp_cz0(filr, con); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, ")"))
| I0Eproj(lab, tup) =>
  (cz_str(filr, "(vector-ref "); i0exp_cz0(filr, tup); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, ")"))
| I0Epflt(lab, tup) =>
  (cz_str(filr, "(vector-ref "); i0exp_cz0(filr, tup); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, ")"))
//
| I0Enone0() => cz_str(filr, "_xunit")
//
(* mutable left-values: a var is a box; read=XATS_lvget, write=XATS_lvset;
   &(deref) cancels to the lvalue; &(field) is a field-address #(cell idx). *)
| I0Eflat(e0) => (cz_str(filr, "(XATS_lvget "); i0exp_cz0(filr, e0); cz_str(filr, ")"))
| I0Efree(e0) => i0exp_cz0(filr, e0)
| I0Edp2tr(e0) => (cz_str(filr, "(XATS_lvget "); i0exp_cz0(filr, e0); cz_str(filr, ")"))
| I0Eaddr(e0) =>
  (case+ e0.node() of
   | I0Eflat(inner) => i0exp_cz0(filr, inner)
   | I0Eproj(lab, base) =>
     (cz_str(filr, "(vector "); i0exp_cz0(filr, base); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, ")"))
   | I0Epflt(lab, base) =>
     (cz_str(filr, "(vector "); i0exp_cz0(filr, base); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, ")"))
   | I0Epcon(lab, con) =>
     (cz_str(filr, "(vector "); i0exp_cz0(filr, con); cz_str(filr, " (+ "); cz_lab_idx(filr, lab); cz_str(filr, " 1))"))
   | _ (*else*) => i0exp_cz0(filr, e0))
| I0Eassgn(lval, rval) => i0exp_cz0_assgn(filr, lval, rval)
//
(* exceptions: raise -> (raise e); try BODY with HANDLERS -> guard dispatching the
   handler clauses (re-raise if none match).  Exception ctags are unique stamps. *)
| I0Eraise(_, e0) => (cz_str(filr, "(raise "); i0exp_cz0(filr, e0); cz_str(filr, ")"))
| I0Etry0(_, body, handlers) =>
  (cz_str(filr, "(guard (czscrut "); cz_try_clslst(filr, handlers);
   cz_str(filr, " (else (raise czscrut))) "); i0exp_cz0(filr, body); cz_str(filr, ")"))
//
(* lazy: l0azy memoizes, l1azy is call-by-name; dl0az/dl1az force. *)
| I0El0azy(_, e0) => (cz_str(filr, "(XATS000_l0azy (lambda () "); i0exp_cz0(filr, e0); cz_str(filr, "))"))
| I0El1azy(_, e0, _) => (cz_str(filr, "(XATS000_l1azy (lambda (czlz) "); i0exp_cz0(filr, e0); cz_str(filr, "))"))
| I0Edl0az(e0) => (cz_str(filr, "(XATS000_dl0az "); i0exp_cz0(filr, e0); cz_str(filr, ")"))
| I0Edl1az(e0) => (cz_str(filr, "(XATS000_dl1az "); i0exp_cz0(filr, e0); cz_str(filr, ")"))
//
| I0Eseqn(inits, last) =>
  (cz_str(filr, "(begin "); cz_seq(filr, inits); i0exp_cz0(filr, last); cz_str(filr, ")"))
//
(* let/where: local decls (externs emit nothing; local funs/vals -> internal
   defines, which Scheme treats as letrec* — mutual recursion OK) then the body. *)
| I0Elet0(decls, scope) =>
  (cz_str(filr, "(let () "); i0dclist_cz0(filr, decls); i0exp_cz0(filr, scope); cz_str(filr, ")"))
| I0Ewhere(scope, decls) =>
  (cz_str(filr, "(let () "); i0dclist_cz0(filr, decls); i0exp_cz0(filr, scope); cz_str(filr, ")"))
//
| _ (*else*) =>
  (
  cz_str(filr, "(UNHANDLED-i0exp)");
  prerrsln("[cz0emit] UNHANDLED-i0exp-NODE:");
  i0exp_fprint(i0e0, g_stderr((*0*))); prerrsln(""))
)
//
and
cz_args
( filr: FILR, args: i0explst): void =
(
case+ args of
| list_nil() => ()
| list_cons(a0, rest) =>
  (cz_str(filr, " "); i0exp_cz0(filr, a0); cz_args(filr, rest)))
//
and
cz_seq
( filr: FILR, es: i0explst): void =
(
case+ es of
| list_nil() => ()
| list_cons(e0, rest) =>
  (i0exp_cz0(filr, e0); cz_str(filr, " "); cz_seq(filr, rest)))
//
and  (* record field VALUES in order (labels resolved positionally at construction) *)
cz_l0i0e_vec
( filr: FILR, lies: l0i0elst): void =
(
case+ lies of
| list_nil() => ()
| list_cons(lie, rest) =>
  (cz_str(filr, " ");
   (case+ lie of | I0LAB(_, e0) => i0exp_cz0(filr, e0));
   cz_l0i0e_vec(filr, rest)))
//
and
cz_branchopt
( filr: FILR, opt: i0expopt): void =
(
case+ opt of
| optn_nil() => cz_str(filr, "_xunit")
| optn_cons(e0) => i0exp_cz0(filr, e0))
//
and
cz_clslst
( filr: FILR, clss: i0clslst): void =
(
case+ clss of
| list_nil() => ()
| list_cons(cls, rest) => (cz_cls(filr, cls); cz_str(filr, " "); cz_clslst(filr, rest)))
//
and
cz_cls
( filr: FILR, cls: i0cls): void =
(
case+ cls.node() of
| I0CLSgpt(_) => ()
| I0CLScls(gpt, body) =>
  (
  case+ gpt.node() of
  | I0GPTpat(pat) =>
    (* (when <test> (let (<binds>) (czret <body>)))  *)
    (cz_str(filr, "(when "); cz_pat_test(filr, pat); cz_str(filr, " (let (");
     cz_pat_binds(filr, pat); cz_str(filr, ") (czret ");
     i0exp_cz0(filr, body); cz_str(filr, ")))"))
  | I0GPTgua(pat, guas) =>
    (* (when <test> (let (<binds>) (when <guard> (czret <body>))))  *)
    (cz_str(filr, "(when "); cz_pat_test(filr, pat); cz_str(filr, " (let (");
     cz_pat_binds(filr, pat); cz_str(filr, ") (when "); cz_gualst(filr, guas);
     cz_str(filr, " (czret "); i0exp_cz0(filr, body); cz_str(filr, "))))"))))
//
and
cz_gualst
( filr: FILR, guas: i0gualst): void =
(
cz_str(filr, "(and");
cz_gualst_loop(filr, guas);
cz_str(filr, ")"))
//
and
cz_gualst_loop
( filr: FILR, guas: i0gualst): void =
(
case+ guas of
| list_nil() => ()
| list_cons(gua, rest) =>
  (cz_str(filr, " ");
   (case+ gua.node() of
    | I0GUAexp(e0) => i0exp_cz0(filr, e0)
    | I0GUAmat(e0, _) => i0exp_cz0(filr, e0));
   cz_gualst_loop(filr, rest)))
//
(* assignment: a field lval -> vector-set!; else (box/field-address) -> XATS_lvset. *)
and
i0exp_cz0_assgn
( filr: FILR, lval: i0exp, rval: i0exp): void =
(
case+ lval.node() of
| I0Eflat(inner) =>
  (cz_str(filr, "(XATS_lvset "); i0exp_cz0(filr, inner); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| I0Eproj(lab, base) =>
  (cz_str(filr, "(vector-set! "); i0exp_cz0(filr, base); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| I0Epflt(lab, base) =>
  (cz_str(filr, "(vector-set! "); i0exp_cz0(filr, base); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| I0Epcon(lab, con) =>
  (cz_str(filr, "(vector-set! "); i0exp_cz0(filr, con); cz_str(filr, " (+ "); cz_lab_idx(filr, lab); cz_str(filr, " 1) "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| _ (*box var / field-address*) =>
  (cz_str(filr, "(XATS_lvset "); i0exp_cz0(filr, lval); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")")))
//
(* exception handler clause -> a guard clause (test expr); guard returns the body
   value directly (no czret/call-cc). *)
and
cz_try_cls
( filr: FILR, cls: i0cls): void =
(
case+ cls.node() of
| I0CLSgpt(_) => ()
| I0CLScls(gpt, body) =>
  (
  case+ gpt.node() of
  | I0GPTpat(pat) =>
    (cz_str(filr, "("); cz_pat_test(filr, pat); cz_str(filr, " (let (");
     cz_pat_binds(filr, pat); cz_str(filr, ") "); i0exp_cz0(filr, body); cz_str(filr, "))"))
  | I0GPTgua(pat, guas) =>
    (cz_str(filr, "((and "); cz_pat_test(filr, pat); cz_str(filr, " "); cz_gualst(filr, guas);
     cz_str(filr, ") (let ("); cz_pat_binds(filr, pat); cz_str(filr, ") ");
     i0exp_cz0(filr, body); cz_str(filr, "))"))))
//
and
cz_try_clslst
( filr: FILR, clss: i0clslst): void =
(
case+ clss of
| list_nil() => ()
| list_cons(c0, rest) => (cz_try_cls(filr, c0); cz_str(filr, " "); cz_try_clslst(filr, rest)))
//
(* mutable var -> (define <var> (box <init>)). *)
and
i0vardcl_cz0
( filr: FILR, ivd0: i0vardcl): void =
let
val dpid = ivd0.dpid((*0*))
val dini = ivd0.dini((*0*))
in//let
(
cz_str(filr, "(define "); cz_dvar(filr, dpid); cz_str(filr, " (box ");
(case+ dini of
 | TEQI0EXPnone() => cz_str(filr, "_xunit")
 | TEQI0EXPsome(_, e0) => i0exp_cz0(filr, e0));
cz_str(filr, "))\n"))
end//let
//
and
i0vardclist_cz0
( filr: FILR, ivs0: i0vardclist): void =
(
case+ ivs0 of
| list_nil() => ()
| list_cons(ivd0, rest) => (i0vardcl_cz0(filr, ivd0); i0vardclist_cz0(filr, rest)))
//
(* cz_timp_inline: emit a template instance as (lambda (params) body), taken from
   the frontend-resolved instance body in the t0imp.  A bodiless instance is an
   upstream resolution failure (docs/04) — emit a loud marker. *)
and
cz_timp_inline
( filr: FILR, timp: t0imp): void =
(
case+ timp.node() of
| T0IMPall1(_, _, dopt) => cz_timp_body(filr, dopt)
| T0IMPallx(_, _, dopt) => cz_timp_body(filr, dopt))
//
and
cz_timp_body
( filr: FILR, dopt: i0dclopt): void =
(
case+ dopt of
| optn_nil() =>
  (
  cz_str(filr, "(XATS_undef)");
  prerrsln("[cz0emit] BODILESS template instance (upstream resolution failure!)"))
| optn_cons(idcl) => cz_timp_dcl(filr, idcl))
//
and
cz_timp_dcl
( filr: FILR, idcl: i0dcl): void =
(
case+ idcl.node() of
| I0Dtmpsub(_, inner) => cz_timp_dcl(filr, inner)
| I0Dstatic(_, inner) => cz_timp_dcl(filr, inner)
| I0Ddclst0(ds) => cz_timp_dcl_lst(filr, ds)
| I0Dimplmnt0(_, _, _, fargs, body) =>
  (
  case+ fargs of
  (* point-free alias (#implfun f = g): forward args to the body value, which is
     itself a function — NOT a nullary thunk (which would mis-apply). *)
  | list_nil() =>
    (cz_str(filr, "(lambda czfwd (apply "); i0exp_cz0(filr, body); cz_str(filr, " czfwd))"))
  | _ =>
    (cz_str(filr, "(lambda ("); cz_params(filr, fargs); cz_str(filr, ") ");
     i0exp_cz0(filr, body); cz_str(filr, ")")))
| _ (*else*) =>
  (
  cz_str(filr, "(UNHANDLED-timp-dcl)");
  prerrsln("[cz0emit] UNHANDLED template-instance body decl:");
  i0dcl_fprint(idcl, g_stderr((*0*))); prerrsln("")))
//
and
cz_timp_dcl_lst
( filr: FILR, ds: i0dclist): void =
(
case+ ds of
| list_nil() => (cz_str(filr, "(XATS_undef)"))
| list_cons(d0, _) => cz_timp_dcl(filr, d0))
//
(* params: the fiarglst -> a flat Scheme parameter list. *)
and
cz_params
( filr: FILR, fargs: fiarglst): void =
(
case+ fargs of
| list_nil() => ()
| list_cons(fa, rest) => (cz_param1(filr, fa); cz_params(filr, rest)))
//
and
cz_param1
( filr: FILR, fa: fiarg): void =
(
case+ fa.node() of
| FIARGdarg(pats) => cz_param_pats(filr, pats))
//
and
cz_param_pats
( filr: FILR, pats: i0patlst): void =
(
case+ pats of
| list_nil() => ()
| list_cons(p0, rest) =>
  (cz_str(filr, " "); cz_param_name(filr, p0); cz_param_pats(filr, rest)))
//
and
cz_param_name
( filr: FILR, p0: i0pat): void =
(
case+ p0.node() of
| I0Pvar(dvar) => cz_dvar(filr, dvar)
| I0Pany() => cz_str(filr, "_p")
| _ (*else*) => cz_str(filr, "_p"))
//
(* ===== declarations ===== *)
and
i0dcl_cz0
( filr: FILR, idcl: i0dcl): void =
(
case+ idcl.node() of
| I0Dvaldclst(_, ivs) => i0valdclist_cz0(filr, ivs)
| I0Ddclst0(ds) => i0dclist_cz0(filr, ds)
| I0Dlocal0(h, b) => (i0dclist_cz0(filr, h); i0dclist_cz0(filr, b))
| I0Dstatic(_, d0) => i0dcl_cz0(filr, d0)
| I0Dtmpsub(_, d0) => i0dcl_cz0(filr, d0)
(* template impl: nothing (inlined at uses).  non-template handled in M2. *)
| I0Dimplmnt0(_, _, _, _, _) => ()
(* extern, includes, errck-dropped(none1), benign-empty: no Scheme. *)
| I0Dextern(_, _) => ()
| I0Dd3ecl(_) => ()
| I0Dinclude(_, _, _, _, _) => ()
| I0Dnone0() => ()
| I0Dnone1(_) => ()
| I0Dfundclst(_, _, _, ifs) => i0fundclist_cz0(filr, ifs)
| I0Dvardclst(_, ivs) => i0vardclist_cz0(filr, ivs)
| _ (*else*) =>
  (
  cz_str(filr, ";; UNHANDLED-i0dcl\n");
  prerrsln("[cz0emit] UNHANDLED-i0dcl-NODE:");
  i0dcl_fprint(idcl, g_stderr((*0*))); prerrsln(""))
)
//
and
i0dclist_cz0
( filr: FILR, ds: i0dclist): void =
(
case+ ds of
| list_nil() => ()
| list_cons(d0, rest) => (i0dcl_cz0(filr, d0); i0dclist_cz0(filr, rest)))
//
and
i0valdclist_cz0
( filr: FILR, ivs: i0valdclist): void =
(
case+ ivs of
| list_nil() => ()
| list_cons(iv, rest) => (i0valdcl_cz0(filr, iv); i0valdclist_cz0(filr, rest)))
//
and
i0valdcl_cz0
( filr: FILR, iv: i0valdcl): void =
let
val ipat = iv.ipat((*0*))
val tdxp = iv.tdxp((*0*))
in//let
case+ tdxp of
| TEQI0EXPnone() => ()
| TEQI0EXPsome(_, rhs) =>
  (
  case+ ipat.node() of
  | I0Pvar(dvar) =>
    (cz_str(filr, "(define "); cz_dvar(filr, dvar); cz_str(filr, " ");
     i0exp_cz0(filr, rhs); cz_str(filr, ")\n"))
  | _ (*unit/any: effectful top-level expr*) =>
    (i0exp_cz0(filr, rhs); cz_str(filr, "\n")))
end//let
//
(* one fun binding -> (define (name params) body).  Self/mutual recursion is free
   (top-level + internal defines are recursive in Scheme).  Name = the dpid d2var,
   matching the call site's I0Evar reference.  A TEMPLATE fun's define is dead code
   (uses are inlined) but harmless — Scheme never evaluates an unapplied lambda body. *)
and
i0fundcl_cz0
( filr: FILR, ifun: i0fundcl): void =
let
val dpid = ifun.dpid((*0*))
val farg = ifun.farg((*0*))
val tdxp = ifun.tdxp((*0*))
in//let
case+ tdxp of
| TEQI0EXPnone() => ()
| TEQI0EXPsome(_, body) =>
  (
  case+ farg of
  (* point-free (no arg groups): fun f = g -> forwarding lambda (defers a possibly
     forward-referenced body to call time, keeps arity). *)
  | list_nil() =>
    (cz_str(filr, "(define "); cz_dvar(filr, dpid);
     cz_str(filr, " (lambda czfwd (apply "); i0exp_cz0(filr, body);
     cz_str(filr, " czfwd)))\n"))
  | _ (*has arg groups*) =>
    (cz_str(filr, "(define ("); cz_dvar(filr, dpid); cz_params(filr, farg);
     cz_str(filr, ") "); i0exp_cz0(filr, body); cz_str(filr, ")\n")))
end//let
//
and
i0fundclist_cz0
( filr: FILR, ifs: i0fundclist): void =
(
case+ ifs of
| list_nil() => ()
| list_cons(if0, rest) => (i0fundcl_cz0(filr, if0); i0fundclist_cz0(filr, rest)))
(* ****** ****** *)
#implfun
i0parsed_cz0emit
( ipar, filr) =
let
val dopt = ipar.parsed((*0*))
in//let
cz_str(filr, ";;==XATS2CZ-BEGIN==\n");
(
case+ dopt of
| optn_nil() => ()
| optn_cons(idcls) => i0dclist_cz0(filr, idcls));
cz_str(filr, ";;==XATS2CZ-END==\n")
end//let
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2cz_DATS_cz0emit.dats] *)
(***********************************************************************)
