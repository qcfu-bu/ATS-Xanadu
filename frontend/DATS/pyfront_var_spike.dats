(* ****** ****** *)
(*
** VAR GATING SPIKE driver — proves a REAL `var`/mutation (an aliasable mutable
** CELL, distinct from our `let mut` SSA rebinding) can be CONSTRUCTED DIRECTLY at
** level-2 and TYPECHECK to nerror=0 through the stock pipeline.
**
** Two cases, each its own d2parsed + pipeline + nerror probe:
**
** (1) STRAIGHT-LINE  — the equivalent of:
**         def count() -> Int:
**             var x: Int = 0
**             x := 5
**             let y = x          # y : Int
**             y
**     i.e. a `def count()` whose body is
**         D2Elet0([D2Cvardclst(VAR, [vardcl x : Int = 0])],
**                 D2Eseqn([D2Eassgn(D2Evar x, 5)],
**                         D2Elet0([val y = D2Evar x], D2Evar y)))
**     The var cell DECLARES (D2Cvardclst via d2vardcl_make_args, vpid=None), ASSIGNS
**     (D2Eassgn), and READS (D2Evar x in the val-rhs). nerror=0?
**
** (2) VAR-IN-LOOP  — the KEY interaction; the equivalent of:
**         def sum_to(n: Int) -> Int:
**             var s: Int = 0
**             var i: Int = 0
**             let fun loop() =
**                 if i < n then (s := s + i; i := i + 1; loop()) else ()
**             loop()
**             s
**     i.e. the var cells `s`,`i` are declared in the def body, then a LOCAL
**     tail-recursive `loop` (a D2Cfundclst inside a D2Elet0 — exactly the shape the
**     `while` desugaring produces) CAPTURES the cells and ASSIGNS them in place
**     (D2Eassgn inside the loop closure body). The vars are NOT loop accumulators
**     (not threaded through the loop's params) — they are real cells mutated in place.
**     Does a var captured + assigned inside the desugared tail-recursive loop closure
**     TYPECHECK? (possible view/linearity wall — views are parsed+threaded but NOT
**     enforced at typecheck, recipe finding). nerror=0?  -> GO/NO-GO for var-in-loop.
**
** RECIPE MIRRORED FROM (cited):
**   srcgen2/SATS/dynexp2.sats:1522 D2Cvardclst(token VAR, d2vardclist);
**     :1852 d2vardcl_make_args(loc, dpid:d2var, vpid:d2varopt, sres:s2expopt,
**           dini:teqd2exp).  vpid OPTIONAL (optn_nil = no view-proof id).
**   trans2a_decl00.dats:945 trans2a_d2vardcl : dpid.styp(s2typ_lft(tres)) — the var's
**     d2var is typed as a LEFT-VALUE of its result type; a later D2Evar read of it is
**     an lval of T (assignable + readable as T).
**   trans12_decl00.dats:2861 f1_add0_d2vs : after building the vardcls, REGISTER each
**     dpid (+ vpid) into the env via tr12env_add0_d2var so a later read resolves. We
**     do that registration ourselves (we hand-build, no L1->L2 pass).
**   trans23_dynexp.dats:2662 f0_assgn : typechecks the LHS to t2pl, then the RHS to
**     t2pl, returns void — NO view consumption (so a plain `var x:T=e; x:=e'` needs no
**     view plumbing). trans23_decl00.dats:896 trans23_d2vardcl : threads the vardcl.
**
** PURELY ADDITIVE: only CALLS the compiler-as-a-library (lib2xatsopt). Nothing under
** srcgen2/ or language-server/ is modified. Typecheck-only (no codegen).
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
// s1exp_none0 for the `given` slot of a D2Pannot binder.
#staload "./../../srcgen2/SATS/staexp1.sats"
#staload "./../../srcgen2/SATS/dynexp1.sats"
//
(* ****** ****** *)
//
#extern fun PYB_log(s: strn): void = $extnam()
#extern fun PYB_log_int(s: strn, n: sint): void = $extnam()
//
(* ****** ****** *)
//
// resolve a (prelude) static type NAME to its s2exp (pylower_staexp resolve_typ). The
// surface `Int` aliases to the prelude internal `the_s2exp_sint0` (M5a finding) — the
// SAME T2Pcst the int literal carries.
//
fun
resolve_typ_name(env: !tr12env, name: strn): s2exp = let
  val key = symbl_make_name(name)
  val sopt = tr12env_find_s2itm(env, key)
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then s2exp_none0() else s2exp_cst(s2cs.head())
      | S2ITMvar(s2v)  => s2exp_var(s2v)
      | S2ITMenv(_)    => s2exp_none0()
    )
  | ~optn_vt_nil() => s2exp_none0()
end
//
// resolve a bound dynamic VARIABLE by name to a D2Evar reference. The name is bound at
// every call site (we add it ourselves), so the recovery yields a none-node.
//
fun
resolve_var(env: !tr12env, loc: loctn, name: strn): d2exp = let
  val dopt = tr12env_find_d2itm(env, symbl_make_name(name))
in
  case+ dopt of
  | ~optn_vt_cons(d2i) =>
    (
      case+ d2i of
      | D2ITMvar(d2v) => d2exp_make_node(loc, D2Evar(d2v))
      | _ => d2exp_none0(loc)
    )
  | ~optn_vt_nil() => d2exp_none0(loc)
end
//
(* ****** ****** *)
//
// helper makers (mirror pylower_dynexp.dats tok_*/literal builders).
//
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_var(loc: loctn): token = token_make_node(loc, T_VAR(VRKvar))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2))
fun tok_eq (loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
//
fun d2e_int(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
//
// resolve a binary operator NAME (e.g. "+", "<"). EXACTLY mirrors pl_var
// (pylower_dynexp.dats:153): an OVERLOADED operator resolves to D2ITMsym -> a
// d2exp_sym0 node (the #13a overload-resolution path); trans2a then picks the right
// instance from the operand types. (A naive D2ITMcst-only lookup -> d2exp_none0 was the
// FIRST spike bug — it broke i<n / s+i / i+1, masquerading as a var-in-loop wall.)
//
fun d2e_op(env: !tr12env, loc: loctn, sym: sym_t): d2exp = let
  val dopt = tr12env_find_d2itm(env, sym)
in
  case+ dopt of
  | ~optn_vt_nil() => d2exp_none1(d1exp_make_node(loc, D1Eid0(sym)))
  | ~optn_vt_cons(d2i) =>
    (
      case+ d2i of
      | D2ITMvar(d2v)  => d2exp_var(loc, d2v)
      | D2ITMcon(d2cs) =>
          if list_singq(d2cs) then d2exp_con(loc, d2cs.head()) else d2exp_cons(loc, d2cs)
      | D2ITMcst(d2cs) =>
          if list_singq(d2cs) then d2exp_cst(loc, d2cs.head()) else d2exp_csts(loc, d2cs)
      | D2ITMsym(_, dpis) =>
          d2exp_sym0(loc, d2rxp_new1(loc), d1exp_make_node(loc, D1Eid0(sym)), dpis)
    )
end
//
// a binary application  op(a, b)  ->  D2Edapp(op, -1, [a, b]).
fun d2e_binop(env: !tr12env, loc: loctn, opname: strn, a: d2exp, b: d2exp): d2exp = let
  val d2op = d2e_op(env, loc, symbl_make_name(opname))
in
  d2exp_make_node(loc, D2Edapp(d2op, (-1), list_cons(a, list_sing(b))))
end
//
(* ****** ****** *)
//
// build ONE `var name : Int = init` cell as a D2Cvardclst decl, REGISTER its dpid in
// the env (so a later read/assign resolves), and return the decl. vpid = optn_nil
// (NO view-proof id — the recipe finding: vpid OPTIONAL, views not enforced).
//
fun
build_var_cell
  (env: !tr12env, loc: loctn, name: strn, s2e_typ: s2exp, init: d2exp): d2ecl = let
  val d2v = d2var_new2_name(loc, symbl_make_name(name))
  val sres = optn_cons(s2e_typ)                       // sres: s2expopt = Some(Int)
  val dini = TEQD2EXPsome(tok_eq(loc), init)
  val dvar = d2vardcl_make_args(loc, d2v, optn_nil()(*vpid*), sres, dini)
  // register the cell's dpid so a later D2Evar read/assign of it resolves.
  val () = tr12env_add0_d2var(env, d2v)
in
  d2ecl_make_node(loc, D2Cvardclst(tok_var(loc), list_sing(dvar)))
end
//
// a cell assignment  name := rval  ->  D2Eassgn(D2Evar name, rval).
fun
build_assign(env: !tr12env, loc: loctn, name: strn, rval: d2exp): d2exp = let
  val lval = resolve_var(env, loc, name)
in
  d2exp_make_node(loc, D2Eassgn(lval, rval))
end
//
(* ****** ****** *)
//
// ====================== CASE (1): STRAIGHT-LINE var ==========================
//
//   def count() -> Int:
//       var x: Int = 0
//       x := 5
//       let y = x
//       y
//
fun
build_case1((*void*)): d2parsed = let
//
val loc = loctn_dummy()
val env = tr12env_make_nil()
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// def count() -> Int : a nullary fun. Bind the name first (recursive group order).
val d2v_count = d2var_new2_name(loc, symbl_make_name("count"))
val () = tr12env_add0_d2var(env, d2v_count)
val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
val sres = S2RESsome(S2EFFnone(), s2e_int)
//
// enter the fun's param scope, then a let-scope for the body's local decls.
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as)
val () = tr12env_pshlet0(env)
//
// (a) the var cell : `var x : Int = 0`  -> D2Cvardclst, x registered.
val decl_x = build_var_cell(env, loc, "x", s2e_int, d2e_int(loc, "0"))
//
// (b) `x := 5`  -> D2Eassgn(D2Evar x, 5).
val assign5 = build_assign(env, loc, "x", d2e_int(loc, "5"))
//
// (c) `let y = x`  -> a D2Cvaldclst binding y to the cell read (D2Evar x : Int).
val d2v_y = d2var_new2_name(loc, symbl_make_name("y"))
val pat_y = d2pat_var(loc, d2v_y)
val read_x = resolve_var(env, loc, "x")              // reads the cell as Int (lval of Int)
val () = tr12env_add0_d2var(env, d2v_y)
val dval_y =
  d2valdcl_make_args(loc, pat_y, TEQD2EXPsome(tok_val(loc), read_x), WTHS2EXPnone())
val decl_y = d2ecl_make_node(loc, D2Cvaldclst(tok_val(loc), list_sing(dval_y)))
//
// (d) the tail value `y`.
val read_y = resolve_var(env, loc, "y")
//
// body : let val y = x in (let-y-scope) y  — but y's decl must be in scope with the
// var+assign. Structure: D2Elet0([decl_x], D2Eseqn([assign5], D2Elet0([decl_y], y))).
val inner = d2exp_make_node(loc, D2Elet0(list_sing(decl_y), read_y))
val seqd  = d2exp_make_node(loc, D2Eseqn(list_sing(assign5), inner))
val d2body = d2exp_make_node(loc, D2Elet0(list_sing(decl_x), seqd))
//
val () = tr12env_poplet0(env)
val () = tr12env_poplam0(env)
//
val d2f =
  d2fundcl_make_args
    (loc, d2v_count, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
val fundecl =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
//
val decls = list_sing(fundecl)
val t2penv = tr12env_free_top(env)
val dpar =
  d2parsed_make_args
  ( 1(*dynamic*), 0(*nerror*), LCSRCnone0()
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
in
  dpar
end // end of [build_case1]
//
(* ****** ****** *)
//
// ====================== CASE (2): var-in-LOOP ================================
//
//   def sum_to(n: Int) -> Int:
//       var s: Int = 0
//       var i: Int = 0
//       let fun loop() =
//           if i < n then (s := s + i; i := i + 1; loop()) else ()
//       loop()
//       s
//
// The var cells s,i are declared in the def body; a LOCAL tail-recursive `loop`
// (D2Cfundclst inside a D2Elet0 — the while-desugaring shape) CAPTURES the cells and
// ASSIGNS them in place. The vars are NOT loop accumulators (not loop params).
//
fun
build_case2((*void*)): d2parsed = let
//
val loc = loctn_dummy()
val env = tr12env_make_nil()
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// def sum_to(n: Int) -> Int.
val d2v_sum = d2var_new2_name(loc, symbl_make_name("sum_to"))
val () = tr12env_add0_d2var(env, d2v_sum)
val d2v_n = d2var_new2_name(loc, symbl_make_name("n"))
val pat_n = d2pat_var(loc, d2v_n)
val pat_n_annot = d2pat_make_node(loc, D2Pannot(pat_n, s1exp_none0(loc), s2e_int))
val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_n_annot))))
val sres = S2RESsome(S2EFFnone(), s2e_int)
//
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as)
val () = tr12env_pshlet0(env)
//
// var s : Int = 0 ; var i : Int = 0.
val decl_s = build_var_cell(env, loc, "s", s2e_int, d2e_int(loc, "0"))
val decl_i = build_var_cell(env, loc, "i", s2e_int, d2e_int(loc, "0"))
//
// the local loop : `let fun loop() = if i < n then (s:=s+i; i:=i+1; loop()) else ()`.
// Bind the loop name FIRST (the self-call resolves to the same d2var; tail-call test).
val d2v_loop = d2var_new2_name(loc, symbl_make_name("loop"))
val () = tr12env_add0_d2var(env, d2v_loop)
val loop_f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
//
// enter the loop fun's body scope (it captures s,i,n,loop from the outer env).
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, loop_f2as)
//
// cond : i < n.
val cond = d2e_binop(env, loc, "<", resolve_var(env, loc, "i"), resolve_var(env, loc, "n"))
// s := s + i.
val assign_s = build_assign(env, loc, "s",
  d2e_binop(env, loc, "+", resolve_var(env, loc, "s"), resolve_var(env, loc, "i")))
