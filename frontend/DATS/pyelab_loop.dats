(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: FLOW-MODE elaboration + the LOOP COMBINATORS (DATS).
**
** The control-bearing half of the elaborator (LOOP-DESUGARING §5.2/§5.3 + the §3 flow
** monad). Implements the SATS entries elab_flow / elab_while_value / elab_for_value /
** elab_while_flow / elab_for_flow as thin `#implfun` wrappers over plain `fun` workers
** (M2 Δ3: no `#implfun` may head a `fun ... and ...` group with non-impl helpers).
**
** The generated `loop` self-call is ALWAYS the tail of a `case`/`if` arm (never wrapped in
** a flow_bind continuation or an argument) so the §6 tail-position invariant holds;
** pyelab_lint.dats asserts it before M3.
**
** PURELY ADDITIVE; consumes pyparsing.sats / pycore.sats / pyelab.sats read-only. The
** cross-DATS elaborator helpers (el_dloc, elab_exp, elab_pat, elab_func_body, elab_pure,
** assigned_stmts, flags_stmts, accs_tuple_exp/pat, lvalue_name, add_pat_names) come from
** pyelab.sats (defined in pyelab_core.dats).
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
fun b_or(a: bool, b: bool): bool = if a then true else b
fun b_and(a: bool, b: bool): bool = if a then b else false
//
fun control_any(fl: pcflags): bool = b_or(fl.0, b_or(fl.1, fl.2))
//
fun
flow_app(loc: loctn, tag: strn, arg: pcexp): pcexp =
  PCEapp(loc, PCEcon(loc, tag), list_sing(arg))
//
fun
loop_call(loc: loctn, accs: nameset): pcexp =
  PCEapp(loc, PCEvar(el_dloc(), LOOPNAME), list_sing(accs_tuple_exp(loc, accs)))
//
// ---- THREADED-iterator helpers (architect ruling i) -------------------------
//
// The iterator state `it` is THREADED through the loop's accumulator tuple: the loop
// parameter is `(it, <accs>)` and the self-call passes `(it1, <accs'>)` where `it1` is the
// advanced iterator pattern-bound from `iter_more(x, it1)`. There is NO `var`/`ref` cell —
// `it` is an ordinary immutable value carried as a tail-call argument (preserves §6 and
// keeps the pass re-entrant). v1 containers: lists (it = the list) and `range` (it = the
// current index), both threaded by the `iterstep`/`iter_step` protocol in pyrt.
//
#define ITNAME  "it"   // the current iterator state (the loop's first parameter)
#define ITNEXT  "it1"  // the advanced iterator state (bound by iter_more's it' field)
//
// the loop's parameter nameset: the iterator state PREPENDED to the user accumulators.
fun
it_params(accs: nameset): nameset = list_cons(ITNAME, accs)
//
// accs -> a list of `(Evar nm)` (for splicing into the it-prefixed tuple).
fun
accs_var_exps(loc: loctn, accs: nameset): list(pcexp) =
(
case+ accs of
| list_nil() => list_nil()
| list_cons(nm, rest) => list_cons(PCEvar(loc, nm), accs_var_exps(loc, rest))
)
//
// a self-call `loop((it1, accs'))` — the advanced iterator `it1` threads in TAIL position.
fun
loop_call_it(loc: loctn, accs: nameset): pcexp =
  PCEapp(loc, PCEvar(el_dloc(), LOOPNAME),
         list_sing(accs_tuple_exp(loc, list_cons(ITNEXT, accs))))
//
// the initial call `loop((iter_open(iter), accs0))`. Match accs_tuple_exp's single-vs-tuple
// convention on the (it :: accs) shape: a bare `it` slot (accs empty) is passed un-tupled,
// otherwise an it-prefixed tuple — so the call shape matches the loop parameter shape.
fun
loop_call_init(loc: loctn, openexp: pcexp, accs: nameset): pcexp =
let
  val itarg =
    (case+ accs of
     | list_nil() => openexp
     | list_cons(_, _) => PCEtup(loc, list_cons(openexp, accs_var_exps(loc, accs))))
in
  PCEapp(loc, PCEvar(el_dloc(), LOOPNAME), list_sing(itarg))
end
//
fun
mk_arm_con(tag: strn, accs: nameset, rhs: pcexp): pcarm =
  PCArm(el_dloc(), PCPcon(el_dloc(), tag, list_nil()(*sargs*), list_sing(accs_tuple_pat(el_dloc(), accs))), PCEGNone(), rhs)
//
fun
mk_arm_ret(rhs: pcexp): pcarm =
  PCArm(el_dloc(), PCPcon(el_dloc(), "flow_return", list_nil()(*sargs*), list_sing(PCPvar(el_dloc(), "r"))), PCEGNone(), rhs)
//
fun
param_names_l(ps0: list(pyparam)): list(strn) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(PyParam(_, nm, _), rest) => list_cons(nm, param_names_l(rest))
)
//
// M5a: the parallel param-type list for a nested `def` (PySdecl), mirroring el_param_types.
fun
param_types_l(ps0: list(pyparam)): list(pytypopt) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(PyParam(_, _, topt), rest) => list_cons(topt, param_types_l(rest))
)
//
// M5a: a parallel `list(pytypopt)` of all-`PyTypNone()`, one per name (untyped loop params).
fun
none_types(xs: nameset): list(pytypopt) =
(
case+ xs of
| list_nil() => list_nil()
| list_cons(_, rest) => list_cons(PyTypNone(), none_types(rest))
)
//
fun
assigned_else_w(els: pystmtlstopt): nameset =
  (case+ els of PyElseNone() => list_nil() | PyElseSome(b) => assigned_stmts(b))
