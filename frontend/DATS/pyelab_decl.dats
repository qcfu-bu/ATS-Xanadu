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
// extract the bare names of the §5.7 type params (the PyCore datatype layer keeps tvs as
// a plain list(strn); sorts/decorators are recorded in the surface AST and consumed later
// by lowering — M5b.6 wires the memory/representation modes).
fun
typaram_names(tps: list(pytyparam)): list(strn) =
(
case+ tps of
| list_nil() => list_nil()
| list_cons(PyTyParam(_, nm, _, _), rest) => list_cons(nm, typaram_names(rest))
)
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
// M5b.6a: a `struct` field `name: T` (surface pyfield) becomes a PyCore record field `name: T`
// (pcfield). A `struct` lowers to a PCCrecord carrying these RAW fields + its mode (NOT a
// desugared PyTrec alias), so the decorator's S2Etrcd `trcdknd`/sort selection threads through.
fun
field_to_pcfield(f: pyfield): pcfield =
( case+ f of PyField(floc, fname, ftyp) => PCField(floc, fname, ftyp) )
//
fun
fields_to_pcfields(fs: list(pyfield)): list(pcfield) =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(f, rest) => list_cons(field_to_pcfield(f), fields_to_pcfields(rest))
)
//
// M5b.6a: map a §5.7 decorator list to the memory/representation MODE. Decorator NAMES come
// from `@<name>` (`pydecorator = PyDecor of (loctn, strn)`). LAST-WINS: scan left-to-right
// carrying the current verdict; each RECOGNIZED decorator overrides it (so `@boxed @viewtype`
// is linear), an UNRECOGNIZED one is ignored. `viewtype`->PCMlin (linear), `unboxed`->PCMflat
// (flat), `boxed`->PCMbox. The seed (no/only-unknown decorators) is PCMbox (boxed default).
fun
mode_of_decos_go(decos: list(pydecorator), cur: pcmode): pcmode =
(
case+ decos of
| list_nil() => cur
| list_cons(PyDecor(_, nm), rest) =>
    let
      val cur1 =
        if strn_eq(nm, "viewtype") then PCMlin()
        else if strn_eq(nm, "unboxed") then PCMflat()
        else if strn_eq(nm, "boxed") then PCMbox()
        else cur                              // unknown decorator: keep the current verdict
    in
      mode_of_decos_go(rest, cur1)
    end
)
//
fun
mode_of_decos(decos: list(pydecorator)): pcmode = mode_of_decos_go(decos, PCMbox())
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
| PyCfun(loc, nm, _tps, params, ret, body) =>
    let
      // M5a: thread the param types + the return annotation into the PCFundcl (typed def).
      // (typarams `_tps` are still ignored at this layer — unchanged behavior; the field
      //  type changed to list(pytyparam) in §5.7 but the value flow is identical.)
      val fundcl = PCFundcl(loc, nm, param_names_d(params), param_types_d(params),
                            ret, elab_func_body(loc, body), false)
    in
      list_sing(PCCfun(loc, list_sing(fundcl)))
    end
| PyCenum(loc, decos, nm, tps, dcs) =>
    // §5.7 enum → a PyCore datatype. M5b.6a: the decorator selects the memory/representation
    // MODE (@viewtype->linear, @unboxed/none/@boxed->boxed datatype). tvs are the bare names.
    list_sing(PCCdata(loc, nm, typaram_names(tps), elab_datacons(dcs), mode_of_decos(decos)))
| PyCstruct(loc, decos, nm, tps, fields) =>
    // §5.7.1 — a `struct` IS a record-type alias. M5b.6a: emit a PCCrecord carrying the RAW
    // fields + the decorator-selected MODE (@viewtype->linear record, @unboxed->flat record,
    // none/@boxed->boxed record). M3 selects the S2Etrcd trcdknd + alias sort from the mode.
    // tvs are the bare names (parametric structs wrap in s2exp_lam1 at lowering).
    list_sing(PCCrecord(loc, nm, typaram_names(tps), fields_to_pcfields(fields), mode_of_decos(decos)))
| PyCtype(loc, _decos, nm, tps, aliasTyp) =>
    // §5.7 — a `type X = T` alias -> a PCCalias (M5b.5). M3 lowers `T` via pylower_typ and
    // builds the D2Csexpdef. tvs are monomorphic for now (a non-empty list is M5c).
    list_sing(PCCalias(loc, nm, typaram_names(tps), aliasTyp))
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
