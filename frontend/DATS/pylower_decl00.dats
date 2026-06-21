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
// create one s2var (of sort `type`) per surface type-param name, in order. These are BOTH the
// params bound into scope (so a con arg type / record field `A` resolves to s2exp_var) AND the
// vars the result type is applied to + the con/alias is quantified over.
//
fun
mk_param_s2vars(tvs: list(strn)): s2varlst =
(
case+ tvs of
| list_nil() => list_nil()
| list_cons(tv, rest) =>
    let val s2v = s2var_make_idst(symbl_make_name(tv), the_sort2_type)
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
// one `the_sort2_type` per param (the arg-sort list for the type's FUNCTION sort S2Tfun1).
//
fun
mk_type_sorts(tvs: list(strn)): sort2lst =
(
case+ tvs of
| list_nil() => list_nil()
| list_cons(_, rest) => list_cons(the_sort2_type, mk_type_sorts(rest))
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
#implfun
pylower_decl(env, d) =
(
case+ d of
//
// a top-level (possibly recursive/mutual) def group -> D2Cfundclst. lower_fungroup binds the
// group's names into `env` (visible to later decls + recursive self-calls) BEFORE the bodies.
| PCCfun(loc, fdcls) => lower_fungroup(env, loc, fdcls)
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
// a datatype (enum) -> a real D2Cdatatype (M5b.3; SPIKE-PROVEN, see lower_datacon above).
// (1) create the type s2cst (boxed datatype — the §5.7 default; decorators/sorts are a later
// slice). (2) register the TYPE FIRST so a con's own arg types + the matcher resolve it.
// (3) the type's own s2exp. (4) build the cons (con-function types, ctags = list index).
// (5) wire the cons onto the s2cst + register them in the env. (6) the D2Cdatatype decl — its
// FIRST field is a level-1 d1ecl, VESTIGIAL for typecheck, so d1ecl_none0(loc) is safe.
| PCCdata(loc, name, tvs, dcs, mode) =>
  if list_nilq(tvs) then let
    // ---- MONOMORPHIC enum (tvs empty): the M5b.3 path. M5b.6a: the sort is mode-selected
    //      (boxed tbox by default, linear vtbx for @viewtype) via dt_sort_of. ----------------
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
// the alias's own sort: @boxed/none -> (TRCDbox0, tbox), @viewtype -> (TRCDbox1, vtbx, linear),
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