//
(* ****** ****** *)
//
// ---- flow-mode suite elaboration (mutually recursive worker group) ----------
//
// M7-closures: `encl` carries the enclosing function-locals visible at this flow-mode suite
// (a def/lambda's params + body lets) so a @func lambda anywhere in here is capture-checked.
fun
fl_suite(encl: nameset, ss: list(pystmt), accs: nameset, muts: nameset, mts: muttypes): pcexp =
(
case+ ss of
| list_nil() => flow_app(el_dloc(), "flow_next", accs_tuple_exp(el_dloc(), accs))
| list_cons(s, rest) =>
  (
  case+ s of
  | PySreturn(loc, eopt) =>
      let val rexp = (case+ eopt of PyExpNone() => PCEunit(loc) | PyExpSome(e) => elab_exp(encl, e))
      in flow_app(loc, "flow_return", rexp) end
  | PySbreak(loc) => flow_app(loc, "flow_break", accs_tuple_exp(loc, accs))
  | PyScontinue(loc) => flow_app(loc, "flow_cont", accs_tuple_exp(loc, accs))
  | PyDlet(loc, _decos, ismut, p, ann, rhs) =>
      // M5a: thread the binding annotation onto PCElet; a `let mut x : T` also records it in mts.
      // (DECORATOR REWORK: the new decorator field is irrelevant to loop-accumulator analysis.)
      let
        val newmuts = (if ismut then add_pat_names(muts, p) else muts)
        val newmts = (if ismut then mt_add(mts, p, ann) else mts)
        val encl2 = add_pat_names(encl, p)   // the binder is a function-local hereafter
      in
        PCElet(loc, elab_pat(p), ann, elab_exp(encl, rhs), fl_suite(encl2, rest, accs, newmuts, newmts))
      end
  | PySvar(loc, nm, ann, rhs) =>
      // a MUTABLE CELL declared INSIDE a loop body. CRITICAL: a `var` is NEVER a loop
      // accumulator — it does NOT enter `accs`/`muts`/`mts`. It is an in-place cell scoping
      // the rest of THIS loop-body suite (PCEvarcell's body); it extends `encl` only.
      let val encl1 = nameset_add(encl, nm) in
        PCEvarcell(loc, nm, ann, elab_exp(encl, rhs), fl_suite(encl1, rest, accs, muts, mts))
      end
  | PySassign(loc, lv, rhs) =>
      // a CELL ASSIGNMENT inside a loop body -> PCEassign (D2Eassgn), in place. DISTINCT from
      // `=` reassign (which SSA-rebinds an accumulator in `muts`): a var cell is mutated where
      // it lives — captured from the enclosing scope, not threaded through the loop's accs.
      PCEseq(loc, PCEassign(loc, elab_exp(encl, lv), elab_exp(encl, rhs)),
             fl_suite(encl, rest, accs, muts, mts))
  // B-LINEAR: MOVE / SWAP inside a loop body — in place; NOT accumulators. `:=>`/`:=:` return the
  // l-value type (NOT void), so a non-tail move/swap is bound to a `_` wildcard let to absorb its
  // result (a void seq-init would reject the non-void value); the LAST one is the suite tail.
  | PySmove(loc, lv, rhs) =>
      (case+ rest of
       | list_nil() => PCEmove(loc, elab_exp(encl, lv), elab_exp(encl, rhs))
       | list_cons(_, _) =>
           PCElet(loc, PCPwild(loc), PyTypNone(), PCEmove(loc, elab_exp(encl, lv), elab_exp(encl, rhs)),
                  fl_suite(encl, rest, accs, muts, mts)))
  | PySswap(loc, lv, rhs) =>
      (case+ rest of
       | list_nil() => PCEswap(loc, elab_exp(encl, lv), elab_exp(encl, rhs))
       | list_cons(_, _) =>
           PCElet(loc, PCPwild(loc), PyTypNone(), PCEswap(loc, elab_exp(encl, lv), elab_exp(encl, rhs)),
                  fl_suite(encl, rest, accs, muts, mts)))
  | PySreassign(loc, lv, rhs) =>
      let val nm = lvalue_name(lv) in
        if strn_eq(nm, "")
          then PCEseq(loc, PCEapp(loc, PCEvar(loc, "set!"),
                                  list_cons(elab_exp(encl, lv), list_sing(elab_exp(encl, rhs)))),
                      fl_suite(encl, rest, accs, muts, mts))
        else if nameset_mem(muts, nm)
          then PCElet(loc, PCPvar(loc, nm), PyTypNone(), elab_exp(encl, rhs), fl_suite(encl, rest, accs, muts, mts))
        else PCEseq(loc, PCEerror(loc, strn_append("reassignment to non-mut binding: ", nm)),
                    fl_suite(encl, rest, accs, muts, mts))
      end
  | PySexpr(loc, e) => PCEseq(loc, elab_exp(encl, e), fl_suite(encl, rest, accs, muts, mts))
  | PySif(loc, gs, els) =>
      let val iff = fl_if(encl, loc, gs, els, accs, muts, mts)
      in fl_bind(loc, iff, accs, fl_suite(encl, rest, accs, muts, mts)) end
  | PySwhile(loc, cond, body, wels) =>
      let val w = wh_flow(encl, loc, cond, body, wels, muts, mts)
      in fl_bind(loc, w, accs, fl_suite(encl, rest, accs, muts, mts)) end
  | PySfor(loc, pat, iter, body, fels) =>
      let val fr = for_flow(encl, loc, pat, iter, body, fels, muts, mts)
      in fl_bind(loc, fr, accs, fl_suite(add_pat_names(encl, pat), rest, accs, muts, mts)) end
  | PySblock(loc, body) => fl_suite(encl, list_append(body, rest), accs, muts, mts)
  | PySdecl(loc, d) =>
      (case+ d of
       | PyCfun(floc, _decos, nm, _, params, ret, fbody, wheres) =>
           // SCOPING: an inner def in flow-mode MAY carry a `where:` block — wrap its body in
           // PCEwhere (M3 -> D2Ewhere); EMPTY where => no wrap (byte-identical to before).
           let
             val ibody0 = elab_func_body(fc_param_names_pub(encl, params), floc, fbody)
             val ibody1 =
               ( case+ wheres of
                 | list_nil() => ibody0
                 | _ => PCEwhere(floc, ibody0, elab_decls(wheres)) )
           in
             PCEletfun(loc,
               list_sing(PCFundcl(floc, nm, param_names_l(params), param_types_l(params),
                                  ret, ibody1, false)),
               fl_suite(nameset_add(encl, nm), rest, accs, muts, mts))
           end
       | _ => fl_suite(encl, rest, accs, muts, mts))
  | PySerror(loc, msg) => PCEseq(loc, PCEerror(loc, msg), fl_suite(encl, rest, accs, muts, mts))
  )
)
//
// M5a: register a `let mut p : T` annotation into the mut-type map (only a simple var binder).
and
mt_add(mts: muttypes, p: pypat, ann: pytypopt): muttypes =
( case+ p of PyPvar(_, nm) => muttypes_add(mts, nm, ann) | _ => mts )
//
// the §3 bind, inlined as a `case`: only flow_next runs `kont`; the rest short-circuit.
and
fl_bind(loc: loctn, m: pcexp, accs: nameset, kont: pcexp): pcexp =
let
  val a_next  = mk_arm_con("flow_next", accs, kont)
  val a_cont  = mk_arm_con("flow_cont", accs, flow_app(el_dloc(), "flow_cont", accs_tuple_exp(el_dloc(), accs)))
  val a_break = mk_arm_con("flow_break", accs, flow_app(el_dloc(), "flow_break", accs_tuple_exp(el_dloc(), accs)))
  val a_ret   = mk_arm_ret(flow_app(el_dloc(), "flow_return", PCEvar(el_dloc(), "r")))
