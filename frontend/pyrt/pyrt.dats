(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the `pyrt` RUNTIME PRELUDE (ATS surface module).
**
** The frontend-runtime machinery the loop/mut elaborator's desugared output references
** BY NAME (LOOP-DESUGARING §3/§5/§9). PyCore is NOT special-cased for any of this: the
** elaborator emits ordinary con/var references (`flow_next`, `flow_bind`, `iter_open`,
** `list_foldleft`, ...) and a leading `staload pyrt`; M3 resolves them through the
** ordinary `tr12env` fall-through, exactly like any prelude name.
**
** This module is a REAL ATS3-Xanadu surface program: it type-checks (and, as the Step-0
** spike proved for `flow`, codegens + runs) through the stock compiler. It is the single
** source of truth for the runtime contract the desugarer commits to.
**
** Contents:
**   * the §3 `flow(a, r)` datatype + `flow_bind`        (Step-0-proven 2-param datatype)
**   * the iterator protocol `iter`/`iter_open`/`iter_step` (open item (i) — v1 = lists +
**     an integer range; signatures below, flagged for the architect's confirmation)
**   * `list_foldleft`                                   (the §5.3 fast-path fold)
**
** SURFACE NOTE (verified, M2.5 STEP-0): the sort of a boxed type parameter is `t0` (NOT
** the ATS2 `t@ype`); a 2-parameter datatype is `datatype D(a:t0, r:t0) = ...`.
*)
(* ****** ****** *)
//
#include
"./../../srcgen2/prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// ============================ §3 the control-flow result ============================
//
// a = the accumulator-tuple type threaded through a loop body; r = the enclosing
// function's return type. The four control signals of LOOP-DESUGARING §3.
//
datatype
flow(a:t0, r:t0) =
  | flow_next   of (a)   // fell off the end of the suite — normal completion, new state
  | flow_cont   of (a)   // `continue` — go to the innermost loop's next iteration
  | flow_break  of (a)   // `break`    — exit the innermost loop, new state a
  | flow_return of (r)   // `return e` — exit the enclosing function with r
//
// the §3 monad bind: only `flow_next` runs the continuation `k`; the three control
// signals short-circuit (propagate unchanged). Generic over (a, r).
//
fun
<a:t0>
<r:t0>
flow_bind
( m: flow(a, r)
, k: (a) -> flow(a, r)): flow(a, r) =
(
case+ m of
| flow_next(a)   => k(a)
| flow_cont(a)   => flow_cont(a)
| flow_break(a)  => flow_break(a)
| flow_return(r) => flow_return(r)
)
//
(* ****** ****** *)
//
// ============================ the iterator protocol ============================
//
// LOOP-DESUGARING open item (i): the exact `for x in iter` protocol + which containers
// v1 supports. DECISION (v1, FLAGGED FOR CONFIRMATION):
//
//   * an iterator state is a `pyiter(x)` carrying the REMAINING elements of the sequence
//     (a snapshot list); it is THREADED functionally by the loop, never mutated. This
//     keeps the §7.1 capture-by-value semantics and re-entrancy clean (no hidden cell).
//   * `iter_open` materializes a container into a `pyiter(x)`:
//       - a list `list(x)`          -> the list itself (v1 container #1)
//       - an integer range `range`  -> the list [lo, lo+1, ..., hi-1] (v1 container #2)
//     (v1 MINIMUM per the task = lists + an integer range. Strings/dicts/sets are
//     post-v1, additive — each adds one `iter_open` overload, no protocol change.)
//   * `iter_step(it)` returns:
//       - `iter_done()`        when exhausted, or
//       - `iter_more(x, it')`  with the next element `x` and the advanced iterator `it'`.
//     The elaborator's §5.3 loop binds `x` fresh per turn and threads `it'` (so the
//     emitted `for` loop is a pure tail recursion over the iterator state).
//
// NOTE (RESOLVED 2026-06-20, architect ruling i): the elaborator (pyelab_loop.dats,
// `for_iter_loop`) now emits the THREADED form that matches this signature exactly: the
// iterator state `it` is the loop's FIRST parameter (threaded through the accumulator
// tuple), `iter_step(it)` returns `iter_more(x, it')`, and the loop's tail self-call passes
// the advanced `it'` (bound by the `iter_more(x, it')` pattern) — no `var`/`ref` cell, so
// the loop self-call stays in tail position (§6) and the pass is re-entrant. v1 containers:
// lists (it = the list) and `range` (it = the current index, materialized to a list).
//
datatype
iterstep(x:t0) =
  | iter_done of ()
  | iter_more of (x, list(x))   // (next element, remaining)
//
// open a list into an iterator state (v1 container #1).
fun
<x:t0>
iter_open_list(xs: list(x)): list(x) = xs
//
// step a list-backed iterator.
fun
<x:t0>
iter_step_list(it: list(x)): iterstep(x) =
(
case+ it of
| list_nil() => iter_done()
| list_cons(x, rest) => iter_more(x, rest)
)
//
// an integer range [lo, hi) materialized to a list (v1 container #2). The elaborator's
// `for i in range(lo, hi)` lowers `range(lo, hi)` to this, then iterates the list.
fun
range(lo: sint, hi: sint): list(sint) =
  if lo < hi then list_cons(lo, range(lo + 1, hi)) else list_nil()
//
(* ****** ****** *)
//
// ============================ the §5.3 fast-path fold ============================
//
// `list_foldleft(xs, a0, f)` = the left fold a control-pure single-accumulator `for`
// collapses to (LOOP-DESUGARING §5.3 fast path): a = f(...f(f(a0, x0), x1)..., xn-1).
// Argument order matches the elaborator's emitted call
// `list_foldleft(<iter>, <acc0>, lam(acc, x) => <body-state>)`.
//
fun
<x:t0>
<a:t0>
list_foldleft(xs: list(x), a0: a, f: (a, x) -> a): a =
(
case+ xs of
| list_nil() => a0
| list_cons(x, rest) => list_foldleft(rest, f(a0, x), f)
)
//
(* ****** ****** *)
//
// NOTE (M2.5 deliverable scope): the GENERIC definitions above are the runtime CONTRACT
// the desugared PyCore references and the M3 lowering resolves through `tr12env`
// fall-through (LOOP-DESUGARING §9). They TYPE-CHECK cleanly through the stock compiler
// (0 errck). A self-test that explicitly INSTANTIATES the generic `flow_bind`/
// `list_foldleft` at `<sint><sint>` in this same file triggers a stock-`jsemit01`
// backend template-match crash (a generic-template CODEGEN limitation, unrelated to the
// 2-parameter datatype itself — the Step-0 spike proved that end-to-end with a
// MONOMORPHIC `flow_bind`). M2.5 tests the elaborator against the PyCore PRINTER (not
// L2; LOOP-DESUGARING §11), so the contract is validated by type-check here and by the
// Step-0 run; M3 will instantiate these at concrete types in its own emission. The
// monomorphic-`flow` run proof lives in frontend/pyrt/flow_spike.dats (Step-0).
//
(* ****** ****** *)
(*
end of [frontend/pyrt/pyrt.dats]
*)
