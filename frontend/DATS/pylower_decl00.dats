(* ****** ****** *)
(*
** M3 — Python-surface frontend: declaration lowering (pcdecl -> d2ecl) + module driver.
**
** Mirrors trans12_decl00.dats: a top-level def group -> D2Cfundclst (template F, shared
** lower_fungroup in pylower_dynexp), a `val p = e` -> D2Cvaldclst (template C), a staload of
** pyrt -> a no-op (the prelude names the functional core uses all resolve via the tr12env
** GLOBAL fall-through with NO explicit staload — PROBE-VERIFIED: `+`/`print`/`int` resolve in
** a fresh env). The module driver threads `env` left-to-right so each decl's bindings are
** visible to the following decls (trans12.dats:528-556).
**
** TYPE-ANNOTATION GAP (flagged for the architect — M3-REPORT): the M2.5 elaborator DROPS a
** def's param types and return type (pyelab_decl.dats:74 discards `_ret`; param_names_d
** discards each PyParam's type), and PCFundcl carries none. So a top-level `def` lowers
** UNTYPED here (its types are inferred by trans23). The type-lowering machinery
** (pylower_typ/pylower_sres + pyrt Int/Bool aliasing in pylower_staexp.dats) is fully built
** and plugs straight in once PyCore carries the annotations — a wire-format change deferred
** to the architect (it would force rewriting the M2.5 elaborator + every M2.5 golden).
**
** PURELY ADDITIVE; consumes pycore.sats/pyparsing.sats read-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
//
// d1ecl_none0 (the VESTIGIAL first field of D2Cdatatype — trans23's f0_datatype binds but
// never reads it; M5b-spike proven) lives in dynexp1.sats, which libxatsopt.hats does NOT
// pull in (it staloads only staexp2/dynexp2). Staload it here for the datatype lowering.
#staload "./../../srcgen2/SATS/dynexp1.sats"
//
// M7-import (task #34): the SCOPED module-load path needs these — `d0parsed_from_fpath`
// (parsing.sats: parse a `.sats` to L0), `g1exp_make_node`/`G1Eid0` (staexp1.sats: build the
// D2Cstaload `gsrc`), `fpath_make_absolute` (filpath.sats: the D2Cstaload `fpathopt` for the
// LSP dep-graph), and `DLRDT_symbl` (xsymbol.sats: the "$." key a BARE staload registers its
// f2env under — so the module's names resolve by bare-name fall-through, scoped to THIS env).
#staload "./../../srcgen2/SATS/parsing.sats"
#staload "./../../srcgen2/SATS/staexp1.sats"
#staload "./../../srcgen2/SATS/filpath.sats"
#staload "./../../srcgen2/SATS/xsymbol.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pylower.sats"
//
(* ****** ****** *)
//
// ---- datatype (enum) lowering: PCCdata -> D2Cdatatype (M5b.3; SPIKE-PROVEN recipe,
//      LOWERING-MAP §3.3). Mirrors trans12_d1tsc/trans12_d1tcn: register the TYPE first
//      (so a con's own arg types + the matching function resolve it), then build each con
//      as a con-FUNCTION type `(args) -> Self`, wire the cons onto the s2cst + the env.
//
// SCOPE: MONOMORPHIC enums only (the spike's scope) — `tvs` is EMPTY. A parametric enum
// (`enum Tree[A]`, tvs non-empty) needs s2var-bound params during con elaboration; that is
// a clean follow-up (M5b.3b). For THIS slice the monomorphic path is correct and a
// parametric `tvs` does NOT crash (we just build the type without binding the params — it is
// not required to typecheck). See M5b.3b.
//
// lower one data constructor at list index `i`. The con's sexp is ALWAYS a con-function type
// `s2exp_fun1_nil0(npf, argSexps, self)` (nullary -> argSexps = nil -> `() -> Self`; n-ary ->
// the lowered arg types -> `(Args) -> Self`). The name token MUST be T_IDALP — d2con_make_idtp
// derives the name via dconid_sym, which accepts only T_IDALP/T_IDSYM. ctag = list index `i`
// (assigned for CODEGEN; harmless for typecheck).
//
// `tqas` is the con's universal quantifier (M5b.3b): list_nil() for a MONOMORPHIC enum, or
// list_sing(t2qag(loc, s2vs)) for a PARAMETRIC enum (the params are quantified PER-con, in the
// d2con's `tqas` field — NOT inside the con sexp). `self` is the con's result type: the bare
// s2exp_cst(s2c) (monomorphic) or s2exp_apps(s2exp_cst(s2c), [params]) (parametric). The con
// ARG types lower via pylower_typlst either way — a bare param `A` resolves to its in-scope
// s2var through resolve_typ's S2ITMvar arm (no special-casing here).
//
fun
lower_datacon(env: !tr12env, self: s2exp, tqas: t2qaglst, i: int, dc: pcdatacon): d2con =
(
case+ dc of
| PCDataCon(cloc, cname, argtyps) => let
    val argSexps = pylower_typlst(env, argtyps)  // aliases Int -> the_s2exp_sint0, params -> s2var
    val conSexp = s2exp_fun1_nil0((-1)(*npf*), argSexps, self)
    val tok = token_make_node(cloc, T_IDALP(cname))
    val con = d2con_make_idtp(tok, tqas, conSexp)
    val () = d2con_set_ctag(con, i)
  in
    con
  end
)
//
// lower the whole con list, threading the 0-based index. `tqas` is shared by all cons.
fun
lower_dataconlst(env: !tr12env, self: s2exp, tqas: t2qaglst, i: int, dcs: list(pcdatacon)): list(d2con) =
(
case+ dcs of
| list_nil() => list_nil()
| list_cons(dc, rest) =>
    let val con = lower_datacon(env, self, tqas, i, dc)
    in list_cons(con, lower_dataconlst(env, self, tqas, i + 1, rest)) end
)
//
// ---- M5b.3b parametric-generics helpers (SPIKE-PROVEN, LOWERING-MAP §3.3c) ------------------
//
// M5b.6b: map a pcparam's SURFACE sort name (+ @unboxed flag) to its L2 `sort2` (SURFACE-
// GRAMMAR §5.7.1): `Linear` -> the_sort2_vwtp (linear/non-linear viewtype), +@unboxed ->
// the_sort2_vtft (flat viewtype); `Prop` -> the_sort2_prop; `Type` or "" (default) ->
// the_sort2_type, +@unboxed -> the_sort2_tflt (flat type). An UNKNOWN sort name defaults to
// the_sort2_type (a sort typo must not crash — trans23 surfaces a real error if the
// instantiation mismatches). Plain `[A]` (sname="", unboxed=false) -> the_sort2_type, so the
// monomorphic-and-plain-parametric path is BYTE-IDENTICAL to before this slice.
//
// DEP (dependent-type surface, Stages 1–2): the two INDEX sorts (DEP-spike P1/P2-proven, the
// predicative static-arithmetic sorts a `[n: SInt]` / `[b: SBool]` quantifier binds):
//   `SInt`  -> the_sort2_int0   (the int index sort — so `[n: SInt]` is an INDEX param; its
//              s2var is `s2var_make_idst(sym, the_sort2_int0)`, the spike's index-var recipe),
//   `SBool` -> the_sort2_bool   (the bool index sort).
// An index param's s2var (int/bool-sorted) is bound in scope exactly like a type param, so a
// type-app arg `Vec[A, n]` resolves `n` to s2exp_var(<the int s2var>) via resolve_typ's S2ITMvar
// arm. (Static arithmetic `n+1` + guards `{n | n>=0}` are a SEPARATE follow-up — literal +
// variable indices only here.)
#implfun
psort2_of(p) =
(
case+ p of
| PCParam(_, _, sname, unboxed) =>
  (
    // DEP: the index sorts first (a `[n: SInt]` is an INDEX param, not a type param).
    if strn_eq(sname, "SInt")
      then the_sort2_int0
      else if strn_eq(sname, "SBool")
        then the_sort2_bool
    // "Type" OR "" (default) OR any unknown name => the_sort2_type / the_sort2_tflt.
      else if strn_eq(sname, "Linear")
        then (if unboxed then the_sort2_vtft else the_sort2_vwtp)
        else if strn_eq(sname, "Prop")
          then the_sort2_prop
          else (if unboxed then the_sort2_tflt else the_sort2_type)
  )
)
//
// STAT/PROOF parity: map a bare SORT-REFERENCE NAME (a string like `SInt`/`Type`/`Prop`/`SBool`/
// `Linear`) to its L2 sort2 — the SAME vocab psort2_of uses, but keyed on a plain string (sortdef/
// stacst carry a sort-name string, not a pcparam). An UNKNOWN name defaults to the_sort2_type (a
// sort typo must not crash; trans23 surfaces a real error if a use mismatches). Shared by the
// PCCsortdef + PCCstacst lowering arms.
fun
sort2_of_name(sname: strn): sort2 =
(
  if strn_eq(sname, "SInt")
    then the_sort2_int0
    else if strn_eq(sname, "SBool")
      then the_sort2_bool
      else if strn_eq(sname, "Linear")
        then the_sort2_vwtp
        else if strn_eq(sname, "Prop")
          then the_sort2_prop
          else the_sort2_type     // "Type" / "" / any unknown name -> the default type sort
)
//
// STAT/PROOF parity: extract the static s2exp for a `stadef Name = <body>` RHS. v1 supports an INT
// LITERAL body — the elaborated pcexp is a `PCElit(_, PCLint(_, raw))`; we parse the lexeme and emit
// s2exp_int(k) (the SAME index-lit lowering pylower_index_lit uses). Any non-int body (unsupported in
// v1) degrades to s2exp_int(0) — a benign characterized fallback (build_sexpdef still typechecks; a
// real static-expr stadef is a follow-up).
fun
stadef_body_sexp(body: pcexp): s2exp =
(
case+ body of
| PCElit(_, lit) =>
  (
    case+ lit of
    | PCLint(_, raw) => s2exp_int(gint_parse_sint(raw))
    | _ => s2exp_int(0)
  )
| _ => s2exp_int(0)
)
//
// A-QUANT: lower a SUBSET-sort GUARD list (`{a | g1, g2}`) to an s2explst. Each guard is a
// bool-index `pytyp` (a PyTbin comparison); pylower_typ routes it through pylower_index_binop ->
// an s2exp at sort bool — exactly the prop slot S2TEXsub expects (a-quant SX-SUB-proven, the
// f0_sortdef/S1TDFtsub recipe: guards lowered at the_sort2_bool inside the binder scope).
fun
lower_sub_guards(env: !tr12env, guards: list(pytyp)): s2explst =
( case+ guards of
  | list_nil() => list_nil()
  | list_cons(g, rest) => list_cons(pylower_typ(env, g), lower_sub_guards(env, rest)) )
//
// create one s2var per surface type param, in order, AT ITS DECLARED SORT (psort2_of). These
// are BOTH the params bound into scope (so a con arg type / record field `A` resolves to
// s2exp_var) AND the vars the result type is applied to + the con/alias is quantified over.
//
#implfun
mk_param_s2vars(params) =
(
case+ params of
| list_nil() => list_nil()
| list_cons(p, rest) =>
    let
      val+ PCParam(_, name, _, _) = p
      val s2v = s2var_make_idst(symbl_make_name(name), psort2_of(p))
    in list_cons(s2v, mk_param_s2vars(rest)) end
)
//
// push the param s2vars into the current lam-scope so they resolve while we elaborate con arg
// types / record fields (mirrors trans12's f1_s2vs). Caller brackets with pshlam0/poplam0.
//
fun
bind_param_s2vars(env: !tr12env, s2vs: s2varlst): void =
(
case+ s2vs of
| list_nil() => ()
| list_cons(s2v, rest) =>
    let val () = tr12env_add0_s2var(env, s2v) in bind_param_s2vars(env, rest) end
)
//
// M5b.6b: one DECLARED sort per param (the arg-sort list for the type's FUNCTION sort S2Tfun1)
// — psort2_of each param instead of forcing the_sort2_type. A plain `[A]` still yields
// the_sort2_type (byte-identical to before this slice).
//
fun
mk_type_sorts(params: list(pcparam)): sort2lst =
(
case+ params of
| list_nil() => list_nil()
| list_cons(p, rest) => list_cons(psort2_of(p), mk_type_sorts(rest))
)
//
// the list of s2exp_var(s2v) (the type-constructor's params, for s2exp_apps on the result type).
//
fun
param_s2exps(s2vs: s2varlst): s2explst =
(
case+ s2vs of
| list_nil() => list_nil()
| list_cons(s2v, rest) => list_cons(s2exp_var(s2v), param_s2exps(rest))
)
//
(* ****** ****** *)
//
// ---- M5b.6a mode-selection helpers (SPIKE-PROVEN, build-m5b6-spike.sh @ ca3e14377) ---------
//
// the DATATYPE (enum) sort for a mode: boxed/flat -> `the_sort2_tbox`, linear -> `the_sort2_vtbx`.
// PCMflat (@unboxed enum) falls back to BOXED: there is NO stock unboxed-datatype primitive
// (a pinned M5b.6a decision — only RECORDS have a flat representation, TRCDflt0). Threaded into
// BOTH the monomorphic s2cst sort AND the parametric S2Tfun1 result sort.
//
fun
dt_sort_of(m: pcmode): sort2 =
(
case+ m of
| PCMbox()  => the_sort2_tbox
| PCMlin()  => the_sort2_vtbx
| PCMflat() => the_sort2_tbox   // no unboxed-datatype primitive — boxed fallback (pinned).
// DEP (dataprop/dataview): the PROOF/VIEW datatype sorts (DEP-spike P4/P9). The s2cst RESULT sort
// is the_sort2_prop (dataprop) / the_sort2_view (dataview); the con-building + parametric S2Tfun1
// result reuse this so a `dataprop LE[m,n: SInt]` yields `LE : (i0,i0) -> prop`.
| PCMprop() => the_sort2_prop
| PCMview() => the_sort2_view
)
//
// the RECORD (struct) (trcdknd, sort) pair for a mode: boxed -> (TRCDbox0, tbox), linear ->
// (TRCDbox1, vtbx), flat -> (TRCDflt0, tflt). The S2Etrcd `knd` + the alias's own sort.
//
fun
rcd_kind_sort_of(m: pcmode): @(trcdknd, sort2) =
(
case+ m of
| PCMbox()  => @(TRCDbox0, the_sort2_tbox)
| PCMlin()  => @(TRCDbox1, the_sort2_vtbx)
| PCMflat() => @(TRCDflt0, the_sort2_tflt)
// DEP: PCMprop/PCMview are emitted ONLY for a datatype (dataprop/dataview), never for a struct —
// a defensive boxed fallback keeps this match TOTAL (it is unreachable in practice).
| PCMprop() => @(TRCDbox0, the_sort2_tbox)
| PCMview() => @(TRCDbox0, the_sort2_tbox)
)
//
// lower a PyCore record-field list `name: T, ...` to an `l2s2elst` of label/s2exp pairs
// (S2LAB(LABsym(name), <lowered T>)). Each field type goes through pylower_typ, so a primitive
// field (`x: Int`) inherits the M5a resolve_typ mitigation (direct T2Pcst the_s2exp_*0). A bare
// type-param `A` resolves via resolve_typ's S2ITMvar arm when the param s2vars are in scope.
// (Mirrors pylower_tfields in pylower_staexp.dats, over the PyCore pcfield instead of pytfield.)
//
fun
pylower_pcfields(env: !tr12env, fs: list(pcfield)): l2s2elst =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PCField(floc, fname, ftyp), rest) =>
    let
      val lab = LABsym(symbl_make_name(fname))
      val s2e = pylower_typ(env, ftyp)
    in
      list_cons(S2LAB(lab, s2e), pylower_pcfields(env, rest))
    end
)
//
// build the record s2exp for a struct: select the (trcdknd, sort) from the mode, lower the
// fields, and assemble S2Etrcd. Used by BOTH the monomorphic and parametric PCCrecord paths
// (the parametric path calls this with the param s2vars already in scope, then wraps the result
// in s2exp_lam1 before build_sexpdef).
//
fun
build_record_sexp(env: !tr12env, m: pcmode, fields: list(pcfield)): s2exp = let
  val ks = rcd_kind_sort_of(m)
  val knd = ks.0
  val srt = ks.1
  val l2flds = pylower_pcfields(env, fields)
