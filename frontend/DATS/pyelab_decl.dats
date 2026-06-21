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
// M5b.6b: elaborate the §5.7 type params to PyCore `pcparam`s, each CARRYING its surface
// sort name + an @unboxed flag (so M3 can select the s2var sort, not force the_sort2_type):
//   * name      = the PyTyParam name.
//   * sort name = the `[A: SORT]` annotation if present ("" = none ⇒ default Type).
//   * unboxed   = whether any param decorator is `@unboxed` (`PyDecor(_, "unboxed")`). Only
//                 @unboxed flattens the sort; @boxed/@linear on a PARAM are not meaningful
//                 for the sort selection (they pick a DECL mode, not a param sort) — ignored.
fun
decos_has_unboxed(decos: list(pydecorator)): bool =
(
case+ decos of
| list_nil() => false
| list_cons(PyDecor(_, nm), rest) =>
    if strn_eq(nm, "unboxed") then true else decos_has_unboxed(rest)
)
//
fun
elab_typarams(tps: list(pytyparam)): list(pcparam) =
(
case+ tps of
| list_nil() => list_nil()
| list_cons(PyTyParam(ploc, nm, sortopt, decos), rest) =>
    let
      val sname = (case+ sortopt of PySortSome(_, s) => s | PySortNone() => "")
      val unboxed = decos_has_unboxed(decos)
    in
      list_cons(PCParam(ploc, nm, sname, unboxed), elab_typarams(rest))
    end
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
// carrying the current verdict; each RECOGNIZED decorator overrides it (so `@boxed @linear`
// is linear), an UNRECOGNIZED one is ignored. `linear`->PCMlin (linear), `unboxed`->PCMflat
// (flat), `boxed`->PCMbox. The seed (no/only-unknown decorators) is PCMbox (boxed default).
fun
mode_of_decos_go(decos: list(pydecorator), cur: pcmode): pcmode =
(
case+ decos of
| list_nil() => cur
| list_cons(PyDecor(_, nm), rest) =>
    let
      val cur1 =
        if strn_eq(nm, "linear") then PCMlin()
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
// ---- M7-import (task #34): resolve a dotted module path -> an XATSHOME-relative `.sats` path.
//
// THE v1 RESOLUTION RULE (SIMPLE + documented): a dotted module path `a.b.c` resolves to the
// XATSHOME-relative file path `/a/b/c.sats`. We join the segments with "/", prepend a leading
// "/" (so it is XATSHOME-RELATIVE, exactly the convention `filpath_pvsload`/`f0_pvsload` use —
// they prepend `the_XATSHOME()`), and append ".sats". A v1 import thus always names an ATS
// `.sats` INTERFACE; e.g. `from frontend.TEST.m7imp.lib import lib_double`
//   -> "/frontend/TEST/m7imp/lib.sats".
//
// (No source-relative resolution in v1: the lowering env `tr12env` does not carry the importing
// file's directory, and DATS dirname-string math is fragile — deferred. The XATSHOME-relative
// rule matches the proven spike mechanism exactly.)
//
fun
modpath_join(segs: list(strn)): strn =
(
case+ segs of
| list_nil() => ""
| list_cons(s, list_nil()) => s
| list_cons(s, rest) => strn_append(s, strn_append("/", modpath_join(rest)))
)
//
// resolve segments -> the XATSHOME-relative `.sats` path. ("" segments -> a "/.sats" that will
// fail the load with a clean diagnostic at M3, not a crash.)
fun
modpath_to_sats(segs: list(strn)): strn =
  strn_append("/", strn_append(modpath_join(segs), ".sats"))
//
(* ****** ****** *)
//
// elaborate one surface decl into zero-or-one PyCore decls (a statement decl may produce a
// PCCval; a def -> PCCfun; a type -> PCCdata or nothing for an alias; import -> a PCCimport).
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
      // M7-closures: seed `encl` with the def's OWN params — they are the first enclosing
      // FUNCTION-LOCALS a @func lambda in this body may NOT capture (make_bad(n)'s `n`).
      val fundcl = PCFundcl(loc, nm, param_names_d(params), param_types_d(params),
                            ret, elab_func_body(fc_param_names_pub(list_nil(), params), loc, body), false)
    in
      list_sing(PCCfun(loc, list_sing(fundcl)))
    end
| PyCenum(loc, decos, nm, tps, dcs) =>
    // §5.7 enum → a PyCore datatype. M5b.6a: the decorator selects the memory/representation
    // MODE (@linear->linear, @unboxed/none/@boxed->boxed datatype). tvs are the bare names.
    list_sing(PCCdata(loc, nm, elab_typarams(tps), elab_datacons(dcs), mode_of_decos(decos)))
| PyCstruct(loc, decos, nm, tps, fields) =>
    // §5.7.1 — a `struct` IS a record-type alias. M5b.6a: emit a PCCrecord carrying the RAW
    // fields + the decorator-selected MODE (@linear->linear record, @unboxed->flat record,
    // none/@boxed->boxed record). M3 selects the S2Etrcd trcdknd + alias sort from the mode.
    // tvs are the bare names (parametric structs wrap in s2exp_lam1 at lowering).
    list_sing(PCCrecord(loc, nm, elab_typarams(tps), fields_to_pcfields(fields), mode_of_decos(decos)))
| PyCtype(loc, _decos, nm, tps, aliasTyp) =>
    // §5.7 — a `type X = T` alias -> a PCCalias (M5b.5). M3 lowers `T` via pylower_typ and
    // builds the D2Csexpdef. tvs are monomorphic for now (a non-empty list is M5c).
    list_sing(PCCalias(loc, nm, elab_typarams(tps), aliasTyp))
| PyCabstype(loc, decos, nm, tps) =>
    // ATS-parity: `abstype Name [tvs]` -> a PCCabstype. The decorator selects the memory/repr
    // MODE (@boxed/none->boxed tbox, @unboxed->flat tflt; @linear deferred -> boxed at lowering).
    // No imperative content (opacity is a static fact). M3 builds the OPAQUE s2cst (no sexp).
    list_sing(PCCabstype(loc, nm, elab_typarams(tps), mode_of_decos(decos)))
| PyCassume(loc, nm, repTyp) =>
    // ATS-parity: `assume Name = T` -> a PCCassume carrying the abstract type's NAME + the raw
    // representation surface type. M3 selects the registered abstract s2cst by name + lowers T.
    list_sing(PCCassume(loc, nm, repTyp))
| PyCextern(loc, nm, params, ret) =>
    // ATS-parity: `extern def foo(params) -> Ret` -> a PCCextern carrying the fun NAME, its param
    // names + OPTIONAL types (parallel lists, M5a-style), and the OPTIONAL return type. No body.
    // M3 builds the function type, makes a (registered) d2cst, and emits D2Cextern(D2Cdynconst).
    list_sing(PCCextern(loc, nm, param_names_d(params), param_types_d(params), ret))
| PyCexcept(loc, nm, ts) =>
    // EXN: `exception E(T...)` -> a PCCexcept carrying the con name + raw surface arg types.
    // M3 lowers it to a D2Cexcptcon: a d2con of the built-in `exn` type, registered like a
    // datatype con so `raise E` / `except E` resolve. No imperative content to elaborate.
    list_sing(PCCexcept(loc, nm, ts))
| PyCimplement(loc, nm, params, ret, body) =>
    // ATS-parity: `implement foo(params) -> Ret: <body>` -> a PCCimplement carrying the fun NAME,
    // its param names + OPTIONAL types (parallel lists, M5a-style), the OPTIONAL return type, and
    // the ELABORATED body (a pcexp — the suite folded to a function-epilogue expr EXACTLY like a
    // `def` body, via elab_func_body). M3 resolves the pre-declared d2cst by NAME and emits a
    // D2Cimplmnt0 binding the params + the body (SPIKE-PROVEN, pyfront_surf1_spike.dats case 3).
    list_sing(PCCimplement(loc, nm, param_names_d(params), param_types_d(params), ret,
                           elab_func_body(fc_param_names_pub(list_nil(), params), loc, body)))
| PyCoverload(loc, nm, impl) =>
    // ATS-parity (`#symload`): `overload NAME with IMPL` -> a PCCoverload carrying both bare names.
    // No body / no imperative content. M3 resolves IMPL's d2itm and REGISTERS NAME -> a D2ITMsym
    // bucket so a later use of NAME resolves to IMPL (SPIKE-PROVEN, case 4).
    list_sing(PCCoverload(loc, nm, impl))
| PyCimport(loc, imp) =>
    // M7-import (task #34): a USER `import M` / `from M import x` -> a PCCimport carrying the
    // RESOLVED XATSHOME-relative `.sats` path (v1 rule: dotted `a.b` -> `/a/b.sats`). M3
    // (pylower_decl00) LOADS the module + SCOPED-merges its exports into THIS file's tr12env, so
    // subsequent decls resolve them — per-file, NO global leak. We do NOT yet act on the imported
    // NAMES list of `from M import x, y` (a bare staload promotes the WHOLE module's namespace,
    // which is a sound superset; selective filtering is a follow-up). knd0=0 (STATIC `.sats`).
    // is_python=false: v1 imports an ATS `.sats`; a Python-surface module needs recursing OUR
    // frontend (deferred — see PCCimport doc + the M3 lowering's graceful diagnostic).
    (
      case+ imp of
      | PyImpModule(iloc, segs) =>
          list_sing(PCCimport(iloc, modpath_to_sats(segs), 0(*static*), false(*is_python*)))
      | PyImpFrom(iloc, segs, _star, _names) =>
          list_sing(PCCimport(iloc, modpath_to_sats(segs), 0(*static*), false(*is_python*)))
    )
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
    // M7-closures: at MODULE level `encl = nil` — module-level names are NOT capturable locals,
    // so a @func lambda may freely reference them.
    list_sing(PCCval(loc, elab_pat(p), elab_exp(list_nil(), rhs)))
| PySexpr(loc, e) =>
    list_sing(PCCval(loc, PCPwild(loc), elab_exp(list_nil(), e)))
| _ =>
    // any other module-level statement (while/for/if/...) is elaborated as a one-stmt
    // suite producing a value, bound to a wildcard (a module-init effect).
    let val e = elab_func_body(list_nil(), pystmt_loctn(s), list_sing(s)) in
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
