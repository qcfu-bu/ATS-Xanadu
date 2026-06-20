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
fun
lower_datacon(env: !tr12env, self: s2exp, i: int, dc: pcdatacon): d2con =
(
case+ dc of
| PCDataCon(cloc, cname, argtyps) => let
    val argSexps = pylower_typlst(env, argtyps)  // aliases Int -> the_s2exp_sint0, etc.
    val conSexp = s2exp_fun1_nil0((-1)(*npf*), argSexps, self)
    val tok = token_make_node(cloc, T_IDALP(cname))
    val con = d2con_make_idtp(tok, list_nil()(*tqas*), conSexp)
    val () = d2con_set_ctag(con, i)
  in
    con
  end
)
//
// lower the whole con list, threading the 0-based index.
fun
lower_dataconlst(env: !tr12env, self: s2exp, i: int, dcs: list(pcdatacon)): list(d2con) =
(
case+ dcs of
| list_nil() => list_nil()
| list_cons(dc, rest) =>
    let val con = lower_datacon(env, self, i, dc)
    in list_cons(con, lower_dataconlst(env, self, i + 1, rest)) end
)
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
| PCCdata(loc, name, tvs, dcs) => let
    val s2c = s2cst_make_idst(loc, symbl_make_name(name), the_sort2_tbox)
    val () = tr12env_add1_s2cst(env, s2c)               // register the TYPE first (recursion)
    val s2e_self = s2exp_cst(s2c)                        // the datatype's own s2exp
    // NOTE: monomorphic only — a non-empty `tvs` (parametric enum) is NOT bound here; making
    // `Tree[A]` typecheck needs s2var-bound params during con elaboration (M5b.3b). We still
    // build the type (no crash), but the cons reference `s2e_self` un-applied.
    // NB: do NOT name this `cons` — that collides with the prelude list-constructor overload
    // symbol and the args resolve to it instead of the local.
    val d2cs = lower_dataconlst(env, s2e_self, 0, dcs)
    val () = s2cst_set_d2cs(s2c, d2cs)                  // wire cons onto the type
    val () = tr12env_add1_d2conlst(env, d2cs)           // register the cons in the env
  in
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c)))
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
