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
   cast (fcast/castfn)        -> identity (xs -> xs): a runtime no-op reinterpret,
                                  matching the JS XATSCAST(args)=args[0].  These are
                                  prelude decls cz0emit never emits, so they must NOT
                                  dangle as name_<loc>.
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
(
if d2cst_castq(dcst)
then cz_str(filr, "(lambda (czcastx) czcastx)")
else
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
end(*let*))
(* ****** ****** *)
(* cz_dimpl_name: the name of a (non-template) #implfun's resolved constant — its
   top-level define name, matching the name_<loc> at use sites (cf. JS dicstjs1). *)
fun
cz_dimpl_name
( filr: FILR, dimp: dimpl): void =
(
case+ dimp.node() of
| DIMPLone1(dcst) => cz_dcst_loc(filr, dcst)
| DIMPLone2(dcst, _) => cz_dcst_loc(filr, dcst)
| DIMPLnon1(_) =>
  (cz_str(filr, "XATS_undef_dimplnon1");
   prerrsln("[cz0emit] DIMPLnon1 (unresolved impl name) — TODO")))
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
(* cz_lab_sym: a record field label as a quoted Chez symbol — the key into the
   symbol-keyed record rep (the Chez analog of the JS object).  Construction and
   every projection route the label through here, so the keys always agree. *)
fun
cz_lab_sym
( filr: FILR, lab: label): void =
(
case+ lab of
| LABsym(s) => (cz_str(filr, "'"); cz_str(filr, symbl_get_name(s)))
| LABint(i0) => (cz_str(filr, "'f"); cz_int(filr, i0)))
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
(* === pattern match ACCESS PATHS (arbitrary nesting) ===
   A path is a list of (iscon, fieldidx) steps; HEAD = the OUTERMOST field wrap
   (the most-recently descended sub-pattern).  cz_emit_acc roots it at czscrut and
   composes XATSPCON (datacon, skips ctag at slot 0) / vector-ref (tuple) nests,
   e.g. C(D(x),_) gives x the access (XATSPCON (XATSPCON czscrut 0) 0). *)
fun
cz_emit_acc
( filr: FILR, path: list(@(bool, sint))): void =
(
case+ path of
| list_nil() => cz_str(filr, "czscrut")
| list_cons(@(iscon, idx), rest) =>
  (cz_str(filr, if iscon then "(XATSPCON " else "(vector-ref ");
   cz_emit_acc(filr, rest); cz_str(filr, " "); cz_int(filr, idx); cz_str(filr, ")")))
