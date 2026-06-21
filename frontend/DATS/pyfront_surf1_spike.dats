(* ****** ****** *)
(*
** SURF1 GATING SPIKE driver — proves the two RISKY decl-level surface-parity
** features can be CONSTRUCTED DIRECTLY at level-2 and TYPECHECK to nerror=0
** through the stock pipeline (trans2a/trsym2b/t2read0/trans23/tread3a).
**
** (3) IMPLEMENT  — `extern def foo(x:Int)->Int` (a registered bodyless d2cst) +
**     `implement foo(x): x + x` (a D2Cimplmnt0 attaching a body) + a call `foo(5)`.
**     RECIPE (mirrors stock f0_implmnt0_dimp @ trans12_decl00.dats:3373-3463):
**       * resolve the pre-declared d2cst by NAME (tr12env_find_d2itm -> D2ITMcst head),
**       * wrap as dimpl(loc, DIMPLone1(d2c)),
**       * impkind token T_IMPLMNT(IMPLfun()),
**       * f2arglst = the param-pattern list (the binders the body references),
**       * BIND those params in a pshlam0/add0_f2as scope, build the body d2exp, poplam0,
**       * D2Cimplmnt0(tknd, [], [], dimp, [], f2as, S2RESnone(), body) — all quantifier
**         lists empty for the MONOMORPHIC case.
**     Registration: NONE needed beyond the d2cst the extern already added.  nerror=0?
**
** (4) OVERLOAD  — `def my_show(x:Int)->Int: x` (a registered d2cst) + an overload that
**     makes the NAME `show` resolve to `my_show` (a D2Csymload) + a use `show(7)`.
**     RECIPE (mirrors stock f0_symload @ trans12_decl00.dats:2056-2154):
**       * resolve the IMPL d2itm by name (tr12env_find_d2itm "my_show" -> D2ITMcst),
**       * wrap as d2ptm = D2PTMsome(0(*pval*), ditm),
**       * fetch any existing overload bucket under `show` (merge), else [],
**       * REGISTER: tr12env_add0_d2itm(env, sym_show, D2ITMsym(sym_show, dptm::bucket))
**         — THIS is the whole mechanism that makes `show` resolve to `my_show`,
**       * emit D2Csymload(tknd, sym_show, dptm).  nerror=0?
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
// resolve a (prelude) static type NAME to its s2exp. `Int` aliases to the prelude
// internal `the_s2exp_sint0` (the M5a finding — the SAME T2Pcst an int literal carries).
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
// resolve a bound dynamic VARIABLE by name to a D2Evar reference.
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
// resolve a NAME used as a CALLABLE — branch on the d2itm (mirrors pl_var). A def/extern
// resolves to D2ITMcst -> d2exp_cst; an OVERLOAD resolves to D2ITMsym -> d2exp_sym0.
fun
resolve_callee(env: !tr12env, loc: loctn, name: strn): d2exp = let
  val sym = symbl_make_name(name)
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
(* ****** ****** *)
//
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2))
//
fun d2e_int(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
//
// resolve a binary operator NAME ("+", ...) to a D2ITMsym -> d2exp_sym0 (the #13a path).
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
fun d2e_binop(env: !tr12env, loc: loctn, opname: strn, a: d2exp, b: d2exp): d2exp = let
  val d2op = d2e_op(env, loc, symbl_make_name(opname))
in
  d2exp_make_node(loc, D2Edapp(d2op, (-1), list_cons(a, list_sing(b))))
end
//
// build + REGISTER an `extern def name(Int)->Int` bodyless d2cst (mirrors build_extern in
// pylower_decl00.dats). Returns the D2Cextern decl AND the resolved d2cst stays in `env`.
fun
build_extern_intfun
  (env: !tr12env, loc: loctn, name: strn, s2e_int: s2exp): d2ecl = let
  val argtyps = list_sing(s2e_int)
  val sfun    = s2exp_fun1_nil0((-1)(*npf*), argtyps, s2e_int)
  val tok_id  = token_make_node(loc, T_IDALP(name))
  val tok_fnk = token_make_node(loc, T_FUN(FNKfn2))
  val d2c     = d2cst_make_idtp(tok_fnk, tok_id, list_nil()(*tqas*), sfun)
  val () = tr12env_add1_d2cst(env, d2c)
  val dcdcl   = d2cstdcl_make_args(loc, d2c, list_nil()(*darg*), S2RESnone(), TEQD2EXPnone())
  val dyncst  = d2ecl_make_node(loc, D2Cdynconst(tok_fnk, list_nil()(*tqas*), list_sing(dcdcl)))
  val tok_ext = token_make_node(loc, T_SRP_EXTERN())
in
  d2ecl_make_node(loc, D2Cextern(tok_ext, dyncst))
end
//
// build + REGISTER a top-level `def name(x:Int)->Int: <body>` as a D2Cfundclst, returning
// the decl (the def's d2cst-ish d2var is registered under `name` so a call resolves).
// `mkbody(env)` builds the body in the param scope (x bound).
fun
build_def_intfun
  (env: !tr12env, loc: loctn, name: strn, s2e_int: s2exp,
   mkbody: (!tr12env, d2var) -<cloref1> d2exp): d2ecl = let
  val d2v_f = d2var_new2_name(loc, symbl_make_name(name))
  val () = tr12env_add0_d2var(env, d2v_f)            // recursive group order: name first
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val pat_x = d2pat_var(loc, d2v_x)
  val pat_x_ann = d2pat_make_node(loc, D2Pannot(pat_x, s1exp_none0(loc), s2e_int))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_x_ann))))
  val sres = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val body = mkbody(env, d2v_x)
  val () = tr12env_poplam0(env)
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val(loc), body), WTHS2EXPnone())
in
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
end
//
(* ****** ****** *)
//
// ============ CASE (3): IMPLEMENT ============================================
//   extern def foo(x: Int) -> Int
//   implement foo(x): x + x
//   def caller() -> Int: foo(5)
//
fun
build_case_implement((*void*)): d2parsed = let
//
val loc = loctn_dummy()
val env = tr12env_make_nil()
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// (a) extern def foo(x:Int)->Int  — registers the bodyless d2cst `foo`.
val decl_extern = build_extern_intfun(env, loc, "foo", s2e_int)
//
// (b) implement foo(x): x + x
//   resolve the pre-declared d2cst `foo` by name -> dimpl(DIMPLone1).
val d2c_foo =
  (
  case+ tr12env_find_d2itm(env, symbl_make_name("foo")) of
  | ~optn_vt_cons(d2i) =>
    (case+ d2i of
     | D2ITMcst(d2cs) => (if list_nilq(d2cs) then optn_nil() else optn_cons(d2cs.head()))
     | _ => optn_nil())
  | ~optn_vt_nil() => optn_nil()
  ): optn(d2cst)