in
  PCEcase(loc, m, list_cons(a_next, list_cons(a_cont, list_cons(a_break, list_sing(a_ret)))))
end
//
and
fl_if(encl: nameset, loc: loctn, gs: list(pyguard), els: pystmtlstopt, accs: nameset, muts: nameset, mts: muttypes): pcexp =
(
case+ gs of
| list_nil() =>
    (case+ els of
     | PyElseNone() => flow_app(loc, "flow_next", accs_tuple_exp(loc, accs))
     | PyElseSome(body) => fl_suite(encl, body, accs, muts, mts))
| list_cons(PyGuard(gloc, c, body), grest) =>
    PCEif(gloc, elab_exp(encl, c), fl_suite(encl, body, accs, muts, mts), fl_if(encl, loc, grest, els, accs, muts, mts))
)
//
(* ****** ****** *)
//
// ---- §5.2 while combinators (worker group) ----------------------------------
//
// the inner `case <body-flow> of next/cont => loop(TAIL) | break => flow_break | ret`.
and
wh_body_dispatch(encl: nameset, loc: loctn, body: list(pystmt), muts: nameset, mts: muttypes, accs: nameset): pcexp =
let
  val bodyflow = fl_suite(encl, body, accs, muts, mts)
  val a_next  = mk_arm_con("flow_next", accs, loop_call(loc, accs))
  val a_cont  = mk_arm_con("flow_cont", accs, loop_call(loc, accs))
  val a_break = mk_arm_con("flow_break", accs, flow_app(el_dloc(), "flow_break", accs_tuple_exp(el_dloc(), accs)))
  val a_ret   = mk_arm_ret(flow_app(el_dloc(), "flow_return", PCEvar(el_dloc(), "r")))