// i := i + 1.
val assign_i = build_assign(env, loc, "i",
  d2e_binop(env, loc, "+", resolve_var(env, loc, "i"), d2e_int(loc, "1")))
// loop() self-call.
val selfcall = d2exp_make_node(loc, D2Edap0(resolve_var(env, loc, "loop")))
// then-branch : (s:=s+i; i:=i+1; loop())  -> D2Eseqn([assign_s, assign_i], loop()).
val thenbr = d2exp_make_node(loc, D2Eseqn(list_cons(assign_s, list_sing(assign_i)), selfcall))
// else-branch : ()  -> empty tuple (unit).
val elsebr = d2exp_make_node(loc, D2Etup0((-1), list_nil()))
val loopbody = d2exp_make_node(loc, D2Eift0(cond, optn_cons(thenbr), optn_cons(elsebr)))
//
val () = tr12env_poplam0(env)  // exit loop body scope
//
val d2f_loop =
  d2fundcl_make_args
    (loc, d2v_loop, loop_f2as, S2RESnone(), TEQD2EXPsome(tok_val(loc), loopbody), WTHS2EXPnone())
val decl_loop =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_loop)))
//
// the def body tail : `loop(); s` -> D2Eseqn([loop()], D2Evar s).
val callinit = d2exp_make_node(loc, D2Edap0(resolve_var(env, loc, "loop")))
val read_s   = resolve_var(env, loc, "s")
val tail     = d2exp_make_node(loc, D2Eseqn(list_sing(callinit), read_s))
//
// assemble : let var s; let var i; let fun loop=...; (loop(); s).
// D2Elet0([decl_s], D2Elet0([decl_i], D2Elet0([decl_loop], tail))).
val b3 = d2exp_make_node(loc, D2Elet0(list_sing(decl_loop), tail))
val b2 = d2exp_make_node(loc, D2Elet0(list_sing(decl_i), b3))
val d2body = d2exp_make_node(loc, D2Elet0(list_sing(decl_s), b2))
//
val () = tr12env_poplet0(env)
val () = tr12env_poplam0(env)
//
val d2f =
  d2fundcl_make_args
    (loc, d2v_sum, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
val fundecl =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
//
val decls = list_sing(fundecl)
val t2penv = tr12env_free_top(env)
val dpar =
  d2parsed_make_args
  ( 1(*dynamic*), 0(*nerror*), LCSRCnone0()
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
in
  dpar
end // end of [build_case2]
//
(* ****** ****** *)
//
// the full L2 -> L3 pipeline (same as the m5b spike).
//
fun
run_pipeline(dpar: d2parsed): d3parsed = let
  val dpar = d2parsed_of_trans2a(dpar)
  val () = PYB_log("  trans2a (overload res) done")
  val ( ) = d2parsed_by_trsym2b(dpar)
  val () = PYB_log("  trsym2b (symbol res) done")
  val dpar = d2parsed_of_t2read0(dpar)
  val () = PYB_log("  t2read0 (L2 read/check) done")
  val dp3 = d3parsed_of_trans23(dpar)
  val () = PYB_log("  trans23 (L2 -> L3) done")
in
  dp3
end
//
// run one case, probe nerror, report.
fun
run_case(label: strn, dpar: d2parsed): sint = let
  val dp3 = run_pipeline(dpar)
  val dp3 = d3parsed_of_tread3a(dp3)
  val nerror = d3parsed_get_nerror(dp3)
  val () = PYB_log_int("  nerror (after tread3a) =", nerror)
  val out0 = g_stderr()
  val () = f3perr0_d3parsed(out0, dp3)
in
  nerror
end
//
(* ****** ****** *)
//
fun
mymain_var((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYB_log("######## VAR (mutable cell) GATING SPIKE ########")
//
val () = PYB_log("[case 1] straight-line: var x:Int=0; x:=5; let y=x; y")
val n1 = run_case("case1", build_case1())
//
val () = PYB_log("[case 2] var-in-loop: var s,i; let fun loop=if i<n then (s:=s+i;i:=i+1;loop()) else (); loop(); s")
val n2 = run_case("case2", build_case2())
//
val () = (if n1 = 0 then PYB_log("RESULT case1: GO (straight-line var typechecks, nerror=0)")
          else PYB_log("RESULT case1: NO-GO (nerror != 0)"))
val () = (if n2 = 0 then PYB_log("RESULT case2: GO (var-in-loop typechecks, nerror=0)")
          else PYB_log("RESULT case2: NO-GO (var-in-loop nerror != 0)"))
//
in
  if (n1 = 0) then
    (if n2 = 0 then PYB_log("RESULT: PASS (both var cases typecheck, nerror=0)")
     else PYB_log("RESULT: PARTIAL (case1 GO, case2 NO-GO — see f3perr0 above)"))
  else
    PYB_log("RESULT: FAIL (case1 NO-GO — straight-line var did not typecheck)")
end // end of [mymain_var]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_var()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_var_spike.dats]
*)