val decl_impl =
  (
  case+ d2c_foo of
  | ~optn_cons(d2c) => let
      val dimp = dimpl_make_node(loc, DIMPLone1(d2c))
      val tknd = token_make_node(loc, T_IMPLMNT(IMPLfun()))
      // f2arglst = the param-pattern list (x : Int) the body references.
      val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
      val pat_x = d2pat_var(loc, d2v_x)
      val pat_x_ann = d2pat_make_node(loc, D2Pannot(pat_x, s1exp_none0(loc), s2e_int))
      val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_x_ann))))
      // bind x in a lam scope, build body `x + x`, pop.
      val () = tr12env_pshlam0(env)
      val () = tr12env_add0_f2arglst(env, f2as)
      val read_x1 = d2exp_make_node(loc, D2Evar(d2v_x))
      val read_x2 = d2exp_make_node(loc, D2Evar(d2v_x))
      val body = d2e_binop(env, loc, "+", read_x1, read_x2)
      val () = tr12env_poplam0(env)
    in
      d2ecl_make_node
        (loc, D2Cimplmnt0(tknd, list_nil()(*sqas*), list_nil()(*tqas*),
                          dimp, list_nil()(*tias*), f2as, S2RESnone(), body))
    end
  | ~optn_nil() => d2ecl_make_node(loc, D2Cnone0())
  ): d2ecl
//
// (c) def caller() -> Int: foo(5)
val d2v_caller = d2var_new2_name(loc, symbl_make_name("caller"))
val () = tr12env_add0_d2var(env, d2v_caller)
val cf2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
val csres = S2RESsome(S2EFFnone(), s2e_int)
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, cf2as)
val call_foo =
  d2exp_make_node(loc, D2Edapp(resolve_callee(env, loc, "foo"), (-1), list_sing(d2e_int(loc, "5"))))
val () = tr12env_poplam0(env)
val d2f_caller =
  d2fundcl_make_args
    (loc, d2v_caller, cf2as, csres, TEQD2EXPsome(tok_val(loc), call_foo), WTHS2EXPnone())
