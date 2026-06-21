(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the §6 TAIL-POSITION LINT (DATS).
**
** LOOP-DESUGARING §6 is the LOAD-BEARING invariant: the backend compiles a recursive
** function to a real `while` loop IFF its self-call is a TAIL call (d2var_tailq). So
** every generated `loop` MUST have its self-call(s) in tail position, or a desugared
** loop becomes a growing-stack recursion. This lint asserts the invariant at ELABORATION
** time so a regression fails the build, not a run.
**
** For each `PCFundcl` with `isloop = true`, walk its body with a `tail: bool` flag and
** assert every application of the loop NAME ("loop") occurs only in TAIL position. A
** loop-name application found in non-tail position -> a diagnostic (the build script
** treats any TAIL-LINT VIOLATION diagnostic as a hard FAIL).
**
** Structure: each walk is one `fun ... and ...` group + a thin `#implfun` wrapper.
**
** PURELY ADDITIVE; consumes pycore.sats read-only.
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
#define LOOPNAME "loop"
//
fun b_and(a: bool, b: bool): bool = if a then b else false
//
// is this expression `loop(...)` (an application whose head is the loop var)?
fun
is_loop_call(e: pcexp): bool =
(
case+ e of
| PCEapp(_, hd, _) =>
    (case+ hd of PCEvar(_, nm) => strn_eq(nm, LOOPNAME) | _ => false)
| _ => false
)
//
// does a fun group bind a member named "loop" (i.e. open a fresh inner loop scope)?
fun
binds_loop(fs: list(pcfundcl)): bool =
(
case+ fs of
| list_nil() => false
| list_cons(PCFundcl(_, nm, _, _, _, _, _), rest) =>
    if strn_eq(nm, LOOPNAME) then true else binds_loop(rest)
)
//
(* ****** ****** *)
//
// ---- tail-position walk of a single loop body ------------------------------
//
// `tail` = are we in a tail position of the enclosing loop body? Tail rules: if-branches
// tail (cond not); case-arm bodies tail (scrut not); let-body tail (rhs not); seq-second
// tail (first not); app args/head NOT tail; everything else NOT tail.
//
fun
lint_exp(e: pcexp, tail: bool, acc: list(pcdiag)): list(pcdiag) =
(
case+ e of
| PCEapp(loc, hd, args) =>
    let
      val viol = b_and(is_loop_call(e), ~tail)
      val acc1 =
        if viol
          then list_append(acc, list_sing(PCDiag(loc,
                 "TAIL-LINT VIOLATION: generated loop self-call not in tail position")))
          else acc
      val acc2 = lint_exp(hd, false, acc1)
    in
      lint_explst_nt(args, acc2)
    end
| PCEif(_, c, t, f) =>
    let val a1 = lint_exp(c, false, acc)
        val a2 = lint_exp(t, tail, a1)
    in lint_exp(f, tail, a2) end
| PCEcase(_, scrut, arms) => lint_arms(arms, tail, lint_exp(scrut, false, acc))
| PCElet(_, _, _, rhs, body) => lint_exp(body, tail, lint_exp(rhs, false, acc))
// a var cell: the init is NOT tail; the body inherits the enclosing tail context (the cell
// scopes the rest exactly like a `let`). A cell assignment is void-valued — neither side tail.
| PCEvarcell(_, _, _, init, body) => lint_exp(body, tail, lint_exp(init, false, acc))
| PCEassign(_, lv, rv) => lint_exp(rv, false, lint_exp(lv, false, acc))
// a nested `Eletfun` that REBINDS the name `loop` (every generated loop is named
// "loop") opens a fresh `loop` scope: inside BOTH its members AND its body, `loop`
// refers to the INNER loop, governed by its OWN tail-lint (driven from
// lint_loops_fundcls). So STOP the current loop's tail-walk at such a node entirely —
// else we'd mis-flag the inner loop's legitimate tail self-calls (and its non-tail
// outer-dispatch `case loop(...)`) as THIS (outer) loop's violations. (M2.5 §6.)
// A nested `Eletfun` that does NOT bind `loop` (a surface local def group) is walked
// normally: members are separate scopes (non-tail), the body stays in tail context.
| PCEletfun(_, fs, body) =>
    if binds_loop(fs)
      then acc
      else lint_exp(body, tail, acc)
| PCEseq(_, e1, e2) => lint_exp(e2, tail, lint_exp(e1, false, acc))
| PCElam(_, _, _, _, body) => lint_exp(body, false, acc)
| PCEtup(_, es) => lint_explst_nt(es, acc)
| PCErec(_, fs) => lint_efields_nt(fs, acc)
| PCElist(_, es) => lint_explst_nt(es, acc)
| PCEfield(_, e1, _) => lint_exp(e1, false, acc)
// EXN: the raised sub-expr is NOT tail. A try's body + each handler body ARE in the try's
// tail position (the try is value-valued, like a case) — walk them with the inherited `tail`.
| PCEraise(_, e1) => lint_exp(e1, false, acc)
| PCEtry(_, body, hs) => lint_arms(hs, tail, lint_exp(body, tail, acc))
| PCElit(_, _) => acc
| PCEvar(_, _) => acc
| PCEcon(_, _) => acc
| PCEunit(_) => acc
| PCEerror(_, _) => acc
)
//
and
lint_explst_nt(es: list(pcexp), acc: list(pcdiag)): list(pcdiag) =
(
case+ es of
| list_nil() => acc
| list_cons(e, rest) => lint_explst_nt(rest, lint_exp(e, false, acc))
)
//
and
lint_efields_nt(fs: list(pcefield), acc: list(pcdiag)): list(pcdiag) =
(
case+ fs of
| list_nil() => acc
| list_cons(PCEField(_, _, e), rest) => lint_efields_nt(rest, lint_exp(e, false, acc))
)
//
and
lint_arms(arms: list(pcarm), tail: bool, acc: list(pcdiag)): list(pcdiag) =
(
case+ arms of
| list_nil() => acc
| list_cons(PCArm(_, _, gopt, body), rest) =>
    // the guard is in scrutinee position (NOT tail); the arm body is tail iff the case is.
    let val acc1 = lint_gopt(gopt, acc)
    in lint_arms(rest, tail, lint_exp(body, tail, acc1)) end
)
//
and
lint_gopt(gopt: pcexpopt, acc: list(pcdiag)): list(pcdiag) =
( case+ gopt of PCEGNone() => acc | PCEGSome(g) => lint_exp(g, false, acc) )
//
(* ****** ****** *)
//
// ---- find every generated loop + lint its body (whole-tree walk) -----------
//
fun
lint_loops_exp(e: pcexp, acc: list(pcdiag)): list(pcdiag) =
(
case+ e of
| PCEletfun(_, fs, body) => lint_loops_exp(body, lint_loops_fundcls(fs, acc))
| PCEapp(_, hd, args) => lint_loops_explst(args, lint_loops_exp(hd, acc))
| PCElam(_, _, _, _, body) => lint_loops_exp(body, acc)
| PCElet(_, _, _, rhs, body) => lint_loops_exp(body, lint_loops_exp(rhs, acc))
// a var cell scopes its body — a generated loop nested inside (the var-in-loop case) MUST
// be reached by the loop-lint, so recurse into BOTH the init and the body.
| PCEvarcell(_, _, _, init, body) => lint_loops_exp(body, lint_loops_exp(init, acc))
| PCEassign(_, lv, rv) => lint_loops_exp(rv, lint_loops_exp(lv, acc))
| PCEif(_, c, t, f) => lint_loops_exp(f, lint_loops_exp(t, lint_loops_exp(c, acc)))
| PCEcase(_, scrut, arms) => lint_loops_arms(arms, lint_loops_exp(scrut, acc))
| PCEtup(_, es) => lint_loops_explst(es, acc)
| PCErec(_, fs) => lint_loops_efields(fs, acc)
| PCElist(_, es) => lint_loops_explst(es, acc)
| PCEfield(_, e1, _) => lint_loops_exp(e1, acc)
| PCEseq(_, e1, e2) => lint_loops_exp(e2, lint_loops_exp(e1, acc))
// EXN: recurse into raise/try so a generated loop nested in a try body/handler is still
// tail-walked from its own loop-binding fundcl (lint_loops_fundcls drives lint_exp there).
| PCEraise(_, e1) => lint_loops_exp(e1, acc)
| PCEtry(_, body, hs) => lint_loops_arms(hs, lint_loops_exp(body, acc))
| _ => acc
)
//
and
lint_loops_fundcls(fs: list(pcfundcl), acc: list(pcdiag)): list(pcdiag) =
(
case+ fs of
| list_nil() => acc
| list_cons(PCFundcl(_, _, _, _, _, body, isloop), rest) =>
    let
      val acc1 = if isloop then lint_exp(body, true, acc) else acc
      val acc2 = lint_loops_exp(body, acc1)
    in
      lint_loops_fundcls(rest, acc2)
    end
)
//
and
lint_loops_explst(es: list(pcexp), acc: list(pcdiag)): list(pcdiag) =
(
case+ es of
| list_nil() => acc
| list_cons(e, rest) => lint_loops_explst(rest, lint_loops_exp(e, acc))
)
//
and
lint_loops_efields(fs: list(pcefield), acc: list(pcdiag)): list(pcdiag) =
(
case+ fs of
| list_nil() => acc
| list_cons(PCEField(_, _, e), rest) => lint_loops_efields(rest, lint_loops_exp(e, acc))
)
//
and
lint_loops_arms(arms: list(pcarm), acc: list(pcdiag)): list(pcdiag) =
(
case+ arms of
| list_nil() => acc
| list_cons(PCArm(_, _, gopt, body), rest) =>
    let val acc1 = (case+ gopt of PCEGNone() => acc | PCEGSome(g) => lint_loops_exp(g, acc))
    in lint_loops_arms(rest, lint_loops_exp(body, acc1)) end
)
//
fun
lint_decl(d: pcdecl, acc: list(pcdiag)): list(pcdiag) =
(
case+ d of
| PCCfun(_, _, fs) => lint_loops_fundcls(fs, acc)
| PCCval(_, _, e) => lint_loops_exp(e, acc)
| PCCimplement(_, _, _, _, _, body) => lint_loops_exp(body, acc) // an implement body is a fun body — lint its loops.
| _ => acc
)
//
fun
lint_decls_go(ds: list(pcdecl), acc: list(pcdiag)): list(pcdiag) =
(
case+ ds of
| list_nil() => acc
| list_cons(d, rest) => lint_decls_go(rest, lint_decl(d, acc))
)
//
(* ****** ****** *)
//
#implfun lint_decls(ds) = lint_decls_go(ds, list_nil())
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_lint.dats]
*)