in
  s2exp_make_node(srt, S2Etrcd(knd, (-1)(*npf*), l2flds))
end
//
(* ****** ****** *)
//
// ---- type alias / struct lowering: PCCalias -> D2Csexpdef (M5b.4/.5; SPIKE-PROVEN,
//      LOWERING-MAP §3.3b). A `type X = T` and a `struct S { f: T ... }` (= a record-type
//      alias, §5.7.1) both collapse to ONE mechanism: a static type-definition `s2cst`.
//
// build a `D2Csexpdef` aliasing `name` to the already-lowered RHS s2exp `rhs`, register the
// s2cst in the env (so later USES of the alias resolve + unfold to `rhs`), and return the
// decl. Mirrors f0_sexpdef @ trans12_decl00.dats: the alias inherits the RHS's sort, its
// `sexp` is the RHS, its `styp` the stpize'd (erased) form. `s2exp_stpize` comes from
// statyp2.sats, which libxatsopt.hats already staloads.
fun
build_sexpdef(env: !tr12env, loc: loctn, name: strn, rhs: s2exp): d2ecl = let
  val s2t  = rhs.sort()                 // the alias inherits the RHS's sort
  val tdef = s2exp_stpize(rhs)          // the erased styp form (f0_sexpdef tdef)
  val s2c  = s2cst_make_idst(loc, symbl_make_name(name), s2t)
  val () = s2cst_set_sexp(s2c, rhs)
  val () = s2cst_set_styp(s2c, tdef)
  val () = tr12env_add1_s2cst(env, s2c)
