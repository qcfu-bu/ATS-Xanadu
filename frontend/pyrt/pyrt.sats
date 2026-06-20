(* ****** ****** *)
(*
** M16 — Python-surface frontend: the `pyrt` RUNTIME PRELUDE *interface* (ATS surface .sats).
**
** WHY A .sats (M16 finding): the loop/list desugaring references pyrt names (`flow_next`,
** `iter_open`, `iter_step`, `list_foldleft`, `range`, ...) BY NAME, and M3 resolves them through
** the ordinary tr12env GLOBAL fall-through after the driver loads pyrt with the stock loader
** (filpath_pvsload -> f0_pvsload: parse -> trans01/trans12 -> merge t2penv into the global env).
** A top-level `fun foo(...) = ...` in a .dats binds a LOCAL function `d2var` (a value with no
** exported type), so a USE from another module resolves to `D2ITMvar` whose type is unknown at
** the call site -> trans23 errcks (D3Et2pck(D3Evar(range);...->...)). The fix is the standard
** ATS .sats/.dats split: a `fun` DECLARATION in a .sats creates a typed `d2cst` CONSTANT (with a
** signature), which resolves as `D2ITMcst` and type-checks at the call site exactly like the
** stock prelude's `strn_append`/`list_cons`. So the desugarer's pyrt names live HERE (the .sats),
** and pyrt.dats provides the implementations.
**
** Contents (the runtime contract the desugared loops commit to — LOOP-DESUGARING §3/§5/§9):
**   * the §3 `flow(a, r)` datatype + `flow_bind`        (the 2-param control-flow result)
**   * the iterator protocol `iterstep`/`iter_open`/`iter_step` (v1 = lists + an integer range)
**   * `list_foldleft`                                   (the §5.3 control-pure fast-path fold)
**
** SURFACE NOTE (verified, M2.5 STEP-0): a boxed type parameter has sort `t0`; a 2-parameter
** datatype is `datatype D(a:t0, r:t0) = ...`. Function templates are `fun<a:t0>...`.
*)
(* ****** ****** *)
//
#include
"./../../srcgen2/prelude/HATS/prelude_sats.hats"
//
(* ****** ****** *)
//
// ============================ §3 the control-flow result ============================
//
// a = the accumulator-tuple type threaded through a loop body; r = the enclosing function's
// return type. The four control signals of LOOP-DESUGARING §3.
//
datatype
flow(a:t0, r:t0) =
  | flow_next   of (a)   // fell off the end of the suite — normal completion, new state
  | flow_cont   of (a)   // `continue` — go to the innermost loop's next iteration
  | flow_break  of (a)   // `break`    — exit the innermost loop, new state a
  | flow_return of (r)   // `return e` — exit the enclosing function with r
//
// the §3 monad bind: only `flow_next` runs the continuation `k`; the three control signals
// short-circuit (propagate unchanged). Generic over (a, r).
//
fun
<a:t0>
<r:t0>
flow_bind(m: flow(a, r), k: (a) -> flow(a, r)): flow(a, r)
//
(* ****** ****** *)
//
// ============================ the iterator protocol ============================
//
// LOOP-DESUGARING open item (i): the `for x in iter` protocol. v1's only container is the list
// (a `for x in <list>`/`range(...)` threads a `list(x)` iterator state, functionally — no cell).
// `iter_step(it)` returns `iter_done()` when exhausted or `iter_more(x, it')` with the next
// element + the advanced iterator. The elaborator (pyelab_loop.dats) emits the BARE names
// `iter_open`/`iter_step` and the `iter_done`/`iter_more` ctors.
//
datatype
iterstep(x:t0) =
  | iter_done of ()
  | iter_more of (x, list(x))   // (next element, remaining)
//
// open a list into an iterator state (v1 container #1) — the elaborator's `iter_open(iter)`.
fun
<x:t0>
iter_open(xs: list(x)): list(x)
//
// step a list-backed iterator — the elaborator's `iter_step(it)`.
fun
<x:t0>
iter_step(it: list(x)): iterstep(x)
//
// an integer range [lo, hi) materialized to a list (v1 container #2). `for i in range(lo, hi)`
// lowers `range(lo, hi)` to this, then iterates the list. MONOMORPHIC (no template params).
fun
range(lo: sint, hi: sint): list(sint)
//
(* ****** ****** *)
//
// ============================ the §5.3 fast-path fold ============================
//
// `list_foldleft(xs, a0, f)` = the left fold a control-pure single-accumulator `for` collapses
// to (LOOP-DESUGARING §5.3): a = f(...f(f(a0, x0), x1)..., xn-1). Argument order matches the
// elaborator's emitted call `list_foldleft(<iter>, <acc0>, lam(acc, x) => <body-state>)`.
//
fun
<x:t0>
<a:t0>
list_foldleft(xs: list(x), a0: a, f: (a, x) -> a): a
//
(* ****** ****** *)
(*
end of [frontend/pyrt/pyrt.sats]
*)