in
  PCEcase(loc, bodyflow, list_cons(a_next, list_cons(a_cont, list_cons(a_break, list_sing(a_ret)))))
end
//
// the outer `case loop(accs0) of next => <else?>;flow_next | break => flow_next | ret`.
and
out_dispatch(encl: nameset, loc: loctn, callinit: pcexp, els: pystmtlstopt, muts: nameset, mts: muttypes, accs: nameset): pcexp =
let
  val next_body =
    (case+ els of
     | PyElseNone() => flow_app(loc, "flow_next", accs_tuple_exp(loc, accs))
     | PyElseSome(ebody) =>
         PCEseq(loc, elab_else(encl, loc, ebody, muts, mts),
                flow_app(loc, "flow_next", accs_tuple_exp(loc, accs))))
  val a_next  = mk_arm_con("flow_next", accs, next_body)
  val a_break = mk_arm_con("flow_break", accs, flow_app(loc, "flow_next", accs_tuple_exp(loc, accs)))
  val a_ret   = mk_arm_ret(flow_app(loc, "flow_return", PCEvar(el_dloc(), "r")))
in
  PCEcase(loc, callinit, list_cons(a_next, list_cons(a_break, list_sing(a_ret))))
end
//
// the flow `while`.
and
wh_flow(encl: nameset, loc: loctn, cond: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, mts: muttypes): pcexp =
let
  val assigned = nameset_union(assigned_stmts(body), assigned_else_w(els))
  val accs = nameset_inter(muts, assigned)
  val inner = PCEif(loc, elab_exp(encl, cond),
                    wh_body_dispatch(encl, loc, body, muts, mts, accs),
                    flow_app(loc, "flow_next", accs_tuple_exp(loc, accs)))
  // M5a: the loop accumulator params carry their `let mut x : T` annotations (typed loop).
  val loopdcl = PCFundcl(el_dloc(), LOOPNAME, accs, accs_types(accs, mts), PyTypNone(), inner, true)
  val callinit = PCEapp(loc, PCEvar(el_dloc(), LOOPNAME), list_sing(accs_tuple_exp(loc, accs)))