in
  d2ecl_make_node(loc, D2Csexpdef(s2c, rhs))
end
//
(* ****** ****** *)
//
// ---- ABSTRACT TYPES (ATS-parity): PCCabstype -> D2Cabstype, PCCassume -> D2Cabsimpl.
//      SPIKE-PROVEN recipe (frontend/DATS/pyfront_abs_spike.dats; mirrors stock f0_abstype @
//      trans12_decl00.dats:1471 + f0_absimpl @ :1947). The abstract s2cst has NO sexp attached —
//      opacity holds at typecheck (it is a distinct singleton until `assume` gives the rep).
//
// the ABSTYPE sort for a mode: @boxed/none -> the_sort2_tbox (boxed abstract type), @unboxed ->
// the_sort2_tflt (a FLAT abstract type — unlike datatypes, abstract types DO have a flat sort),
// @linear -> DEFERRED, pinned to BOXED tbox in v1 (linearity is erased on the typecheck path —
// the abstract singleton typechecks identically; a code comment records the deferral). The
// monomorphic abstract type's sort; a parametric `abstype Foo[A]` wraps it in a FUNCTION sort.
fun
abs_sort_of(m: pcmode): sort2 =
(
case+ m of
| PCMbox()  => the_sort2_tbox
| PCMflat() => the_sort2_tflt   // a flat abstract type (abstract types DO have a flat repr).
| PCMlin()  => the_sort2_tbox   // @linear abstype DEFERRED -> boxed (linearity erased; v1).
// DEP: PCMprop/PCMview never reach an abstype — a defensive boxed fallback keeps the match TOTAL.
| PCMprop() => the_sort2_tbox
| PCMview() => the_sort2_tbox
)
//
// build a `D2Cabstype` for an OPAQUE type `name`. Mirrors f0_abstype's tail: s2cst_make_idst
// (loc, sym, sort) with NO s2exp attached (the opacity), tr12env_add1_s2cst (register so later
// uses + the `assume` resolve it), D2Cabstype(s2c, A2TDFsome()) (A2TDFsome = a plain abstract
// declaration). A parametric `abstype Foo[A]` gets a FUNCTION sort (type)->...->RESULT (arity N).
fun
build_abstype(env: !tr12env, loc: loctn, name: strn, tvs: list(pcparam), mode: pcmode): d2ecl =
  let
    val s2t =
      if list_nilq(tvs)
        then abs_sort_of(mode)
        else S2Tfun1(mk_type_sorts(tvs), abs_sort_of(mode))
    val s2c = s2cst_make_idst(loc, symbl_make_name(name), s2t)
    val () = tr12env_add1_s2cst(env, s2c)
  in
    d2ecl_make_node(loc, D2Cabstype(s2c, A2TDFsome()))
  end
//
// build a `D2Cabsimpl` for `assume name = T`: SELECT the already-registered abstract s2cst by
// name (mirrors f1_sqid: tr12env_find_s2itm -> S2ITMcst -> head), build a simpl(loc, SIMPLone1
// (s2c)), and attach the concrete representation `rhs`. trans23 inserts the s2c into the env; the
// abstract s2cst still has no sexp at the decl, so opacity holds for code BEFORE the assume.
// If the name does NOT resolve to an s2cst (a forward/typo `assume`), emit a benign no-op (the
// using-decls will errck as unresolved — a graceful failure, never a crash).
fun
build_absimpl(env: !tr12env, loc: loctn, name: strn, rhs: s2exp): d2ecl = let
  val sopt = tr12env_find_s2itm(env, symbl_make_name(name))
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then d2ecl_make_node(loc, D2Cnone0())
          else let
            val s2c  = s2cs.head()
            val simp = simpl_make_node(loc, SIMPLone1(s2c))
            val tok  = token_make_node(loc, T_ABSIMPL())
          in
            d2ecl_make_node(loc, D2Cabsimpl(tok, simp, rhs))
          end
      | _ => d2ecl_make_node(loc, D2Cnone0())
    )
  | ~optn_vt_nil() => d2ecl_make_node(loc, D2Cnone0())