//
(* the ADDRESS of the field reached by [path] (head = that field's step), for a
   `!x` bang reference: #(container key), key = idx+1 datacon / idx tuple. *)
fun
cz_emit_addr
( filr: FILR, path: list(@(bool, sint))): void =
(
case+ path of
| list_nil() => cz_str(filr, "czscrut")
| list_cons(@(iscon, idx), rest) =>
  (cz_str(filr, "(vector "); cz_emit_acc(filr, rest); cz_str(filr, " ");
   (if iscon then (cz_str(filr, "(+ "); cz_int(filr, idx); cz_str(filr, " 1)")) else cz_int(filr, idx));
   cz_str(filr, ")")))
//
(* a sub-pattern whose match-test is always true (binds a var / ignores) — gets no
   test emitted, only a bind.  (Unwraps the linear free/bang/flat markers.) *)
fun
cz_pat_trivial
( p0: i0pat): bool =
(
case+ p0.node() of
| I0Pany() => true
| I0Pvar(_) => true
| I0Pfree(q0) => cz_pat_trivial(q0)
| I0Pbang(q0) => cz_pat_trivial(q0)
| I0Pflat(q0) => cz_pat_trivial(q0)
| _ (*else*) => false)
//
(* ===== pattern-val (`val[-] PAT = rhs`) destructuring =====
   A compound PAT emits  (define-values (v..) (let ((czpv rhs)) (values acc..))):
   one rhs evaluation (effects run once), czpv let-scoped so siblings don't clash.
   One level of fields; a `!x` field binds the field ADDRESS.  cz_pv_vars and
   cz_pv_accs walk PAT identically (both keyed off cz_pv_leafvar) so the var list
   and the values list stay the same length. *)
fun  (* tmp-parameterized field value/address (the scrutinee is Scheme var [tmp]) *)
cz_field_acc_at
( filr: FILR, iscon: bool, idx: sint, tmp: strn): void =
(
if iscon
then (cz_str(filr, "(XATSPCON "); cz_str(filr, tmp); cz_str(filr, " "); cz_int(filr, idx); cz_str(filr, ")"))
else (cz_str(filr, "(vector-ref "); cz_str(filr, tmp); cz_str(filr, " "); cz_int(filr, idx); cz_str(filr, ")")))
//
fun
cz_field_addr_at
( filr: FILR, iscon: bool, idx: sint, tmp: strn): void =
(
if iscon
then (cz_str(filr, "(vector "); cz_str(filr, tmp); cz_str(filr, " (+ "); cz_int(filr, idx); cz_str(filr, " 1))"))
else (cz_str(filr, "(vector "); cz_str(filr, tmp); cz_str(filr, " "); cz_int(filr, idx); cz_str(filr, ")")))
//
fun  (* the leaf bound var of a sub-pattern (unwrapping !/free/flat), or none *)
cz_pv_leafvar
( p0: i0pat): optn(d2var) =
(
case+ p0.node() of
| I0Pvar(dvar) => optn_cons(dvar)
| I0Pbang(q0) => cz_pv_leafvar(q0)
| I0Pfree(q0) => cz_pv_leafvar(q0)
| I0Pflat(q0) => cz_pv_leafvar(q0)
| _ (*else*) => optn_nil())
//
fun  (* does the sub-pattern carry a `!` bang (=> bind the field ADDRESS)? *)
cz_pv_isbang
( p0: i0pat): bool =
(
case+ p0.node() of
| I0Pbang(_) => true
| I0Pfree(q0) => cz_pv_isbang(q0)
| I0Pflat(q0) => cz_pv_isbang(q0)
| _ (*else*) => false)
//
fun  (* a sub-pattern that legitimately binds nothing (no warning needed) *)
cz_pv_nobind
( p0: i0pat): bool =
(
case+ p0.node() of
| I0Pany() => true | I0Pcon(_) => true
| I0Pint(_) => true | I0Pchr(_) => true | I0Pstr(_) => true | I0Pbtf(_) => true
| I0Pfree(q0) => cz_pv_nobind(q0)
| I0Pflat(q0) => cz_pv_nobind(q0)
| _ (*else*) => false)
//
fun  (* does the compound pattern bind at least one (one-level) variable? *)
cz_pat_hasvar
( pat: i0pat): bool =
(
case+ pat.node() of
| I0Pvar(_) => true
| I0Pfree(q0) => cz_pat_hasvar(q0)
| I0Pbang(q0) => cz_pat_hasvar(q0)
| I0Pflat(q0) => cz_pat_hasvar(q0)
| I0Pdapp(_, ps) => cz_patlst_hasvar(ps)
| I0Ptup0(ps) => cz_patlst_hasvar(ps)
| I0Ptup1(_, ps) => cz_patlst_hasvar(ps)
| _ (*else*) => false)
//
and
cz_patlst_hasvar
( ps: i0patlst): bool =
(
case+ ps of
| list_nil() => false
| list_cons(p0, r) =>
  (case+ cz_pv_leafvar(p0) of
   | optn_cons(_) => true
   | optn_nil() => cz_patlst_hasvar(r)))
//
fun  (* the bound var NAMES of a compound pattern, space-prefixed, in field order *)
cz_pv_vars
( filr: FILR, pat: i0pat): void =
(
case+ pat.node() of
| I0Pfree(q0) => cz_pv_vars(filr, q0)
| I0Pbang(q0) => cz_pv_vars(filr, q0)
| I0Pflat(q0) => cz_pv_vars(filr, q0)
| I0Pdapp(_, ps) => cz_pv_vars_lst(filr, ps)
| I0Ptup0(ps) => cz_pv_vars_lst(filr, ps)
| I0Ptup1(_, ps) => cz_pv_vars_lst(filr, ps)
| _ (*else*) => ())
//
and
cz_pv_vars_lst
( filr: FILR, ps: i0patlst): void =
(
case+ ps of
| list_nil() => ()
| list_cons(p0, r) =>
  ((case+ cz_pv_leafvar(p0) of
    | optn_cons(dv) => (cz_str(filr, " "); cz_dvar(filr, dv))
    | optn_nil() =>
      (if cz_pv_nobind(p0) then () else prerrsln("[cz0emit] UNHANDLED nested pattern-val sub-pattern; one-level only")));
   cz_pv_vars_lst(filr, r)))
//
fun  (* the field accesses (value, or address for `!x`), matching cz_pv_vars *)
cz_pv_accs
( filr: FILR, pat: i0pat): void =
(
case+ pat.node() of
| I0Pfree(q0) => cz_pv_accs(filr, q0)
| I0Pbang(q0) => cz_pv_accs(filr, q0)
| I0Pflat(q0) => cz_pv_accs(filr, q0)
| I0Pdapp(_, ps) => cz_pv_accs_lst(filr, true, 0, ps)
| I0Ptup0(ps) => cz_pv_accs_lst(filr, false, 0, ps)
| I0Ptup1(_, ps) => cz_pv_accs_lst(filr, false, 0, ps)
| _ (*else*) => ())
//
and
cz_pv_accs_lst
( filr: FILR, iscon: bool, idx: sint, ps: i0patlst): void =
(
case+ ps of
| list_nil() => ()
| list_cons(p0, r) =>
  ((case+ cz_pv_leafvar(p0) of
    | optn_cons(_) =>
      (cz_str(filr, " ");
       if cz_pv_isbang(p0)
       then cz_field_addr_at(filr, iscon, idx, "czpv")
       else cz_field_acc_at(filr, iscon, idx, "czpv"))
    | optn_nil() => ());
   cz_pv_accs_lst(filr, iscon, idx+1, r)))
//
(* cz_pat_test_p: a boolean Scheme test of the value at [path] (rooted at czscrut)
   against [pat] — RECURSIVE, so nested datacon/tuple sub-patterns test through a
   composed XATSPCON/vector-ref access.  cz_pat_test wraps it at the empty path. *)
fun
cz_pat_test_p
( filr: FILR, path: list(@(bool, sint)), pat: i0pat): void =
(
case+ pat.node() of
| I0Pany() => cz_str(filr, "#t")
| I0Pvar(_) => cz_str(filr, "#t")
| I0Pint(t0) => (cz_str(filr, "(= "); cz_emit_acc(filr, path); cz_str(filr, " "); cz_int_token(filr, t0); cz_str(filr, ")"))
| I0Pchr(t0) => (cz_str(filr, "(= "); cz_emit_acc(filr, path); cz_str(filr, " "); cz_chrtok(filr, t0); cz_str(filr, ")"))
| I0Pstr(t0) => (cz_str(filr, "(string=? "); cz_emit_acc(filr, path); cz_str(filr, " "); cz_str_token(filr, t0); cz_str(filr, ")"))
| I0Pbtf(s0) =>
  (cz_str(filr, "(eq? "); cz_emit_acc(filr, path);
   cz_str(filr, if strn_eq(symbl_get_name(s0), "true") then " #t)" else " #f)"))
| I0Pcon(dcon) =>
  (cz_str(filr, "(XATS000_ctgeq "); cz_emit_acc(filr, path); cz_str(filr, " "); cz_ctag(filr, dcon); cz_str(filr, ")"))
| I0Pdap1(p0) =>
  (cz_str(filr, "(XATS000_ctgeq "); cz_emit_acc(filr, path); cz_str(filr, " "); cz_funpat_ctag(filr, p0); cz_str(filr, ")"))
| I0Pdapp(fpat, argpats) =>
  (cz_str(filr, "(and (XATS000_ctgeq "); cz_emit_acc(filr, path); cz_str(filr, " "); cz_funpat_ctag(filr, fpat); cz_str(filr, ")");
   cz_subtests_p(filr, path, true, 0, argpats); cz_str(filr, ")"))
| I0Ptup0(pats) =>
  (cz_str(filr, "(and #t"); cz_subtests_p(filr, path, false, 0, pats); cz_str(filr, ")"))
| I0Ptup1(_, pats) =>
  (cz_str(filr, "(and #t"); cz_subtests_p(filr, path, false, 0, pats); cz_str(filr, ")"))
| I0Pfree(p0) => cz_pat_test_p(filr, path, p0)
| I0Pbang(p0) => cz_pat_test_p(filr, path, p0)
| I0Pflat(p0) => cz_pat_test_p(filr, path, p0)
| _ (*else*) =>
  (
  cz_str(filr, "#f");
  prerrsln("[cz0emit] UNHANDLED-pat-test-NODE:");
  i0pat_fprint(pat, g_stderr((*0*))); prerrsln("")))
//
and  (* sub-pattern tests: skip the always-true (var/wildcard) ones, descend the rest *)
cz_subtests_p
( filr: FILR, path: list(@(bool, sint)), iscon: bool, idx: sint, pats: i0patlst): void =
(
case+ pats of
| list_nil() => ()
| list_cons(p0, ps) =>
  ((if cz_pat_trivial(p0) then () else
      (cz_str(filr, " "); cz_pat_test_p(filr, list_cons(@(iscon, idx), path), p0)));
   cz_subtests_p(filr, path, iscon, idx+1, ps)))
//
(* cz_pat_binds_p: the let-binding pairs for [pat] at [path] — RECURSIVE; nested
   sub-pattern vars bind through composed accesses; a `!x` binds the field ADDRESS. *)
fun
cz_pat_binds_p
( filr: FILR, path: list(@(bool, sint)), pat: i0pat): void =
(
case+ pat.node() of
| I0Pvar(dvar) => (cz_str(filr, "("); cz_dvar(filr, dvar); cz_str(filr, " "); cz_emit_acc(filr, path); cz_str(filr, ")"))
| I0Pbang(q0) => cz_pat_binds_addr_p(filr, path, q0)
| I0Pfree(p0) => cz_pat_binds_p(filr, path, p0)
| I0Pflat(p0) => cz_pat_binds_p(filr, path, p0)
| I0Pdapp(_, argpats) => cz_subbinds_p(filr, path, true, 0, argpats)
| I0Ptup0(pats) => cz_subbinds_p(filr, path, false, 0, pats)
| I0Ptup1(_, pats) => cz_subbinds_p(filr, path, false, 0, pats)
| _ (*else: any/literal/nullary-con bind nothing*) => ())
//
and
cz_subbinds_p
( filr: FILR, path: list(@(bool, sint)), iscon: bool, idx: sint, pats: i0patlst): void =
(
case+ pats of
| list_nil() => ()
| list_cons(p0, ps) =>
  (cz_pat_binds_p(filr, list_cons(@(iscon, idx), path), p0);
   cz_subbinds_p(filr, path, iscon, idx+1, ps)))
//
and  (* `!x` at [path] binds x to the field ADDRESS (left-value) *)
cz_pat_binds_addr_p
( filr: FILR, path: list(@(bool, sint)), p0: i0pat): void =
(
case+ p0.node() of
| I0Pvar(dvar) => (cz_str(filr, "("); cz_dvar(filr, dvar); cz_str(filr, " "); cz_emit_addr(filr, path); cz_str(filr, ")"))
| I0Pbang(q0) => cz_pat_binds_addr_p(filr, path, q0)
| I0Pfree(q0) => cz_pat_binds_addr_p(filr, path, q0)
| I0Pflat(q0) => cz_pat_binds_addr_p(filr, path, q0)
| _ (*else*) => ())
//
fun  (* wrappers: match at the root (empty path = czscrut) *)
cz_pat_test
( filr: FILR, pat: i0pat): void = cz_pat_test_p(filr, list_nil(), pat)
//
fun
cz_pat_binds
( filr: FILR, pat: i0pat): void = cz_pat_binds_p(filr, list_nil(), pat)
(* ****** ****** *)
(* ===== function parameters ===== *)
(* A function param that is a bare variable binds directly as a Scheme param; a
   compound pattern (tuple/datacon) becomes a fresh czarg<i> destructured in the
   body prologue (cz_fnbody).  The call site already tuples the args into a
   #(..), so the callee just unpacks its single vector param. *)
fun
cz_param_isvar
( p0: i0pat): bool =
(
case+ p0.node() of
| I0Pvar(_) => true
| I0Pfree(q0) => cz_param_isvar(q0)
| I0Pbang(q0) => cz_param_isvar(q0)
| I0Pflat(q0) => cz_param_isvar(q0)
| _ (*else*) => false)
//
fun  (* the bound var name of a (possibly linear-wrapped) var pattern *)
cz_param_var
( filr: FILR, p0: i0pat): void =
(
case+ p0.node() of
| I0Pvar(dvar) => cz_dvar(filr, dvar)
| I0Pfree(q0) => cz_param_var(filr, q0)
| I0Pbang(q0) => cz_param_var(filr, q0)
| I0Pflat(q0) => cz_param_var(filr, q0)
| _ (*else*) => cz_str(filr, "_p"))
//
fun  (* a param that needs a destructuring prologue (binds sub-vars) *)
cz_param_compound
( p0: i0pat): bool =
(
case+ p0.node() of
| I0Ptup0(_) => true
| I0Ptup1(_, _) => true
| I0Pdapp(_, _) => true
| I0Pfree(q0) => cz_param_compound(q0)
| I0Pbang(q0) => cz_param_compound(q0)
| I0Pflat(q0) => cz_param_compound(q0)
| _ (*else*) => false)
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
   cz_fnbody(filr, fargs, body); cz_str(filr, ")"))
(* fix (recursive lambda) -> (letrec ((fid (lambda (params) body))) fid). *)
| I0Efix0(_, fid, fargs, body) =>
  (cz_str(filr, "(letrec (("); cz_dvar(filr, fid); cz_str(filr, " (lambda (");
   cz_params(filr, fargs); cz_str(filr, ") "); cz_fnbody(filr, fargs, body);
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
(* `_` in value position: the omitted/topmost value the checker fills.  Like the
   JS backend (XATSTOP0 = undefined), emit a fixed placeholder never demanded. *)
| I0Etop(_) => cz_str(filr, "XATSTOP0")
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
(* tuples -> #(fields..) positional vector; records -> symbol-keyed XATS_rcd2
   (the JS object analog — projections are by SYMBOL, type erased so position is
   not recoverable; mirror the JS object-rep, not a positional guess). *)
| I0Etup0(es) => (cz_str(filr, "(vector"); cz_args(filr, es); cz_str(filr, ")"))
| I0Etup1(_, es) => (cz_str(filr, "(vector"); cz_args(filr, es); cz_str(filr, ")"))
| I0Ercd2(_, lies) => (cz_str(filr, "(XATS_rcd2"); cz_l0i0e_rcd(filr, lies); cz_str(filr, ")"))
(* projections: datacon field (XATSPCON, skips ctag) / tuple|record field
   (cz_proj_read dispatches on label kind: int -> vector-ref, sym -> XATS_rsel). *)
| I0Epcon(lab, con) =>
  (cz_str(filr, "(XATSPCON "); i0exp_cz0(filr, con); cz_str(filr, " "); cz_lab_idx(filr, lab); cz_str(filr, ")"))
| I0Eproj(lab, tup) => cz_proj_read(filr, lab, tup)
| I0Epflt(lab, tup) => cz_proj_read(filr, lab, tup)
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
   | I0Eproj(lab, base) => cz_addr_field(filr, lab, base)
   | I0Epflt(lab, base) => cz_addr_field(filr, lab, base)
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
| I0Elet0(decls, scope) => cz_dcl_body(filr, decls, scope)
| I0Ewhere(scope, decls) => cz_dcl_body(filr, decls, scope)
//
(* I0Ec00 = a char CONSTANT (e.g. the -1 EOF sentinel); emit (XATSCHR0 "<c>") as
   the JS does (the runtime maps the 1-char string to its code, == JS XATSCHR0). *)
(* I0Ec00 = a char CONSTANT.  Emit its integer code directly (cz0emit's char rep IS
   the int code) -- NOT via a Scheme string: the lexer's EOF sentinel is the char -1,
   and routing -1 through prints/a string byte throws and truncates the form.  char
   and sint share the runtime rep, so reinterpret-cast to read the code. *)
| I0Ec00(c0) => cz_int(filr, $UN.cast10{sint}(c0))
| I0Ef00 _ => (cz_str(filr, "0.0"); prerrsln("[cz0emit] I0Ef00 (float const) -> 0.0, TODO"))
| I0Eeval(e0) => i0exp_cz0(filr, e0)            (* eval-builtin: emit the inner expr *)
| I0Eextnam(_, nam) => g1nam_fprint(nam, filr)  (* external name reference *)
| I0Esynext _ => (cz_str(filr, "(XATS_undef)"); prerrsln("[cz0emit] I0Esynext -> undef, TODO"))
| I0Enone1 _ => cz_str(filr, "_xunit")          (* error marker (cf. I0Enone0) *)
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
and  (* record fields as alternating  'label value  args to XATS_rcd2. *)
cz_l0i0e_rcd
( filr: FILR, lies: l0i0elst): void =
(
case+ lies of
| list_nil() => ()
| list_cons(lie, rest) =>
  (cz_str(filr, " ");
   (case+ lie of
    | I0LAB(lab, e0) =>
      (cz_lab_sym(filr, lab); cz_str(filr, " "); i0exp_cz0(filr, e0)));
   cz_l0i0e_rcd(filr, rest)))
//
and  (* field READ: tuple (int) -> vector-ref ; record (sym) -> XATS_rsel. *)
cz_proj_read
( filr: FILR, lab: label, tup: i0exp): void =
(
case+ lab of
| LABint(i) =>
  (cz_str(filr, "(vector-ref "); i0exp_cz0(filr, tup); cz_str(filr, " "); cz_int(filr, i); cz_str(filr, ")"))
| LABsym(_) =>
  (cz_str(filr, "(XATS_rsel "); i0exp_cz0(filr, tup); cz_str(filr, " "); cz_lab_sym(filr, lab); cz_str(filr, ")")))
//
and  (* field WRITE: tuple (int) -> vector-set! ; record (sym) -> XATS_rset. *)
cz_proj_write
( filr: FILR, lab: label, base: i0exp, rval: i0exp): void =
(
case+ lab of
| LABint(i) =>
  (cz_str(filr, "(vector-set! "); i0exp_cz0(filr, base); cz_str(filr, " "); cz_int(filr, i); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| LABsym(_) =>
  (cz_str(filr, "(XATS_rset "); i0exp_cz0(filr, base); cz_str(filr, " "); cz_lab_sym(filr, lab); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")")))
//
and  (* field ADDRESS: #(container key) — XATS_lvget/lvset dispatch on (symbol? key). *)
cz_addr_field
( filr: FILR, lab: label, base: i0exp): void =
(
cz_str(filr, "(vector "); i0exp_cz0(filr, base); cz_str(filr, " ");
(case+ lab of | LABint(i) => cz_int(filr, i) | LABsym(_) => cz_lab_sym(filr, lab));
cz_str(filr, ")"))
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
(* a deref lvalue (flat var / pointer target): assign THROUGH the cell — one
   XATS_lvset on the cell itself.  Both read as (XATS_lvget e0), so symmetric.
   (The default below would double-deref: (XATS_lvset (XATS_lvget e0) v).) *)
| I0Eflat(inner) =>
  (cz_str(filr, "(XATS_lvset "); i0exp_cz0(filr, inner); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| I0Edp2tr(inner) =>
  (cz_str(filr, "(XATS_lvset "); i0exp_cz0(filr, inner); cz_str(filr, " "); i0exp_cz0(filr, rval); cz_str(filr, ")"))
| I0Eproj(lab, base) => cz_proj_write(filr, lab, base, rval)
| I0Epflt(lab, base) => cz_proj_write(filr, lab, base, rval)
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
     cz_fnbody(filr, fargs, body); cz_str(filr, ")")))
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
(* params: the fiarglst -> a flat Scheme parameter list.  Var patterns bind by
   name; a compound (tuple/datacon) pattern becomes a fresh czarg<i>. *)
and
cz_params
( filr: FILR, fargs: fiarglst): void =
let
  fun
  loop_pats(pats: i0patlst, i: sint): sint =
  (
  case+ pats of
  | list_nil() => i
  | list_cons(p0, rest) =>
    (cz_str(filr, " ");
     (if cz_param_isvar(p0)
      then cz_param_var(filr, p0)
      else (cz_str(filr, "czarg"); cz_int(filr, i)));
     loop_pats(rest, i+1)))
  fun
  loop_fa(fas: fiarglst, i: sint): sint =
  (
  case+ fas of
  | list_nil() => i
  | list_cons(fa, rest) =>
    (case+ fa.node() of | FIARGdarg(pats) => loop_fa(rest, loop_pats(pats, i))))
in
  let val _ = loop_fa(fargs, 0) in () end
end
//
(* cz_fnbody: a function/lambda body wrapped in its param-destructuring prologue.
   Each compound param czarg<i> is unpacked via
   (let ((czscrut czarg<i>)) (let (<cz_pat_binds>) <body>)). *)
and
cz_fnbody
( filr: FILR, fargs: fiarglst, body: i0exp): void =
let
  fun
  open_pats(pats: i0patlst, i: sint): sint =
  (
  case+ pats of
  | list_nil() => i
  | list_cons(p0, rest) =>
    ((if cz_param_compound(p0)
      then (cz_str(filr, "(let ((czscrut czarg"); cz_int(filr, i);
            cz_str(filr, ")) (let ("); cz_pat_binds(filr, p0); cz_str(filr, ") ")));
     open_pats(rest, i+1)))
  fun
  open_fa(fas: fiarglst, i: sint): sint =
  (
  case+ fas of
  | list_nil() => i
  | list_cons(fa, rest) =>
    (case+ fa.node() of | FIARGdarg(pats) => open_fa(rest, open_pats(pats, i))))
  fun
  close_pats(pats: i0patlst): void =
  (
  case+ pats of
  | list_nil() => ()
  | list_cons(p0, rest) =>
    ((if cz_param_compound(p0) then cz_str(filr, "))")); close_pats(rest)))
  fun
  close_fa(fas: fiarglst): void =
  (
  case+ fas of
  | list_nil() => ()
  | list_cons(fa, rest) =>
    ((case+ fa.node() of | FIARGdarg(pats) => close_pats(pats)); close_fa(rest)))
in
  let val _ = open_fa(fargs, 0) in
    (i0exp_cz0(filr, body); close_fa(fargs))
  end
end
//
(* ----- inner let/local/where bodies -----
   Chez requires internal definitions to PRECEDE expressions in a body, but ATS
   let/local/where freely interleave value-bindings and statements.  So rather than
   a flat (let () <define...> <expr...> scope) we emit a RIGHT-NESTED chain: each
   binding opens its own scope (let / letrec / let-values), each statement is
   sequenced via begin, and the scope-expr sits innermost -- so every define-like
   form is at the head of its own body.  (Top-level decls keep the flat i0*_cz0
   path: Chez --script allows interleaving at the program top level.) *)
and
cz_dcl_body
( filr: FILR, decls: i0dclist, body: i0exp): void =
(
case+ decls of
| list_nil() => i0exp_cz0(filr, body)
| list_cons(d0, rest) =>
  (case+ d0.node() of
   | I0Dvaldclst(_, ivs) => cz_val_body(filr, ivs, rest, body)
   | I0Dvardclst(_, ivs) => cz_var_body(filr, ivs, rest, body)
   | I0Dfundclst(_, _, _, ifs) =>
     (cz_str(filr, "(letrec ("); cz_fundcl_binds(filr, ifs);
      cz_str(filr, ") "); cz_dcl_body(filr, rest, body); cz_str(filr, ")"))
   | I0Dimplmnt0(_, _, dimp, fargs, ibody) =>
     if dimpl_tempq(dimp)
     then cz_dcl_body(filr, rest, body)   (* template impl: inlined at uses *)
     else
       (cz_str(filr, "(letrec (("); cz_dimpl_name(filr, dimp);
        (case+ fargs of
         | list_nil() =>
           (cz_str(filr, " (lambda czfwd (apply "); i0exp_cz0(filr, ibody);
            cz_str(filr, " czfwd))"))
         | _ =>
           (cz_str(filr, " (lambda ("); cz_params(filr, fargs); cz_str(filr, ") ");
            cz_fnbody(filr, fargs, ibody); cz_str(filr, ")")));
        cz_str(filr, ")) "); cz_dcl_body(filr, rest, body); cz_str(filr, ")"))
   (* local/dclst/static/tmpsub: splice into the sequence (names are loc-stamped,
      so the slight over-scoping of a local-head is collision-free). *)
   | I0Dlocal0(h, b) => cz_dcl_body(filr, list_append(h, list_append(b, rest)), body)
   | I0Ddclst0(ds) => cz_dcl_body(filr, list_append(ds, rest), body)
   | I0Dstatic(_, d1) => cz_dcl_body(filr, list_cons(d1, rest), body)
   | I0Dtmpsub(_, d1) => cz_dcl_body(filr, list_cons(d1, rest), body)
   (* extern/include/d3ecl/errck-none: no Scheme, just continue *)
   | I0Dextern(_, _) => cz_dcl_body(filr, rest, body)
   | I0Dd3ecl(_) => cz_dcl_body(filr, rest, body)
   | I0Dinclude(_, _, _, _, _) => cz_dcl_body(filr, rest, body)
   | I0Dnone0() => cz_dcl_body(filr, rest, body)
   | I0Dnone1(_) => cz_dcl_body(filr, rest, body)
   | _ (*else*) =>
     (cz_str(filr, ";;UNHANDLED-i0dcl-in-body ");
      prerrsln("[cz0emit] UNHANDLED-i0dcl in let/where body");
      i0dcl_fprint(d0, g_stderr((*0*))); prerrsln("");
      cz_dcl_body(filr, rest, body)))
)
//
and  (* each val: var -> (let ((x e)) ..); compound-with-vars -> let-values; else begin *)
cz_val_body
( filr: FILR, ivs: i0valdclist, rest: i0dclist, body: i0exp): void =
(
case+ ivs of
| list_nil() => cz_dcl_body(filr, rest, body)
| list_cons(iv, ivs_rest) =>
  let
    val ipat = iv.ipat((*0*))
    val tdxp = iv.tdxp((*0*))
  in
    case+ tdxp of
    | TEQI0EXPnone() => cz_val_body(filr, ivs_rest, rest, body)
    | TEQI0EXPsome(_, rhs) =>
      (case+ ipat.node() of
       | I0Pvar(dvar) =>
         (cz_str(filr, "(let (("); cz_dvar(filr, dvar); cz_str(filr, " ");
          i0exp_cz0(filr, rhs); cz_str(filr, ")) ");
          cz_val_body(filr, ivs_rest, rest, body); cz_str(filr, ")"))
       | _ (*else*) =>
         if cz_pat_hasvar(ipat)
         then
           (cz_str(filr, "(let-values ((("); cz_pv_vars(filr, ipat);
            cz_str(filr, ") (let ((czpv "); i0exp_cz0(filr, rhs);
            cz_str(filr, ")) (values"); cz_pv_accs(filr, ipat); cz_str(filr, ")))) ");
            cz_val_body(filr, ivs_rest, rest, body); cz_str(filr, ")"))
         else
           (cz_str(filr, "(begin "); i0exp_cz0(filr, rhs); cz_str(filr, " ");
            cz_val_body(filr, ivs_rest, rest, body); cz_str(filr, ")")))
  end
)
//
and  (* each var -> (let ((v (box init))) ..) *)
cz_var_body
( filr: FILR, ivs: i0vardclist, rest: i0dclist, body: i0exp): void =
(
case+ ivs of
| list_nil() => cz_dcl_body(filr, rest, body)
| list_cons(ivd0, ivs_rest) =>
  let
    val dpid = ivd0.dpid((*0*))
    val dini = ivd0.dini((*0*))
  in
    (cz_str(filr, "(let (("); cz_dvar(filr, dpid); cz_str(filr, " (box ");
     (case+ dini of
      | TEQI0EXPnone() => cz_str(filr, "_xunit")
      | TEQI0EXPsome(_, e0) => i0exp_cz0(filr, e0));
     cz_str(filr, "))) ");
     cz_var_body(filr, ivs_rest, rest, body); cz_str(filr, ")"))
  end
)
//
and  (* letrec binds for a (mutually-recursive) fun group: (name (lambda ..)) ... *)
cz_fundcl_binds
( filr: FILR, ifs: i0fundclist): void =
(
case+ ifs of
| list_nil() => ()
| list_cons(ifun, rest) =>
  let
    val dpid = ifun.dpid((*0*))
    val farg = ifun.farg((*0*))
    val tdxp = ifun.tdxp((*0*))
  in
    ((case+ tdxp of
      | TEQI0EXPnone() => ()
      | TEQI0EXPsome(_, fbody) =>
        (case+ farg of
         | list_nil() =>
           (cz_str(filr, "("); cz_dvar(filr, dpid);
            cz_str(filr, " (lambda czfwd (apply "); i0exp_cz0(filr, fbody);
            cz_str(filr, " czfwd))) "))
         | _ =>
           (cz_str(filr, "("); cz_dvar(filr, dpid);
            cz_str(filr, " (lambda ("); cz_params(filr, farg); cz_str(filr, ") ");
            cz_fnbody(filr, farg, fbody); cz_str(filr, ")) "))));
     cz_fundcl_binds(filr, rest))
  end
)
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
(* #implfun: a template impl emits NOTHING (inlined at uses); a NON-template
   impl emits a top-level define (cf. JS f0_implmnt0 / i0fundcl_cz0). *)
| I0Dimplmnt0(_, _, dimp, fargs, body) =>
  if dimpl_tempq(dimp)
  then ()
  else
    (case+ fargs of
     | list_nil() =>
       (cz_str(filr, "(define "); cz_dimpl_name(filr, dimp);
        cz_str(filr, " (lambda czfwd (apply "); i0exp_cz0(filr, body);
        cz_str(filr, " czfwd)))\n"))
     | _ =>
       (cz_str(filr, "(define ("); cz_dimpl_name(filr, dimp); cz_params(filr, fargs);
        cz_str(filr, ") "); cz_fnbody(filr, fargs, body); cz_str(filr, ")\n")))
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
  (* compound pattern that binds vars (datacon/tuple): destructure rhs ONCE via
     define-values.  Otherwise (unit (), wildcard, ...): effectful statement. *)
  | _ (*else*) =>
    (if cz_pat_hasvar(ipat)
     then (cz_str(filr, "(define-values ("); cz_pv_vars(filr, ipat);
           cz_str(filr, ") (let ((czpv "); i0exp_cz0(filr, rhs);
           cz_str(filr, ")) (values"); cz_pv_accs(filr, ipat); cz_str(filr, ")))\n"))
     else (i0exp_cz0(filr, rhs); cz_str(filr, "\n"))))
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
     cz_str(filr, ") "); cz_fnbody(filr, farg, body); cz_str(filr, ")\n")))
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