val decl_caller =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_caller)))
//
val decls = list_cons(decl_extern, list_cons(decl_impl, list_sing(decl_caller)))
val t2penv = tr12env_free_top(env)
val dpar =
  d2parsed_make_args
  ( 1(*dynamic*), 0(*nerror*), LCSRCnone0()
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
in
  dpar
end
//
(* ****** ****** *)
//
// ============ CASE (4): OVERLOAD =============================================
//   def my_show(x: Int) -> Int: x
//   overload show with my_show      (#symload show with my_show)
//   def caller2() -> Int: show(7)
//
fun
build_case_overload((*void*)): d2parsed = let
//
val loc = loctn_dummy()
val env = tr12env_make_nil()
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// (a) def my_show(x:Int)->Int: x   — registers `my_show` as a d2cst-ish.
val decl_myshow =
  build_def_intfun(env, loc, "my_show", s2e_int,
    lam(env2, d2v_x) => d2exp_make_node(loc, D2Evar(d2v_x)))
//
// (b) overload `show` onto `my_show`: resolve the IMPL d2itm, wrap as d2ptm, register a
//     D2ITMsym bucket under `show` (the load-bearing step), emit D2Csymload.
val sym_show = symbl_make_name("show")
val implopt = tr12env_find_d2itm(env, symbl_make_name("my_show"))
val decl_ovl =
  (
  case+ implopt of
  | ~optn_vt_cons(ditm_impl) => let
      val dptm = D2PTMsome(0(*pval*), ditm_impl)
      // merge with any existing bucket under `show`.
      val d2ps =
        (
        case+ tr12env_find_d2itm(env, sym_show) of
        | ~optn_vt_nil() => list_nil()
        | ~optn_vt_cons(other) =>
          (case+ other of
           | D2ITMsym(_, ps) => ps
           | _ => list_sing(D2PTMsome(0, other)))
        ): list(d2ptm)
      val ditm_show = D2ITMsym(sym_show, list_cons(dptm, d2ps))
      val () = tr12env_add0_d2itm(env, sym_show, ditm_show)   // *** makes `show` resolve ***
      val tknd = token_make_node(loc, T_VAL(VLKval))          // a benign token slot
    in
      d2ecl_make_node(loc, D2Csymload(tknd, sym_show, dptm))
    end
  | ~optn_vt_nil() => d2ecl_make_node(loc, D2Cnone0())
  ): d2ecl
//
// (c) def caller2() -> Int: show(7)   — `show` must now resolve to `my_show`.
val d2v_caller2 = d2var_new2_name(loc, symbl_make_name("caller2"))
val () = tr12env_add0_d2var(env, d2v_caller2)
val cf2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
val csres = S2RESsome(S2EFFnone(), s2e_int)
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, cf2as)
val call_show =
  d2exp_make_node(loc, D2Edapp(resolve_callee(env, loc, "show"), (-1), list_sing(d2e_int(loc, "7"))))
val () = tr12env_poplam0(env)
val d2f_caller2 =
  d2fundcl_make_args
    (loc, d2v_caller2, cf2as, csres, TEQD2EXPsome(tok_val(loc), call_show), WTHS2EXPnone())
val decl_caller2 =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_caller2)))
//
val decls = list_cons(decl_myshow, list_cons(decl_ovl, list_sing(decl_caller2)))
val t2penv = tr12env_free_top(env)
val dpar =
  d2parsed_make_args
  ( 1(*dynamic*), 0(*nerror*), LCSRCnone0()
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
in
  dpar
end
//
(* ****** ****** *)
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
mymain_surf1((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYB_log("######## SURF1 (implement + overload) GATING SPIKE ########")
//
val () = PYB_log("[case 3] implement: extern def foo(x:Int)->Int ; implement foo(x): x+x ; caller()=foo(5)")
val n3 = run_case("implement", build_case_implement())
//
val () = PYB_log("[case 4] overload: def my_show(x:Int)->Int: x ; overload show with my_show ; caller2()=show(7)")
val n4 = run_case("overload", build_case_overload())
//
val () = (if n3 = 0 then PYB_log("RESULT case3: GO (implement typechecks, nerror=0)")
          else PYB_log("RESULT case3: NO-GO (implement nerror != 0)"))
val () = (if n4 = 0 then PYB_log("RESULT case4: GO (overload typechecks, nerror=0)")
          else PYB_log("RESULT case4: NO-GO (overload nerror != 0)"))
//
in
  if (n3 = 0) then
    (if n4 = 0 then PYB_log("RESULT: PASS (both implement + overload typecheck, nerror=0)")
     else PYB_log("RESULT: PARTIAL (case3 GO, case4 NO-GO — see f3perr0 above)"))
  else
    (if n4 = 0 then PYB_log("RESULT: PARTIAL (case4 GO, case3 NO-GO — see f3perr0 above)")
     else PYB_log("RESULT: FAIL (both NO-GO)"))
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_surf1()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_surf1_spike.dats]
*)