end
//
(* ****** ****** *)
//
// ---- FFI EXTERN SIGNATURE (ATS-parity): PCCextern -> D2Cextern(D2Cdynconst(...)).
//      SPIKE-PROVEN recipe (frontend/DATS/pyfront_abs_spike.dats; mirrors stock trans12_d1cstdcl
//      @ trans12_decl00.dats:4438 + f0_dynconst @ :3479 + D1Cextern @ :845). A BODYLESS function
//      signature is a `d2cst` carrying the function type, REGISTERED so calls resolve. No body.
//
// resolve a (prelude) type NAME to its s2exp — the `void` fallback for an untyped extern
// slot. (resolve_typ in pylower_staexp.dats is file-local; this is the minimal env-lookup it
// needs, the same S2ITMcst-head pattern build_absimpl uses.) An unresolvable name -> s2exp_none0
// (trans23 treats it as an unconstrained tyvar — a benign, characterized degenerate case).
fun
resolve_typ_name(env: !tr12env, name: strn): s2exp = let
  val sopt = tr12env_find_s2itm(env, symbl_make_name(name))
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then s2exp_none0() else s2exp_cst(s2cs.head())
      | S2ITMvar(s2v)  => s2exp_var(s2v)
      | S2ITMenv(_)    => s2exp_none0()
    )
  | ~optn_vt_nil() => s2exp_none0()
end
//
// lower an extern signature's PARAMETER TYPES (parallel name/type lists, M5a-style) to an
// s2explst. A `PyTypSome(T)` param lowers via pylower_typ (a primitive inherits the resolve_typ
// mitigation). A `PyTypNone()` param (untyped — unusual for an FFI sig) defaults to the prelude
// `void` so the signature still typechecks (a benign characterized fallback, not a crash).
fun
extern_argtyps(env: !tr12env, tys: list(pytypopt)): s2explst =
(
case+ tys of
| list_nil() => list_nil()
| list_cons(topt, rest) =>
    let
      val s2e =
        (
        case+ topt of
        | PyTypSome(t) => pylower_typ(env, t)
        | PyTypNone()  => resolve_typ_name(env, "void")
        ): s2exp
    in
      list_cons(s2e, extern_argtyps(env, rest))
    end
)
//
// build a `D2Cextern` wrapping a `D2Cdynconst` whose single d2cst is the bodyless function
// signature `name : (argtyps) -> restyp`. Mirrors the spike: s2exp_fun1_nil0 for the fun type,
// d2cst_make_idtp(tok, dpid, [], sfun), REGISTER via tr12env_add1_d2cst (so a call to `name`
// resolves), d2cstdcl_make_args (no args list / no body — the fun type already lives in the
// d2cst), wrap in D2Cdynconst then D2Cextern. A missing `-> Ret` defaults to `void`.
fun
build_extern
( env: !tr12env, loc: loctn, name: strn
, pnames: list(strn), ptypes: list(pytypopt), ret: pytypopt): d2ecl = let
  val argtyps = extern_argtyps(env, ptypes)
  val restyp =
    (
    case+ ret of
    | PyTypSome(t) => pylower_typ(env, t)
    | PyTypNone()  => resolve_typ_name(env, "void")
    ): s2exp
  val sfun     = s2exp_fun1_nil0((-1)(*npf*), argtyps, restyp)
  val tok_id   = token_make_node(loc, T_IDALP(name))
  val tok_fnk  = token_make_node(loc, T_FUN(FNKfn2))
  val d2c      = d2cst_make_idtp(tok_fnk, tok_id, list_nil()(*tqas*), sfun)
  val () = tr12env_add1_d2cst(env, d2c)              // register so a call to `name` resolves
  val dcdcl    = d2cstdcl_make_args(loc, d2c, list_nil()(*darg*), S2RESnone(), TEQD2EXPnone())
  val dyncst   = d2ecl_make_node(loc, D2Cdynconst(tok_fnk, list_nil()(*tqas*), list_sing(dcdcl)))
  val tok_ext  = token_make_node(loc, T_SRP_EXTERN())
in
  d2ecl_make_node(loc, D2Cextern(tok_ext, dyncst))
end
//
// A-TEMPLATE: collapse the 1-or-2 template decls (extern [+ implement]) into the ONE d2ecl the
// module driver expects per pcdecl. A single decl passes through; two are wrapped in a TRANSPARENT
// `D2Clocal0([], decls)` (empty local-head, both decls in the local-body) — trans23 processes the
// body decls in this env and they stay visible (the template d2cst is already env-registered via
// tr12env_add1_d2cst, so no scoping is lost). A degenerate empty list -> a benign D2Cnone0.
fun
template_decls_as_one(loc: loctn, decls: d2eclist): d2ecl =
( case+ decls of
  | list_nil() => d2ecl_make_node(loc, D2Cnone0())
  | list_cons(d, list_nil()) => d
  | _ => d2ecl_make_node(loc, D2Clocal0(list_nil(), decls)) )
//
(* ****** ****** *)
//
// ---- A-TEMPLATE: PCCtempl -> a TEMPLATE extern (+ optional generic implement). -----------------
//
// SPIKE-PROVEN recipe (frontend/DATS/pyfront_atmpl_spike.dats build_template_id / build_template_foo):
//   * one s2var per `@template[A,B]` binder (the TEMPLATE args) + one per `foo[C,D]` binder (the
//     POLYMORPHIC args), at each param's psort2_of sort (default the_sort2_type — boxed; flat
//     `t@ype` is future unboxed work). All bound in a lam-scope so the param/return types resolve
//     them (`A`/`C` -> s2exp_var via resolve_typ's S2ITMvar arm).
//   * the inner fn type `(args) -> ret`; when POLYMORPHIC params exist, wrap it in
//     `s2exp_uni0(<C,D s2vars>, [], inner)` (the `{C,D}` universal — the half we lower for an
//     ordinary def, here over the bodyless extern's fn type).
//   * the d2cst's `tqas = [ t2qag_make_s2vs(loc, <A,B s2vars>) ]` — a NON-EMPTY tqas makes
//     d2cst_tempq=true (THE template marker). `d2cst_make_idtp(tok_fnk, tok_id, tqas, sfun)`.
//   * register via tr12env_add1_d2cst (so `@impl[…]` + `@inst[…]` attach to the SAME d2cst), wrap in
//     D2Cdynconst(tok_fnk, tqas, [dcdcl]) then D2Cextern.
//
// build the TEMPLATE extern d2ecl + return the d2cst (so the inline-body implement reuses the name).
fun
build_template_extern
( env: !tr12env, loc: loctn
, targs: list(pcparam), name: strn, pargs: list(pcparam)
, pnames: list(strn), ptypes: list(pytypopt), ret: pytypopt ): @(d2ecl, d2cst) = let
  // the TEMPLATE-arg s2vars (the `{A,B}`) + the POLYMORPHIC-arg s2vars (the `{C,D}`).
  val a_s2vs = mk_param_s2vars(targs)
  val c_s2vs = mk_param_s2vars(pargs)
  // bind BOTH groups so the param/return types resolve them.
  val () = tr12env_pshlam0(env)
  val () = bind_param_s2vars(env, a_s2vs)
  val () = bind_param_s2vars(env, c_s2vs)
  val argtyps = extern_argtyps(env, ptypes)
  val restyp =
    (
    case+ ret of
    | PyTypSome(t) => pylower_typ(env, t)
    | PyTypNone()  => resolve_typ_name(env, "void")
    ): s2exp
  val () = tr12env_poplam0(env)
  val inner = s2exp_fun1_nil0((-1)(*npf*), argtyps, restyp)
  // wrap in the {C,D} universal when polymorphic params are present (else the bare fn type).
  val sfun =
    ( if list_nilq(pargs) then inner
      else s2exp_uni0(c_s2vs, list_nil()(*s2ps*), inner) ): s2exp
  // the TEMPLATE quantifier group {A,B} on the d2cst (NON-EMPTY -> d2cst_tempq=true).
  val tqas    = list_sing(t2qag_make_s2vs(loc, a_s2vs)) : t2qaglst
  val tok_id  = token_make_node(loc, T_IDALP(name))
  val tok_fnk = token_make_node(loc, T_FUN(FNKfn2))
  val d2c     = d2cst_make_idtp(tok_fnk, tok_id, tqas, sfun)
  val () = tr12env_add1_d2cst(env, d2c)              // register so @impl/@inst resolve to it
  val dcdcl   = d2cstdcl_make_args(loc, d2c, list_nil()(*darg*), S2RESnone(), TEQD2EXPnone())
  val dyncst  = d2ecl_make_node(loc, D2Cdynconst(tok_fnk, tqas, list_sing(dcdcl)))
  val tok_ext = token_make_node(loc, T_SRP_EXTERN())
  val decl    = d2ecl_make_node(loc, D2Cextern(tok_ext, dyncst))