in
  PCEletfun(loc, list_sing(loopdcl), out_dispatch(encl, loc, callinit, els, muts, mts, accs))
end
//
// the value `while` (value position: result tuple bound, then `kont` continues).
//
// TASK #18 FIX: route on the BODY's control-flow flags, NOT unconditionally through elab_pure.
// A value-position `while` is reached ONLY when the enclosing function body has NO `return`
// anywhere (el_func_body: any-return => flow mode), so `return` cannot occur in this body — but
// `break`/`continue` (consumed by the loop itself) CAN. The old code ALWAYS used elab_pure, which
// poisons a `break` to "break outside a loop" (elab_pure cannot express a break). The fix mirrors
// the task-#14 for_value routing: a CONTROL-BEARING body (break/continue present) goes through
// wh_flow + the outer flow dispatch; a CONTROL-PURE body keeps the §10.1 fast path (no flow, no
// case) so the §10.1 invariant (m25_while_pure builds NO flow ctors) still holds.
and
wh_value(encl: nameset, loc: loctn, cond: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, mts: muttypes, kont: pcexp): pcexp =
let
  val assigned = nameset_union(assigned_stmts(body), assigned_else_w(els))
  val accs = nameset_inter(muts, assigned)
  val control_pure = ~control_any(flags_stmts(body))   // no break/continue/return in the body
in
  if control_pure
    then
      // §10.1 fast path: no flow, no case — `if cond then <body;loop(TAIL)> else <accs>`.
      let
        val selfcall = loop_call(loc, accs)
        val body_threaded = elab_pure(encl, body, muts, mts, selfcall)
        val loop_body = PCEif(loc, elab_exp(encl, cond), body_threaded, accs_tuple_exp(loc, accs))
        // M5a: the loop accumulator params carry their `let mut x : T` annotations (typed loop).
        val loopdcl = PCFundcl(el_dloc(), LOOPNAME, accs, accs_types(accs, mts), PyTypNone(), loop_body, true)
        val callinit = PCEapp(loc, PCEvar(el_dloc(), LOOPNAME), list_sing(accs_tuple_exp(loc, accs)))
        val after =
          (case+ els of
           | PyElseNone() => kont
           | PyElseSome(ebody) => PCEseq(loc, elab_else(encl, loc, ebody, muts, mts), kont))
      in
        PCEletfun(loc, list_sing(loopdcl),
          PCElet(loc, accs_tuple_pat(loc, accs), PyTypNone(), callinit, after))
      end
  else
    // control-bearing: route through wh_flow (which, via out_dispatch, already runs the `else`
    // correctly — once, on cond-false exit, skipped on break), then dispatch on the flow ctors.
    // Every flow ctor maps to `kont`: the outer dispatch must NOT re-run elab_else. The break and
    // return arms are dead in value position but required for the match — mirror out_dispatch's
    // 3-arm shape (next/break/return); flow_cont is consumed inside the loop and never escapes.
    let
      val loopexp = wh_flow(encl, loc, cond, body, els, muts, mts)
      val a_next  = mk_arm_con("flow_next", accs, kont)
      val a_break = mk_arm_con("flow_break", accs, kont)
      val a_ret   = mk_arm_ret(kont)
    in
      PCEcase(loc, loopexp, list_cons(a_next, list_cons(a_break, list_sing(a_ret))))
    end
