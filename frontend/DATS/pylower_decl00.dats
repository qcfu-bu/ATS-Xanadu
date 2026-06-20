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
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pylower.sats"
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
// a datatype -> deferred (M4/M5; constructor types need the dropped type layer too).
| PCCdata(loc, _, _, _) => d2ecl_make_node(loc, D2Cnone0())
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