in
  @(decl, d2c)
end
//
// the SATS `lower_template` entry: build the TEMPLATE extern, then — when an INLINE body is present
// — ALSO emit the GENERIC implement (the body IS the template's generic implementation, like ATS
// `fn{a} foo(x) = e`). The implement is BARE-generic (tias=[]): lower_implement resolves the
// just-registered template d2cst by NAME, builds a fresh impl-side tqas matching its `{A,B}` shape,
// binds the params, lowers the body, and emits D2Cimplmnt0. A BODYLESS template (PCEGNone) yields
// ONLY the extern (declaration-only). The pcexpopt body slot reuses pcexp's PCEGSome/PCEGNone.
// the inline-implement's params are UNANNOTATED (PyTypNone per param) — their types are inferred
// from the (already-registered) template d2cst's function type, exactly like the working separate
// `@impl def pick(x, y)` form. RE-ANNOTATING with the surface `A`/`C` template-binder names would
// resolve them to `s2exp_none0` in the fresh impl-tqas scope (the binder is "a", not "A") and then
// fail to t2pck — so we deliberately DROP the param/return annotations for the inline implement.
fun
none_types(ns: list(strn)): list(pytypopt) =
( case+ ns of
  | list_nil() => list_nil()
  | list_cons(_, rest) => list_cons(PyTypNone(), none_types(rest)) )
//
#implfun
lower_template(env, loc, targs, name, pargs, pnames, ptypes, ret, bodyopt) = let
  val @(decl_ext, _d2c) = build_template_extern(env, loc, targs, name, pargs, pnames, ptypes, ret)
in
  case+ bodyopt of
  | PCEGNone() => list_sing(decl_ext)            // BODYLESS: declaration-only (extern fun{A,B})
  | PCEGSome(body) =>
      // INLINE body: the GENERIC implement (tias=[] — not instantiated; this is the generic body).
      // Params/return are inferred from the d2cst's fn type (untyped here — see none_types above).
      let val decl_impl = lower_implement(env, loc, name, pnames, none_types(pnames), PyTypNone(), body, list_nil()) in
        list_cons(decl_ext, list_sing(decl_impl))
      end
end
//
(* ****** ****** *)
//
// ---- OVERLOAD (ATS-parity, `#symload`): PCCoverload -> D2Csymload + env registration.
//      SPIKE-PROVEN recipe (frontend/DATS/pyfront_surf1_spike.dats case 4; mirrors stock
//      f0_symload @ trans12_decl00.dats:2056-2154):
//        * RESOLVE the IMPL d2itm by name (tr12env_find_d2itm),
//        * wrap it as a `d2ptm = D2PTMsome(0(*pval*), ditm)`,
//        * MERGE with any existing overload bucket under NAME (so multiple `overload NAME with ...`
//          accumulate; a non-sym existing binding is seeded as one impl),
//        * REGISTER `NAME -> D2ITMsym(NAME, dptm::bucket)` via tr12env_add0_d2itm — THE load-bearing
//          step that makes a later use of NAME resolve to IMPL,
//        * emit D2Csymload(tknd, NAME, dptm) (the node is a record for the LSP; resolution is the env
//          binding). An UNRESOLVABLE IMPL -> a benign D2Cnone0 (recovery).
fun
build_overload(env: !tr12env, loc: loctn, name: strn, impl: strn): d2ecl = let
  val sym_nm  = symbl_make_name(name)
  val implopt = tr12env_find_d2itm(env, symbl_make_name(impl))
in
  case+ implopt of
  | ~optn_vt_cons(ditm_impl) => let
      val dptm = D2PTMsome(0(*pval*), ditm_impl)
      // merge with any existing overload bucket under NAME.
      val d2ps =
        (
        case+ tr12env_find_d2itm(env, sym_nm) of
        | ~optn_vt_nil() => list_nil()
        | ~optn_vt_cons(other) =>
          (case+ other of
           | D2ITMsym(_, ps) => ps
           | _ => list_sing(D2PTMsome(0, other)))
        ): list(d2ptm)
      val ditm_nm = D2ITMsym(sym_nm, list_cons(dptm, d2ps))
      val () = tr12env_add0_d2itm(env, sym_nm, ditm_nm)   // *** makes NAME resolve to IMPL ***
      val tknd = token_make_node(loc, T_VAL(VLKval))       // a benign token slot (node is a record)
    in
      d2ecl_make_node(loc, D2Csymload(tknd, sym_nm, dptm))
    end
  | ~optn_vt_nil() => d2ecl_make_node(loc, D2Cnone0())     // unresolvable impl: benign no-op