end
//
(* ****** ****** *)
//
// ---- §5.3 for combinators (worker group) ------------------------------------
//
// the body dispatch for the THREADED `for`: only the loop-continuing arms (next/cont)
// thread `it'` into the self-call; break/return carry the user accumulators only (the
// iterator state never escapes the loop's flow result).
and
for_body_dispatch(encl: nameset, loc: loctn, body: list(pystmt), muts: nameset, mts: muttypes, accs: nameset): pcexp =
let
  val bodyflow = fl_suite(encl, body, accs, muts, mts)
  val a_next  = mk_arm_con("flow_next", accs, loop_call_it(loc, accs))   // TAIL, threads it'
  val a_cont  = mk_arm_con("flow_cont", accs, loop_call_it(loc, accs))   // TAIL, threads it'
  val a_break = mk_arm_con("flow_break", accs, flow_app(el_dloc(), "flow_break", accs_tuple_exp(el_dloc(), accs)))
  val a_ret   = mk_arm_ret(flow_app(el_dloc(), "flow_return", PCEvar(el_dloc(), "r")))
in
  PCEcase(loc, bodyflow, list_cons(a_next, list_cons(a_cont, list_cons(a_break, list_sing(a_ret)))))
end
//
// the THREADED iterator loop construct (returns a flow). Shared by for_flow + the
// for_value fallback (multi-acc / else). The loop parameter is `(it, <accs>)`:
//
//   let fun loop((it, <accs>)) =
//         case iter_step(it) of
//         | iter_done()       => flow_next(<accs>)
//         | iter_more(x, it1) => <body-dispatch ; self-call loop((it1, <accs'>))>
//   in <outer-dispatch on> loop((iter_open(iter), <accs0>))
//
// `it` is threaded as a tail-call argument (it1 from the iter_more pattern) — no cell.
and
for_iter_loop
(encl: nameset, loc: loctn, pat: pypat, iter: pyexp, body: list(pystmt), els: pystmtlstopt,
 muts: nameset, mts: muttypes, accs: nameset): pcexp =
let
  val xname = (case+ pat of PyPvar(_, nm) => nm | _ => "_x")
  // the loop element pattern binds inside the body (a function-local for a @func lambda there).
  val encl_body = add_pat_names(encl, pat)
  val itparams = it_params(accs)   // loop parameter nameset = it :: accs
  // M5a: the `it` slot is untyped (its type is inferred from iter_open); the accs carry theirs.
  val itptypes = list_cons(PyTypNone(), accs_types(accs, mts))
  val stepcall = PCEapp(loc, PCEvar(loc, "iter_step"), list_sing(PCEvar(el_dloc(), ITNAME)))
  val a_done = PCArm(el_dloc(), PCPcon(el_dloc(), "iter_done", list_nil()(*sargs*), list_nil()), PCEGNone(),
                     flow_app(el_dloc(), "flow_next", accs_tuple_exp(el_dloc(), accs)))
  val bodydisp = for_body_dispatch(encl_body, loc, body, muts, mts, accs)
  // iter_more(x, it1): bind the element `x` AND the advanced iterator `it1` (threaded).
  val more_pat =
    PCPcon(el_dloc(), "iter_more", list_nil()(*sargs*),
           list_cons(PCPvar(el_dloc(), xname), list_sing(PCPvar(el_dloc(), ITNEXT))))
  val a_more = PCArm(el_dloc(), more_pat, PCEGNone(), bodydisp)
  val step_case = PCEcase(loc, stepcall, list_cons(a_done, list_sing(a_more)))
  val loopdcl = PCFundcl(el_dloc(), LOOPNAME, itparams, itptypes, PyTypNone(), step_case, true)
  val openit = PCEapp(loc, PCEvar(loc, "iter_open"), list_sing(elab_exp(encl, iter)))
  val callinit = loop_call_init(loc, openit, accs)   // loop((iter_open(iter), accs0))
in
  PCEletfun(loc, list_sing(loopdcl), out_dispatch(encl, loc, callinit, els, muts, mts, accs))
end
//
and
for_flow(encl: nameset, loc: loctn, pat: pypat, iter: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, mts: muttypes): pcexp =
let
  val assigned = nameset_union(assigned_stmts(body), assigned_else_w(els))
  val accs = nameset_inter(muts, assigned)
in
  for_iter_loop(encl, loc, pat, iter, body, els, muts, mts, accs)
