(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the MODULE/DECL elaborator + driver (DATS).
**
** Walks a parsed `pymodule`'s decls into a `pcmodule`:
**   * `def`        -> a PCCfun group whose member body is the §5.4 function epilogue.
**   * `type ... =` -> a PCCdata (datatype) carried through (no imperative content).
**   * a module-level statement -> a PCCval (binding) or effect, elaborated as a suite.
**   * EMITS a leading `staload pyrt` iff the elaborated module references the flow /
**     iterator / fold machinery (LOOP-DESUGARING §9): we detect this by scanning the
**     produced PyCore for any pyrt con/var name.
**
** Also runs:
**   * the §6 TAIL-POSITION LINT (pyelab_lint.dats) over every generated `loop`, emitting
**     a diagnostic (and a hard FAIL marker the harness/build script keys on) if a loop's
**     self-call is NOT in tail position.
**   * the DIAGNOSTIC HARVEST (pyelab_diag.dats): collect every PCEerror/PCCerror poison
**     node's message into the module's pcdiaglst, alongside the carried-over parse diags.
**
** PURE / re-entrant: takes a pymodule, returns a fresh pcmodule; no global state.
**
** PURELY ADDITIVE; consumes pyparsing.sats / pycore.sats / pyelab.sats read-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
//
(* ****** ****** *)
//
// el_dloc / elab_func_body / elab_pure / elab_pat / elab_exp / harvest_decls /
// lint_decls / uses_pyrt_decls all come from pyelab.sats (staloaded above).
//
(* ****** ****** *)
//
fun
param_names_d(ps0: list(pyparam)): list(strn) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(PyParam(_, nm, _), rest) => list_cons(nm, param_names_d(rest))
)
//
// M5a: the parallel param-type list for a top-level `def` (each param's optional annotation).
fun
param_types_d(ps0: list(pyparam)): list(pytypopt) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(PyParam(_, _, topt), rest) => list_cons(topt, param_types_d(rest))
)
//
fun
tvars_of(ts: list(strn)): list(strn) = ts
//
// elaborate a surface datatype RHS to PyCore data constructors.
fun
elab_datacons(dcs: list(pydatacon)): list(pcdatacon) =
(
case+ dcs of
| list_nil() => list_nil()
| list_cons(PyDataCon(loc, nm, ts), rest) =>
    list_cons(PCDataCon(loc, nm, ts), elab_datacons(rest))
)
//
(* ****** ****** *)
//
// elaborate one surface decl into zero-or-one PyCore decls (a statement decl may produce a
// PCCval; a def -> PCCfun; a type -> PCCdata or nothing for an alias; import -> nothing in v1).
//
fun
elab_decl(d: pydecl): list(pcdecl) =
(
case+ d of
| PyCfun(loc, nm, tvs, params, ret, body) =>
    let
      // M5a: thread the param types + the return annotation into the PCFundcl (typed def).
      val fundcl = PCFundcl(loc, nm, param_names_d(params), param_types_d(params),
                            ret, elab_func_body(loc, body), false)
    in
      list_sing(PCCfun(loc, list_sing(fundcl)))
    end
| PyCtype(loc, nm, tvs, tdef) =>
    (case+ tdef of
     | PyTDdata(_, dcs) => list_sing(PCCdata(loc, nm, tvs, elab_datacons(dcs)))
     | PyTDalias(_, _) => list_nil())  // type alias: M3 handles; no PyCore datatype node (v1).
| PyCimport(loc, _) => list_nil()      // imports resolved by M3 staloads (v1).
| PyCstmt(loc, s) => elab_module_stmt(s)
| PyCerror(loc, msg) => list_sing(PCCerror(loc, msg))
)
//
// a module-level statement -> a top-level binding / effect. A `let p = e` -> PCCval;
// a bare expr -> PCCval with a wildcard pattern (effect). A module-level while/for/if is
// elaborated as a suite producing a unit value (rare; kept correct).
and
elab_module_stmt(s: pystmt): list(pcdecl) =
(
case+ s of
| PyDlet(loc, _ismut, p, _ann, rhs) =>
    list_sing(PCCval(loc, elab_pat(p), elab_exp(rhs)))
| PySexpr(loc, e) =>
    list_sing(PCCval(loc, PCPwild(loc), elab_exp(e)))
| _ =>
    // any other module-level statement (while/for/if/...) is elaborated as a one-stmt
    // suite producing a value, bound to a wildcard (a module-init effect).
    let val e = elab_func_body(pystmt_loctn(s), list_sing(s)) in
      list_sing(PCCval(pystmt_loctn(s), PCPwild(pystmt_loctn(s)), e))
    end
)
//
fun
elab_decls(ds: list(pydecl)): list(pcdecl) =
(
case+ ds of
| list_nil() => list_nil()
| list_cons(d, rest) => list_append(elab_decl(d), elab_decls(rest))
)
//
(* ****** ****** *)
//
// carry the parse diagnostics over (the §11 harness shows BOTH parse + elaboration diags).
fun
parse_diags(diags: list(pydiag)): list(pcdiag) =
(
case+ diags of
| list_nil() => list_nil()
| list_cons(PyDiag(loc, msg), rest) =>
    list_cons(PCDiag(loc, strn_append("parse: ", msg)), parse_diags(rest))
)
//
(* ****** ****** *)
//
// ---- the public entry -------------------------------------------------------
//
#implfun
pyelab_module(m) = let
  val+ PyModule(decls, pdiags) = m
  val core0 = elab_decls(decls)
  // prepend a `staload pyrt` iff the core uses the pyrt machinery (§9).
  val core =
    if uses_pyrt_decls(core0)
      then list_cons(PCCstaload(el_dloc(), "pyrt"), core0)
      else core0
  // diagnostics = parse diags ++ elaboration poison-node messages ++ tail-lint violations.
  val ediags = harvest_decls(core)
  val ldiags = lint_decls(core)
  val alldiags = list_append(parse_diags(pdiags), list_append(ediags, ldiags))
in
  PCModule(core, alldiags)
end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_decl.dats]
*)
