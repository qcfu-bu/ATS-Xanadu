(* ****** ****** *)
(*
** M2.5 STEP-0 GATING SPIKE — de-risk LOOP-DESUGARING open item (ii).
**
** The whole control model of the loop/mut elaborator rests on an UNVERIFIED
** assumption: that a TWO-type-parameter parametric datatype
**
**     datatype flow(a:t0, r:t0) = ...
**
** plus a `case` over it (the `flow_bind` monad bind and the loop combinators'
** match arms) TYPE-CHECKS and CODEGENS in this simple-typed surface layer.
** (Open item (ii) asks specifically about the 2-PARAMETER datatype + the case
** over it — the exact §3 `flow` shape.)
**
** This file proves it END-TO-END as a real ATS3-Xanadu surface program:
**   * it DECLARES the 2-parameter `flow(a,r)` datatype (the exact §3 shape),
**   * it DEFINES `flow_bind` (the §3 monad bind) by `case` over `flow`, building
**     the same 2-parameter datatype in each arm,
**   * a driver BUILDS a `flow_next`/`flow_cont`/`flow_break`/`flow_return`, BINDS
**     them with a continuation, MATCHES the result, and PRINTS the observed tags
**     + payloads.
**
** It is fed to `d3parsed_of_fildats` (typecheck) and the M0b xats2js backend
** (codegen -> JS -> node run) by `frontend/DATS/pyfront_spike.dats`. If this file
** type-checks (nerror=0) AND the emitted JS runs and prints the expected tags,
** the 2-parameter `flow` foundation is SOUND and M2.5 proceeds.
**
** SURFACE NOTE (ATS3-Xanadu, verified against srcgen1/prelude/SATS/utpl000.sats):
**   the sort of a boxed type parameter is `t0` (NOT the ATS2 `t@ype`), and a
**   2-parameter parametric datatype is written `datatype D(a0:t0, a1:t0) = ...`
**   (see `utpl02_tx`). The spike is monomorphized over `flow(sint, sint)` so the
**   backend never has to instantiate an uninstantiated template — the question
**   open item (ii) actually asks (the 2-parameter datatype + the case over it) is
**   fully exercised either way.
**
** Self-contained: the only dependency is the stock prelude (prelude_dats.hats),
** so `d3parsed_of_fildats` can compile it exactly like any stock test .dats.
*)
(* ****** ****** *)
//
#include
"./../../srcgen2/prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// Tiny print FFI (defined in frontend/CATS/pyfront_spike.cats). We print via an
// explicit `$extnam` FFI rather than the prelude's `prints` so the emitted program
// is self-contained at run time: the only externals it needs are these three
// functions (implemented in the .cats), NOT the full `prints` print-channel
// machinery (whose `XATS000_strn_print` impl is not in the bare runtime set we
// link to run the emitted JS). This keeps the run namespace-agnostic.
//
#extern fun PYRT_pstr(s: string): void = $extnam()
#extern fun PYRT_pint(n: sint): void = $extnam()
//
(* ****** ****** *)
//
// The §3 control-result datatype. a = the accumulator-tuple type threaded through
// a loop body; r = the enclosing function's return type. TWO type parameters —
// the construct this spike must validate. (Sort `t0` = a boxed/flat type.)
//
datatype
flow(a:t0, r:t0) =
  | flow_next   of (a)   // fell off the end of the suite — normal completion
  | flow_cont   of (a)   // `continue` — go to the innermost loop's next iteration
  | flow_break  of (a)   // `break`    — exit the innermost loop, new state a
  | flow_return of (r)   // `return e` — exit the enclosing function with r
//
(* ****** ****** *)
//
// The §3 monad bind, monomorphized to flow(sint,sint): only `flow_next` continues
// (run the continuation `k`); the three control signals short-circuit (propagate
// unchanged). A `case` over the 2-parameter datatype that RECONSTRUCTS the same
// 2-parameter datatype in each arm — the second thing this spike must validate.
//
fun
flow_bind
( m: flow(sint, sint)
, k: (sint) -> flow(sint, sint)): flow(sint, sint) =
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
// `descr` (label, m) extracts a human-readable tag + the int payload from a
// flow(sint,sint) and prints them — a `case` consumer for the run evidence.
//
fun
descr
(label: string, m: flow(sint, sint)): void =
(
case+ m of
| flow_next(a)   => (PYRT_pstr("  "); PYRT_pstr(label); PYRT_pstr(" => flow_next   "); PYRT_pint(a); PYRT_pstr("\n"))
| flow_cont(a)   => (PYRT_pstr("  "); PYRT_pstr(label); PYRT_pstr(" => flow_cont   "); PYRT_pint(a); PYRT_pstr("\n"))
| flow_break(a)  => (PYRT_pstr("  "); PYRT_pstr(label); PYRT_pstr(" => flow_break  "); PYRT_pint(a); PYRT_pstr("\n"))
| flow_return(r) => (PYRT_pstr("  "); PYRT_pstr(label); PYRT_pstr(" => flow_return "); PYRT_pint(r); PYRT_pstr("\n"))
)
//
(* ****** ****** *)
//
// continuation: "if state < 10, complete normally with state+1; else break".
// This is exactly the kind of body the elaborator splices into a loop.
//
fun
step
(a: sint): flow(sint, sint) =
  if a < 10 then flow_next(a + 1) else flow_break(a)
//
(* ****** ****** *)
//
val () = PYRT_pstr("######## flow-spike (2-param datatype) ########\n")
//
// (1) bind flow_next(0) with `step`  => step(0) => flow_next(1)   [continued]
val r1 = flow_bind(flow_next(0), step)
val () = descr("bind next(0)  step", r1)
//
// (2) bind flow_break(7) with `step` => short-circuits, stays flow_break(7)
val r2 = flow_bind(flow_break(7), step)
val () = descr("bind break(7) step", r2)
//
// (3) bind flow_return(42) with `step` => short-circuits, stays flow_return(42)
val r3 = flow_bind(flow_return(42), step)
val () = descr("bind ret(42)  step", r3)
//
// (4) bind flow_next(10) with `step` => step(10) => flow_break(10)  [body broke]
val r4 = flow_bind(flow_next(10), step)
val () = descr("bind next(10) step", r4)
//
// (5) bind flow_cont(3) with `step` => short-circuits, stays flow_cont(3)
val r5 = flow_bind(flow_cont(3), step)
val () = descr("bind cont(3)  step", r5)
//
val () = PYRT_pstr("######## flow-spike OK ########\n")
//
(* ****** ****** *)
(*
end of [frontend/pyrt/flow_spike.dats]
*)