end
//
// the fast-path value `for`: control-PURE single-acc no-else -> list_foldleft; else the
// iterator loop, value-spliced (bind the final accs, then kont).
//
// TASK #14 FIX: the fast path is chosen on the BODY's control-flow flags, NOT on accumulator
// arity alone. A `for` whose body contains a break/continue/return is CONTROL-BEARING and MUST
// take the iterator/flow path (for_iter_loop + the outer flow dispatch), even with a single
// accumulator and no else — otherwise its `break` poisons to "break outside a loop" (elab_pure,
// which the fast path uses, cannot express a break). control_pure <=> flags_stmts(body) has no
// break/continue/return set (control_any = false). The else-branch below already handles the
// control-bearing case correctly (it routes through for_iter_loop and dispatches on the flow
// ctors, so a single-accumulator `for ... break` now works).
and
for_value(encl: nameset, loc: loctn, pat: pypat, iter: pyexp, body: list(pystmt), els: pystmtlstopt, muts: nameset, mts: muttypes, kont: pcexp): pcexp =
let
  val assigned = nameset_union(assigned_stmts(body), assigned_else_w(els))
  val accs = nameset_inter(muts, assigned)
  val noelse = (case+ els of PyElseNone() => true | _ => false)
  val single = (case+ accs of list_cons(_, list_nil()) => true | _ => false)
  val control_pure = ~control_any(flags_stmts(body))   // no break/continue/return in the body
in
  if b_and(b_and(single, noelse), control_pure)
    then
      let
        val accname = (case+ accs of list_cons(nm, _) => nm | _ => "_acc")
        val xname = (case+ pat of PyPvar(_, nm) => nm | _ => "_x")
        // the fold lambda binds `acc` and the element `x` inside its body (function-locals).
        val encl_fold = nameset_add(add_pat_names(encl, pat), accname)
        val step_body = elab_pure(encl_fold, body, muts, mts, PCEvar(loc, accname))
        // M5a: the fold's accumulator param carries its `let mut acc : T` annotation; the
        // element param `x` stays untyped (its type flows from the iterable's element type).
        val folder = PCElam(loc, false(*synthesized fold lam, not @func*),
                            list_cons(accname, list_sing(xname)),
                            list_cons(muttypes_find(mts, accname), list_sing(PyTypNone())),
                            step_body)
        val foldcall =
          PCEapp(loc, PCEvar(loc, "list_foldleft"),
                 list_cons(elab_exp(encl, iter), list_cons(PCEvar(loc, accname), list_sing(folder))))
      in
        PCElet(loc, PCPvar(loc, accname), PyTypNone(), foldcall, kont)
      end
  else
    // TASK #19 FIX: for_iter_loop (via out_dispatch) already runs the `else` exactly once on the
    // no-break path; the OUTER dispatch must NOT run it again. The previous code used a `next_after`
    // that re-ran elab_else on the flow_next arm, so a control-bearing for/while-`else` body
    // executed TWICE on normal completion. Map every flow ctor to `kont` (no re-run of elab_else).
    // The break/return arms are dead in value position but required for the match — mirror
    // out_dispatch's 3-arm shape (next/break/return); flow_cont is consumed inside the loop.
    let
      val loopexp = for_iter_loop(encl, loc, pat, iter, body, els, muts, mts, accs)
      val a_next  = mk_arm_con("flow_next", accs, kont)
      val a_break = mk_arm_con("flow_break", accs, kont)
      val a_ret   = mk_arm_ret(kont)
    in
      PCEcase(loc, loopexp, list_cons(a_next, list_cons(a_break, list_sing(a_ret))))
    end
end
//
(* ****** ****** *)
//
// ---- thin #implfun wrappers for the SATS entries ---------------------------
//
#implfun elab_flow(encl, ss, accs, muts, mts) = fl_suite(encl, ss, accs, muts, mts)
#implfun elab_while_flow(encl, loc, cond, body, els, muts, mts, _accs) = wh_flow(encl, loc, cond, body, els, muts, mts)
#implfun elab_for_flow(encl, loc, pat, iter, body, els, muts, mts, _accs) = for_flow(encl, loc, pat, iter, body, els, muts, mts)
#implfun elab_while_value(encl, loc, cond, body, els, muts, mts, kont) = wh_value(encl, loc, cond, body, els, muts, mts, kont)
#implfun elab_for_value(encl, loc, pat, iter, body, els, muts, mts, kont) = for_value(encl, loc, pat, iter, body, els, muts, mts, kont)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_loop.dats]
*)
