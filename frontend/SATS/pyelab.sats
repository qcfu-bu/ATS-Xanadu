(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the elaborator's INTERNAL cross-DATS entries (SATS).
**
** These are NOT part of the M3 contract (that is pycore.sats). They are the shared
** helpers the elaborator DATS use across files (the accumulator-analysis name-set ops,
** declared here so pyelab_util.dats can implement them and pyelab_core.dats / the
** analysis can call them without one giant `and`-group). The PUBLIC entry is
** `pyelab_module` in pycore.sats.
**
** A `nameset` is a deterministically-ordered (declaration-order) list of `mut`/
** accumulator names — NOT a set abstraction, just a small ordered name list with
** membership/add/union/intersect, so the generated accumulator tuple order is stable
** for golden codegen (LOOP-DESUGARING §4).
**
** PURELY ADDITIVE; consumes pycore.sats / pyparsing.sats read-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
//
(* ****** ****** *)
//
#typedef nameset = list(strn)
//
fun nameset_mem(xs: nameset, x: strn): bool
fun nameset_add(xs: nameset, x: strn): nameset
fun nameset_union(xs: nameset, ys: nameset): nameset
fun nameset_inter(xs: nameset, ys: nameset): nameset
//
(* ****** ****** *)
//
// post-pass entries over a produced PyCore decl list (pyelab_diag.dats / pyelab_lint.dats):
//   harvest_decls   : collect every PCEerror/PCCerror poison node's message (recovery).
//   uses_pyrt_decls : does the PyCore reference any pyrt name (drives `staload pyrt`)?
//   lint_decls      : the §6 tail-position lint over every generated loop.
//
fun harvest_decls(ds: list(pcdecl)): list(pcdiag)
fun uses_pyrt_decls(ds: list(pcdecl)): bool
fun lint_decls(ds: list(pcdecl)): list(pcdiag)
//
(* ****** ****** *)
//
// ==================================================================
//  Cross-DATS elaborator entries. These MUST be SATS-declared (not `extern fun` in a
//  DATS): with separate per-file transpilation, only a SATS declaration gives a shared
//  function a STABLE cross-file symbol (the M2 parser split relies on exactly this; an
//  `extern fun` in one DATS would not match the `#impl` in another — the same cross-file
//  stamp-mismatch the M0b backend hit). The DATS implement them with `#implfun`.
//  The elaborator is split:
//    pyelab_core.dats : expression/pattern elaboration, the §4/§3.1 analyses, the §5.1
//                       control-pure fast path, the §5.4 function epilogue, the small
//                       accumulator-tuple builders.
//    pyelab_loop.dats : flow-mode suite elaboration + the §5.2/§5.3 loop combinators.
//    pyelab_decl.dats : the module driver + the public `pyelab_module`.
// ==================================================================
//
// the §3.1 control flags of a suite: @(may_return, may_break, may_continue).
#typedef pcflags = @(bool, bool, bool)
//
// synthesized-binder dummy span (the generated loop name); §9.
fun el_dloc(): loctn
//
// §4 accumulator-set analysis: the reassigned-mut-name set of a suite (stops at inner
// def/lambda; PySreassign to an LIDENT only).
fun assigned_stmts(ss: list(pystmt)): nameset
// §3.1 control flags of a suite (a nested loop consumes its own break/continue).
fun flags_stmts(ss: list(pystmt)): pcflags
//
// expression / pattern elaboration (no control flow except and/or/not -> if, lambda body).
fun elab_exp(e: pyexp): pcexp
fun elab_pat(p: pypat): pcpat
//
// §5.4 function/branch-body epilogue: a suite -> a PyCore expression (control-pure tail
// value, or the flow-mode `case flow_return | flow_next` epilogue).
fun elab_func_body(loc: loctn, body: list(pystmt)): pcexp
//
// a loop-`else` clause (§7.3) elaborated with the enclosing `muts` IN SCOPE (so a
// reassignment to an enclosing mut is a valid SSA rebind, not a false "non-mut" error).
// Returns the else as a control-pure threaded expression ending in unit (its effect).
fun elab_else(loc: loctn, body: list(pystmt), muts: nameset): pcexp
//
// §5.1 control-pure fast path: thread a suite as a chain of immutable lets ending in `tail`.
fun elab_pure(ss: list(pystmt), muts: nameset, tail: pcexp): pcexp
//
// §5 flow-mode suite elaboration: a control-bearing suite -> a `flow`-producing expr.
fun elab_flow(ss: list(pystmt), accs: nameset, muts: nameset): pcexp
//
// accumulator-tuple builders (an N-tuple, or the bare var for N=1, or unit for N=0).
fun accs_tuple_exp(loc: loctn, accs: nameset): pcexp
fun accs_tuple_pat(loc: loctn, accs: nameset): pcpat
//
// reassign-lvalue -> the bare LIDENT name ("" if it is a field/index target, not threaded).
fun lvalue_name(e: pyexp): strn
// add a pattern's LIDENT binders to the mut set.
fun add_pat_names(muts: nameset, p: pypat): nameset
//
// §5.2/§5.3 loop combinators. The `_value` forms (control-pure suite level) splice the
// rest-of-suite `kont` after the loop; the `_flow` forms (control-bearing suite) return a
// `flow`-typed expression the caller flow_binds.
fun elab_while_value
(loc: loctn, cond: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, kont: pcexp): pcexp
fun elab_for_value
(loc: loctn, pat: pypat, iter: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, kont: pcexp): pcexp
fun elab_while_flow
(loc: loctn, cond: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, accs: nameset): pcexp
fun elab_for_flow
(loc: loctn, pat: pypat, iter: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, accs: nameset): pcexp
//
(* ****** ****** *)
(*
end of [frontend/SATS/pyelab.sats]
*)