end
//
(* ****** ****** *)
//
// ---- M7-import (task #34): the SCOPED module load + merge for a USER `import M` / `from M
//      import x`. This REPLICATES the stock `f0_staload` SCOPED path (trans12_decl00.dats:2365-
//      2388) — load the module's d2parsed, build its `f2env`, register it under `$.` (DLRDT_symbl)
//      in THIS file's `env` via `tr12env_add1_f2env` — WITHOUT the GLOBAL pervasive merge that
//      `filpath_pvsload`/`f0_pvsload` (xglobal.dats:799-801, `the_*env_pvsmrgw`) do. The global
//      merge LEAKS across every later file in the resident LSP (the pervasive bug); the scoped
//      `env` merge lives only in this file's tr12env (a fresh `tr12env_make_nil()` per file), so a
//      later file that did NOT import M does NOT see M's names — the no-leak re-entrancy invariant.
//
//      HOW BARE-NAME RESOLUTION WORKS (no extra promotion needed): a bare staload registers the
//      f2env under `$.`; `tr12env_find_d2itm` (trans12_myenv0.dats:1693) falls through to
//      `tr12env_ofind_d2itm` (:2286) which looks up the `$.` S2ITMenv and searches its f2env list
//      via `f2envlst_find_d2itm`. So `lib_double` resolves by BARE name once its module's f2env is
//      under `$.` in THIS env — exactly the spike's resolved case, but scoped.
//
//      We emit a REAL `D2Cstaload` (NOT D2Cnone0) carrying the resolved `fpath` (for the LSP
//      dep-graph `dependency_d3ecl`, which reads `fopt.fnm2()`) + `S2TALOADfenv(fenv)` (trans23's
//      f0_staload maps it to S3TALOADnone for a static load — harmless; the dep edge is in fopt).
//
// `path` is the XATSHOME-RELATIVE `.sats` path (e.g. "/frontend/TEST/m7imp/lib.sats"); we prepend
// `the_XATSHOME()` exactly as `f0_pvsload` does (xglobal.dats:741-748). `knd0`=0 (static `.sats`).
fun
lower_import(env: !tr12env, loc: loctn, path: strn, knd0: sint, is_python: bool): d2ecl =
  if is_python then
    // DEFERRED: a Python-surface `.psats`/`.pdats` module needs recursing OUR frontend (lex/parse/
    // elab/lower) — the stock `d0parsed_from_fpath` only parses ATS surface, so we CANNOT load it
    // here. Emit a benign no-op (NOT a crash). The using-decls that referenced its exports will
    // errck as unresolved names — a graceful, characterized failure. (Python-module import is a
    // clean follow-up: thread OUR pipeline as the loader.)
    d2ecl_make_node(loc, D2Cnone0())
  else let
    // the absolute path: prepend XATSHOME (mirrors f0_pvsload's `strn_append(XATSHOME, fnam)`).
    val abspath = strn_append(the_XATSHOME(), path)
    // (1) LOAD: parse the `.sats` to L0, then trans01 -> L1, then trans12 -> L2 (a d2parsed whose
    //     `t2penv` is the module's D2TOPENV). SAME three steps `f0_pvsload` runs (xglobal.dats:
    //     756-762), but we do NOT call the global `the_*env_pvsmrgw`.
    val dpar0 = d0parsed_from_fpath(knd0, abspath)
    val dpar1 = d1parsed_of_trans01(dpar0)
    val dpar2 = d2parsed_of_trans12(dpar1)
    // (2) build the module's f2env straight from its D2TOPENV (dynexp2.dats:404 `f2env_of_d2parsed`
    //     = F2ENV(lcsrc, g1mac, s2tex, s2itm, d2itm) from `dpar.t2penv()` — the EXACT value the
    //     stock bare-staload path passes to `tr12env_add1_f2env` (trans12_decl00.dats:2374)).
    val fenv = f2env_of_d2parsed(dpar2)
    // (3) SCOPED MERGE: register the f2env under `$.` in THIS file's env (NOT global). After this,
    //     the module's exports resolve by bare name in `env` for all SUBSEQUENT decls.
    val () = tr12env_add1_f2env(env, DLRDT_symbl, fenv)
    // (4) the emitted node: a real D2Cstaload carrying the resolved fpath (LSP dep-graph) + the
    //     f2env. `gsrc` = a minimal G1Eid0(path-as-symbol) src (vestigial for typecheck; the
    //     dep-graph reads `fopt`, not `gsrc`). tknd = a T_STALOAD-ish token is not required by
    //     trans23/tread3a/the LSP reader — they only read knd0/fopt/dopt — so a benign T_VAL token
    //     suffices for the node's `token` slot.
    val tok  = token_make_node(loc, T_VAL(VLKval))
    val gsrc = g1exp_make_node(loc, G1Eid0(symbl_make_name(path)))
    val fpth = fpath_make_absolute(abspath)
    val fopt = optn_cons(fpth) : fpathopt
    val dres = S2TALOADfenv(fenv) : s2taloadopt
  in
    d2ecl_make_node(loc, D2Cstaload(knd0, tok, gsrc, fopt, dres))
  end
//
(* ****** ****** *)
//
#implfun
pylower_decl(env, d) =
(
case+ d of
//
// a top-level (possibly recursive/mutual) def group -> D2Cfundclst. lower_fungroup binds the
// group's names into `env` (visible to later decls + recursive self-calls) BEFORE the bodies.
// DEP (Stages 1–2): a def group carries its §5.7 type/INDEX params `tvs` (`def f[A, n: SInt]`).
// lower_fungroup builds an s2var per param (int-sorted for `[n: SInt]`), binds them while lowering
// the param/return types, and quantifies the D2Cfundclst over them. `tvs = []` => non-generic def.
| PCCfun(loc, tvs, fdcls) => lower_fungroup(env, loc, tvs, fdcls)
//
// a top-level `val p = e` -> D2Cvaldclst (template C: bind the pattern AFTER its RHS).
| PCCval(loc, p, rhs) => let
    val tknd = token_make_node(loc, T_VAL(VLKval))
    val d2p = pylower_pat(env, p)
    val d2rhs = pylower_exp(env, rhs)
    val () = bind_let_styp(d2p, d2rhs)   // M4: fresh tyvar binder (unless RHS is none0); see SATS
    val () = tr12env_add0_d2pat(env, d2p)
    val dval = d2valdcl_make_args(loc, d2p, TEQD2EXPsome(tknd, d2rhs), WTHS2EXPnone())
  in
    d2ecl_make_node(loc, D2Cvaldclst(tknd, list_sing(dval)))
  end
//
// a staload of pyrt -> a no-op. The functional-core E2E references only PRELUDE names, which
// resolve via the env's global fall-through with no explicit staload (probe-verified). A real
// pyrt staload (for flow/iterator names) is wired with the loop lowering in M4/M5.
| PCCstaload(loc, _) => d2ecl_make_node(loc, D2Cnone0())
//
// a USER `import M` / `from M import x` (M7-import, task #34) -> LOAD the module + SCOPED-merge
// its f2env into THIS file's `env` (per-file, NO global leak) + emit a real D2Cstaload (for the
// LSP dep-graph). The module driver threads `env` left-to-right, so an import declared before its
// uses registers FIRST — its exports are then visible to the following decls. See lower_import.
| PCCimport(loc, path, knd0, is_python) => lower_import(env, loc, path, knd0, is_python)
//
// a datatype (enum) -> a real D2Cdatatype (M5b.3; SPIKE-PROVEN, see lower_datacon above).
// (1) create the type s2cst (boxed datatype — the §5.7 default; decorators/sorts are a later
// slice). (2) register the TYPE FIRST so a con's own arg types + the matcher resolve it.
// (3) the type's own s2exp. (4) build the cons (con-function types, ctags = list index).
// (5) wire the cons onto the s2cst + register them in the env. (6) the D2Cdatatype decl — its
// FIRST field is a level-1 d1ecl, VESTIGIAL for typecheck, so d1ecl_none0(loc) is safe.
| PCCdata(loc, name, tvs, dcs, mode) =>
  if list_nilq(tvs) then let
    // ---- MONOMORPHIC enum (tvs empty): the M5b.3 path. M5b.6a: the sort is mode-selected
    //      (boxed tbox by default, linear vtbx for @linear) via dt_sort_of. ----------------
    val s2c = s2cst_make_idst(loc, symbl_make_name(name), dt_sort_of(mode))
    val () = tr12env_add1_s2cst(env, s2c)               // register the TYPE first (recursion)
    val s2e_self = s2exp_cst(s2c)                        // the datatype's own s2exp
    // NB: do NOT name this `cons` — that collides with the prelude list-constructor overload
    // symbol and the args resolve to it instead of the local.
    val d2cs = lower_dataconlst(env, s2e_self, list_nil()(*tqas*), 0, dcs)
    val () = s2cst_set_d2cs(s2c, d2cs)                  // wire cons onto the type
    val () = tr12env_add1_d2conlst(env, d2cs)           // register the cons in the env
  in
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c)))
  end
  else let
    // ---- PARAMETRIC enum (tvs non-empty): M5b.3b, SPIKE-PROVEN (LOWERING-MAP §3.3c). -------
    // (1) one s2var per param; the type's sort is a FUNCTION sort (type)->...->RESULT (arity N).
    //     M5b.6a: the RESULT sort is mode-selected (tbox boxed / vtbx linear) via dt_sort_of.
    val s2vs   = mk_param_s2vars(tvs)
    val s2t    = S2Tfun1(mk_type_sorts(tvs), dt_sort_of(mode))
    val s2c    = s2cst_make_idst(loc, symbl_make_name(name), s2t)
    val () = tr12env_add1_s2cst(env, s2c)               // register the TYPE first (recursion)
    // (2) push a param lam-scope + bind the s2vars BEFORE building the cons (so an arg type `A`
    //     — and a self-recursive arg `Tree[A]` — resolves to its s2var / the registered s2cst).
    val () = tr12env_pshlam0(env)
    val () = bind_param_s2vars(env, s2vs)
    // (3) the con RESULT type is the s2cst APPLIED to the params: `Name(A, B, ...)`.
    val s2e_self = s2exp_apps(loc, s2exp_cst(s2c), param_s2exps(s2vs))
    // (5) the universal quantifier {A,B,...} lives in the d2con's `tqas` field (per-con), shared.
    val tqas = list_sing(t2qag(loc, s2vs)) : t2qaglst
    // (4) con ARG types lower normally (a bare param resolves via resolve_typ's S2ITMvar arm).
    val d2cs = lower_dataconlst(env, s2e_self, tqas, 0, dcs)
    // pop the param scope now that the cons are fully elaborated (mirrors the spike's ordering).
    val () = tr12env_poplam0(env)
    val () = s2cst_set_d2cs(s2c, d2cs)                  // wire cons onto the type
    val () = tr12env_add1_d2conlst(env, d2cs)           // register the cons in the env
  in
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c)))
  end
//
// a plain `type X = T` alias -> a D2Csexpdef (M5b.5; SPIKE-PROVEN, see build_sexpdef above).
// Lower the surface RHS via pylower_typ (a primitive RHS inherits the M5a `resolve_typ`
// mitigation — direct T2Pcst, NOT the prelude sexpdef — so the alias does not crash unify when
// used), then build the sexpdef. (A `struct` now lowers via PCCrecord below, NOT here.)
// Decl-ordering works: the module driver threads `env` left-to-right, so an alias declared
// before its use registers first.
| PCCalias(loc, name, tvs, typ) =>
  if list_nilq(tvs) then let
    // ---- MONOMORPHIC alias (tvs empty): the M5b.5 path, BYTE-IDENTICAL behavior. -----------
    val rhs = pylower_typ(env, typ)
  in
    build_sexpdef(env, loc, name, rhs)
  end
  else let
    // ---- PARAMETRIC alias (tvs non-empty): M5b.3b, SPIKE-PROVEN (LOWERING-MAP §3.3c, P2). ---
    // Build the params as s2vars in a lam-scope, lower the RHS referencing them (a bare param
    // `A` resolves via resolve_typ's S2ITMvar arm), wrap once in s2exp_lam1(s2vs, body).
    // build_sexpdef's rhs.sort() then auto-derives the (type)->...->tbox arrow sort.
    val s2vs = mk_param_s2vars(tvs)
    val () = tr12env_pshlam0(env)
    val () = bind_param_s2vars(env, s2vs)
    val body = pylower_typ(env, typ)
    val () = tr12env_poplam0(env)
    val rhs = s2exp_lam1(s2vs, body)
  in
    build_sexpdef(env, loc, name, rhs)
  end
//
// a `struct` -> a record-type D2Csexpdef carrying its MODE (M5b.6a; SPIKE-PROVEN, see
// build_record_sexp + rcd_kind_sort_of above). The decorator selects the S2Etrcd `trcdknd` +
// the alias's own sort: @boxed/none -> (TRCDbox0, tbox), @linear -> (TRCDbox1, vtbx, linear),
// @unboxed -> (TRCDflt0, tflt, flat). Otherwise SAME shape as the alias path: build the record
// s2exp, then build_sexpdef. Parametric structs wrap the record body in s2exp_lam1 exactly like
// the parametric alias path (the field types reference params via resolve_typ's S2ITMvar arm).
| PCCrecord(loc, name, tvs, fields, mode) =>
  if list_nilq(tvs) then let
    // ---- MONOMORPHIC struct (tvs empty). ---------------------------------------------------
    val rhs = build_record_sexp(env, mode, fields)
  in
    build_sexpdef(env, loc, name, rhs)
  end
  else let
    // ---- PARAMETRIC struct (tvs non-empty): bind the param s2vars while lowering the field
    //      types (a field `A` resolves via resolve_typ's S2ITMvar arm), wrap in s2exp_lam1. ---
    val s2vs = mk_param_s2vars(tvs)
    val () = tr12env_pshlam0(env)
    val () = bind_param_s2vars(env, s2vs)
    val body = build_record_sexp(env, mode, fields)
    val () = tr12env_poplam0(env)
    val rhs = s2exp_lam1(s2vs, body)
  in
    build_sexpdef(env, loc, name, rhs)
  end
//
// EXN: `exception E(T...)` -> a D2Cexcptcon. SPIKE-PROVEN recipe, mirrors the stock
// f0_excptcon (trans12_decl00.dats:3084): the con is a d2con of the BUILT-IN `exn` type
// (the_s2cst_excptn — sort vtbx/linear), its function type `(args) -> exn`. CRITICAL DELTAS
// from a datatype con (lower_datacon): (1) the result type is s2exp_cst(the_s2cst_excptn()),
// NOT a fresh datatype s2cst; (2) the con tag STAYS -1 (f0_excptcon: "tags of d2cs should
// stay (-1)" — an exn con is not a positional datatype variant), so we do NOT call
// d2con_set_ctag. Register the con via tr12env_add1_d2conlst exactly like f0_excptcon so
// `raise E` / `except E` resolve. The decl's first field is a VESTIGIAL d1ecl (trans23
// f0_excptcon binds but never reads it — d1ecl_none0 is safe, same as D2Cdatatype).
| PCCexcept(loc, name, argtyps) => let
    val s2e_exn  = s2exp_cst(the_s2cst_excptn())
    val argSexps = pylower_typlst(env, argtyps)    // aliases Int -> the_s2exp_sint0
    val conSexp  = s2exp_fun1_nil0((-1)(*npf*), argSexps, s2e_exn)
    val tok      = token_make_node(loc, T_IDALP(name))
    val con      = d2con_make_idtp(tok, list_nil()(*tqas*), conSexp)
    val d2cs     = list_sing(con)
    val () = tr12env_add1_d2conlst(env, d2cs)      // register the con (so raise/except resolve)
  in
    d2ecl_make_node(loc, D2Cexcptcon(d1ecl_none0(loc), d2cs))
  end
//
// ATS-parity: an `abstype Name [tvs]` OPAQUE type -> a D2Cabstype (no sexp). build_abstype
// registers the s2cst so later decls (and the `assume`) resolve `Name`. SPIKE-PROVEN.
| PCCabstype(loc, name, tvs, mode) => build_abstype(env, loc, name, tvs, mode)
//
// ATS-parity: an `assume Name = T` representation -> a D2Cabsimpl. build_absimpl selects the
// already-registered abstract s2cst by name + attaches the lowered representation. SPIKE-PROVEN.
| PCCassume(loc, name, typ) => build_absimpl(env, loc, name, pylower_typ(env, typ))
//
// ATS-parity: an `extern def foo(params) -> Ret` FFI bodyless SIGNATURE -> a D2Cextern wrapping
// a D2Cdynconst whose d2cst carries the function type. build_extern REGISTERS the d2cst so a
// call to `foo(...)` resolves against the declared signature. SPIKE-PROVEN.
| PCCextern(loc, name, pnames, ptypes, ret) => build_extern(env, loc, name, pnames, ptypes, ret)
//
// ATS-parity: an `implement NAME(params) -> Ret: body` -> a D2Cimplmnt0. lower_implement (in
// pylower_dynexp, where pl_exp/pl_params_typed are in scope) RESOLVES the pre-declared d2cst by
// name, binds the params, lowers the body, and assembles the node (MONOMORPHIC). SPIKE-PROVEN.
| PCCimplement(loc, name, pnames, ptypes, ret, body, tias) =>
    lower_implement(env, loc, name, pnames, ptypes, ret, body, tias)
//
// A-TEMPLATE: a `@template[A] def foo[C](...) [: body]` -> a TEMPLATE extern (+ optional generic
// implement). lower_template builds the template d2cst (non-empty tqas + s2exp_uni0 poly wrap) and,
// when an inline body is present, ALSO emits the generic implement. It returns a d2eclist (1 or 2
// decls); the module driver expects ONE d2ecl per pcdecl, so we wrap the list in a single
// D2Clocal0(decls, []) node (a transparent local block — trans23 processes its body decls in this
// env; the wrapper carries no scope of its own here). SPIKE-PROVEN.
| PCCtempl(loc, targs, name, pargs, pnames, ptypes, ret, bodyopt) =>
    template_decls_as_one(loc, lower_template(env, loc, targs, name, pargs, pnames, ptypes, ret, bodyopt))
//
// ATS-parity (`#symload`): an `overload NAME with IMPL` -> a D2Csymload + the env registration that
// makes NAME resolve to IMPL (build_overload, via tr12env_add0_d2itm). SPIKE-PROVEN.
| PCCoverload(loc, name, impl) => build_overload(env, loc, name, impl)
//
// ATS-parity: a `sortdef Name = SORT` SORT ALIAS -> a D2Csortdef. SPIKE-PROVEN (dep-spike P6(A)):
// map the RHS sort-reference string to a sort2 (the same SInt/Type/Prop vocab psort2_of uses), wrap
// it in S2TEXsrt, REGISTER the alias under its name via tr12env_add0_s2tex (so a later `[n: Name]`
// resolves it), and emit D2Csortdef(symbl_make_name(name), s2tex).
| PCCsortdef(loc, name, srt) => let
    val s2tx = S2TEXsrt(sort2_of_name(srt))
    val () = tr12env_add0_s2tex(env, symbl_make_name(name), s2tx)
  in
    d2ecl_make_node(loc, D2Csortdef(symbl_make_name(name), s2tx))
  end
//
// A-QUANT: a `@sort type Nat = {a: SInt | a >= 0}` SUBSET (refined) SORT -> a D2Csortdef carrying
// S2TEXsub. SPIKE-PROVEN (a-quant SX-SUB; the exact f0_sortdef/S1TDFtsub recipe @ trans12_decl00:
// 1291): build the binder s2var at its psort2_of carrier sort (mk_param_s2vars on the singleton),
// push a lam-scope + bind it so the guards resolve `a`, lower each guard via pylower_typ (sort
// bool), pop, assemble S2TEXsub(s2v, [guards]), REGISTER the sort under its name (tr12env_add0_s2tex
// — so a later `[n: Nat]` resolves it), and emit D2Csortdef(symbl_make_name(name), s2tex).
| PCCsortsub(loc, name, binder, guards) => let
    val s2vs = mk_param_s2vars(list_sing(binder))
    val s2v1 =
      ( case+ s2vs of
        | list_cons(v, _) => v
        | list_nil() => s2var_make_idst(symbl_make_name(name), the_sort2_int0) )  // defensive
    val () = tr12env_pshlam0(env)
    val () = bind_param_s2vars(env, s2vs)
    val s2ps = lower_sub_guards(env, guards)
    val () = tr12env_poplam0(env)
    val s2tx = S2TEXsub(s2v1, s2ps)
    val () = tr12env_add0_s2tex(env, symbl_make_name(name), s2tx)
  in
    d2ecl_make_node(loc, D2Csortdef(symbl_make_name(name), s2tx))
  end
//
// ATS-parity: a `stacst Name : SORT` STATIC-CONSTANT decl -> a D2Cstacst0. SPIKE-PROVEN (P6(B)):
// build an s2cst at the named sort (s2cst_make_idst), REGISTER it (tr12env_add1_s2cst, so a later
// static expr resolves `Name`), and emit D2Cstacst0(s2c, sort2).
| PCCstacst(loc, name, srt) => let
    val s2t = sort2_of_name(srt)
    val s2c = s2cst_make_idst(loc, symbl_make_name(name), s2t)
    val () = tr12env_add1_s2cst(env, s2c)
  in
    d2ecl_make_node(loc, D2Cstacst0(s2c, s2t))
  end
//
// ATS-parity: a `stadef Name = <static-expr>` STATIC-LEVEL DEFINITION -> a D2Csexpdef. SPIKE-PROVEN
// (P6(C)): lower the static body to an s2exp (v1: an int literal -> s2exp_int) and reuse build_sexpdef
// (the alias mechanism — it sets the s2cst's sexp/styp at the RHS's sort + registers it).
| PCCstadef(loc, name, body) => build_sexpdef(env, loc, name, stadef_body_sexp(body))
//
// ATS-parity: a `prfun NAME(params) -> Ret: body` proof FUNCTION -> a D2Cfundclst with the FNKprfn1
// funkind. lower_prfungroup (pylower_dynexp) reuses the funkind-parameterized fun-group: the proof
// body lowers like a def body; only the funkind token differs (FNKprfn1, dep-spike P5(A)).
| PCCprfun(loc, tvs, fdcl) => lower_prfungroup(env, loc, tvs, list_sing(fdcl))
//
// ATS-parity: a `prval pat [: T] = e` proof VALUE -> a D2Cvaldclst with the VLKprval valkind.
// lower_prval mirrors the PCCval `val` path; only the valkind token differs (VLKprval, P5(B)).
| PCCprval(loc, p, ann, rhs) => lower_prval(env, loc, p, ann, rhs)
//
// ATS-parity: a `praxi NAME(params) -> Ret` proof AXIOM -> a BODYLESS D2Cstatic(D2Cdynconst) with
// the FNKpraxi funkind. lower_praxi is the extern-signature recipe with the proof funkind; the d2cst
// is registered so a `prval pf = NAME(...)` resolves.
| PCCpraxi(loc, name, pnames, ptypes, ret) => lower_praxi(env, loc, name, pnames, ptypes, ret)
//
// an elaboration poison node -> a benign no-op (the diagnostic was already reported by the
// elaborator; M3 surfaces it via the harness's diagnostics dump, never crashes).
| PCCerror(loc, _) => d2ecl_make_node(loc, D2Cnone0())
//
)
//
(* ****** ****** *)
//
// the module driver: lower a PyCore decl list into a d2eclist, threading `env`. Each decl
// lowers (binding its top-level names into `env`) before the next, so forward references
// within a recursive def group resolve (the group binds its names first) and later decls see
// earlier bindings — mirroring trans12's left-to-right decl processing.
//
#implfun
pylower_decls(env, ds) =
(
case+ ds of
| list_nil() => list_nil()
| list_cons(d, rest) =>
    let val d2c = pylower_decl(env, d) in list_cons(d2c, pylower_decls(env, rest)) end
)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pylower_decl00.dats]
*)
