(* ****** ****** *)
(*
** A-TEMPLATE GATING SPIKE driver.
**
** Hand-builds at L2 (NO surface, NO lexer/parser) the smallest ATS-template
** constructs and runs each probe through the real stock pipeline
**   trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a
** then prints the post-tread3a nerror. EACH probe is an INDEPENDENT d2parsed
** in its OWN node process (PYB_probe selector) so a hard XATS000_cfail is ISOLATED.
**
** The make-or-break question (#4): template RESOLUTION (monomorphization / picking
** the matching implement body) happens in trtmp3b/trtmp3c, which run AFTER tread3a
** (the error-counting pass). So a DECLARED + INSTANTIATED but NOT-codegen'd template
** should reach nerror=0 structurally. These probes verify that.
**
** Probes:
**   T1  template DECLARATION    extern fun{a:t@ype} id(x:a):a   (d2cst with non-empty tqas,
**                               wrapped in D2Cdynconst + D2Cextern; d2cst_tempq = true)
**   T2  template BODY           T1 + implement{a} id(x) = x      (D2Cimplmnt0 carrying the
**                               inherited tqas + an empty tias)
**   T3  template INSTANTIATION  T1 + T2 + def main() = id<int>(5)  (D2Edapp(D2Etapp(cst id,
**                               [int]), [5]) — the foo<Int>(args) use node)
**   T4  BOTH BRACKETS coexist   extern fun{a:t@ype} foo{c:type}(x:a, y:c):c  (a TEMPLATE-arg
**                               list `{a}` AND a polymorphic `tqas`-style universal `{c}` in the
**                               fn type) + an instantiation foo<int>(5, True)
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ or language-server/
** is modified. Typecheck-only (no codegen).
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
#extern fun PYB_probe((*void*)): sint = $extnam()
//
(* ****** ****** *)
//
// resolve a (prelude) static type NAME to its s2exp (head s2cst on hit).
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
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2))
//
fun d2e_int(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
//
// resolve a NAME used as a CALLABLE -> a d2exp_cst (def/extern). Needed so id<int>
// resolves to the (template) d2cst the extern registered.
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
// look up the (template) d2cst the extern registered, by name (so the implement +
// instantiation can attach to the SAME d2cst).
fun
find_d2cst(env: !tr12env, name: strn): optn(d2cst) =
  (
  case+ tr12env_find_d2itm(env, symbl_make_name(name)) of
  | ~optn_vt_cons(d2i) =>
    (case+ d2i of
     | D2ITMcst(d2cs) => (if list_nilq(d2cs) then optn_nil() else optn_cons(d2cs.head()))
     | _ => optn_nil())
  | ~optn_vt_nil() => optn_nil()
  ): optn(d2cst)
//
(* ****** ****** *)
//
// the shared pipeline runner: build a d2parsed from decls+t2penv, push it through the
// REAL stock passes, and report `nerror (after tread3a)`.
fun
run_one(label: strn, decls: d2eclist, t2penv: d2topenv): sint = let
  val source = LCSRCnone0()
  val dpar =
    d2parsed_make_args
    ( 1(*stadyn:dynamic*), 0(*nerror*), source
    , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
//
  val dpar = d2parsed_of_trans2a(dpar)
  val () = PYB_log("  trans2a done")
  val ( ) = d2parsed_by_trsym2b(dpar)
  val () = PYB_log("  trsym2b done")
  val dpar = d2parsed_of_t2read0(dpar)
  val () = PYB_log("  t2read0 done")
  val dp3 = d3parsed_of_trans23(dpar)
  val () = PYB_log("  trans23 done")
  val dp3 = d3parsed_of_tread3a(dp3)
  val nerror = d3parsed_get_nerror(dp3)
  val () = PYB_log_int(label, nerror)
//
  // always dump f3perr0 so a non-zero count is explained.
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dp3))
in
  nerror
end
//
(* ****** ****** *)
//
// build + REGISTER a TEMPLATE `extern fun{a:t@ype} id(x:a):a` bodyless d2cst.
//   * make a fresh s2var `a` at sort t@ype (the_sort2_tflt is the flat `t@ype`; we use
//     the_sort2_type — a BOXED template param — to keep the fn type boxed/erasable;
//     a flat param would need the unboxed-instantiation work, out of scope here).
//   * the fn type is (a) -> a referencing that s2var.
//   * tqas = [ t2qag_make_s2vs(loc, [a]) ]  — ONE template-quantifier-arg group, the `{a}`.
//   * d2cst_make_idtp(tok_fun, tok_id, tqas, sfun) — a NON-EMPTY tqas makes d2cst_tempq=true.
//   * register via tr12env_add1_d2cst, wrap in D2Cdynconst(tok_fun, tqas, [dcdcl]) then D2Cextern.
// Returns (the D2Cextern decl, the template d2cst, the s2var a) so the implement can reuse them.
fun
build_template_id
  (env: !tr12env, loc: loctn): (d2ecl, d2cst, s2var) = let
  val s2v_a   = s2var_make_idst(symbl_make_name("a"), the_sort2_type)
  val s2e_a   = s2exp_var(s2v_a)
  val argtyps = list_sing(s2e_a)
  val sfun    = s2exp_fun1_nil0((-1)(*npf*), argtyps, s2e_a)
  val tqa     = t2qag_make_s2vs(loc, list_sing(s2v_a))
  val tqas    = list_sing(tqa)
  val tok_id  = token_make_node(loc, T_IDALP("id"))
  val tok_fnk = token_make_node(loc, T_FUN(FNKfn2))
  val d2c     = d2cst_make_idtp(tok_fnk, tok_id, tqas, sfun)
  val () = tr12env_add1_d2cst(env, d2c)               // register so `id` resolves
  val dcdcl   = d2cstdcl_make_args(loc, d2c, list_nil()(*darg*), S2RESnone(), TEQD2EXPnone())
  val dyncst  = d2ecl_make_node(loc, D2Cdynconst(tok_fnk, tqas, list_sing(dcdcl)))
  val tok_ext = token_make_node(loc, T_SRP_EXTERN())
  val decl    = d2ecl_make_node(loc, D2Cextern(tok_ext, dyncst))
in
  (decl, d2c, s2v_a)
end
//
(* ****** ****** *)
//
// ===== T1 : template DECLARATION only =========================================
//   extern fun{a:t@ype} id(x:a):a
fun
probe_T1((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val (decl_ext, _d2c, _s2v) = build_template_id(env, loc)
  val decls = list_sing(decl_ext)
  val t2penv = tr12env_free_top(env)
in
  run_one("  nerror (after tread3a) =", decls, t2penv)
end
//
(* ****** ****** *)
//
// build the `implement{a} id(x) = x` decl, given the pre-declared template d2cst.
//   * dimp = DIMPLone1(d2c) — the resolved template d2cst,
//   * the implement INHERITS the d2cst's template quantifier args (d2cst_get_tqas);
//     we build a fresh s2var `a'` for the implement scope and bind it as the tqas group
//     so the body's `x:a'` matches. (Mirrors trans12 f0_implmnt0_dimp's trans12_t1qaglst_wth,
//     which threads the declared tqas into a fresh impl-side quantifier group.)
//   * tias = list_nil() — a bare `implement{a}` carries NO instantiation type-args
//     (those are the `@impl[Int]` brackets; here the impl is the GENERIC body).
//   * f2as = [ x : a' ] ; body = x.
fun
build_implement_id
  (env: !tr12env, loc: loctn, d2c: d2cst): d2ecl = let
  val dimp = dimpl_make_node(loc, DIMPLone1(d2c))
  val tknd = token_make_node(loc, T_IMPLMNT(IMPLfun()))
  // a fresh impl-side template-quantifier group bound to the SAME shape as the decl's `{a}`.
  val s2v_a = s2var_make_idst(symbl_make_name("a"), the_sort2_type)
  val s2e_a = s2exp_var(s2v_a)
  val tqa   = t2qag_make_s2vs(loc, list_sing(s2v_a))
  val tqas  = list_sing(tqa)
  // the param pattern x : a'
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val pat_x = d2pat_var(loc, d2v_x)
  val pat_x_ann = d2pat_make_node(loc, D2Pannot(pat_x, s1exp_none0(loc), s2e_a))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_x_ann))))
  // bind the tqas-var + the param, build body `x`, pop.
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_tqas(env, tqas)
  val () = tr12env_add0_f2arglst(env, f2as)
  val body = d2exp_make_node(loc, D2Evar(d2v_x))
  val () = tr12env_poplam0(env)
in
  d2ecl_make_node
    (loc, D2Cimplmnt0(tknd, list_nil()(*sqas*), tqas,
                      dimp, list_nil()(*tias*), f2as, S2RESnone(), body))
end
//
// ===== T2 : template DECLARATION + BODY =======================================
//   extern fun{a:t@ype} id(x:a):a
//   implement{a} id(x) = x
fun
probe_T2((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val (decl_ext, d2c, _s2v) = build_template_id(env, loc)
  val decl_impl = build_implement_id(env, loc, d2c)
  val decls = list_cons(decl_ext, list_sing(decl_impl))
  val t2penv = tr12env_free_top(env)
in
  run_one("  nerror (after tread3a) =", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== T3 : template DECL + BODY + INSTANTIATION ==============================
//   extern fun{a:t@ype} id(x:a):a
//   implement{a} id(x) = x
//   def main() -> Int: id<int>(5)
// the instantiation node: D2Edapp(D2Etapp(d2exp_cst(id), [int]), -1, [5]).
fun
probe_T3((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
  val (decl_ext, d2c, _s2v) = build_template_id(env, loc)
  val decl_impl = build_implement_id(env, loc, d2c)
  //
  // def main() -> Int: id<int>(5)
  val d2v_main = d2var_new2_name(loc, symbl_make_name("main"))
  val () = tr12env_add0_d2var(env, d2v_main)
  val cf2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
  val csres = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, cf2as)
  // id<int> : a TEMPLATE-INSTANTIATION expr (D2Etapp) over the template callee.
  val callee   = resolve_callee(env, loc, "id")
  val id_atint = d2exp_tapp(loc, callee, list_sing(s2e_int))     // id<int>
  val call     = d2exp_make_node(loc, D2Edapp(id_atint, (-1), list_sing(d2e_int(loc, "5"))))
  val () = tr12env_poplam0(env)
  val d2f_main =
    d2fundcl_make_args(loc, d2v_main, cf2as, csres, TEQD2EXPsome(tok_val(loc), call), WTHS2EXPnone())
  val decl_main =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_main)))
  //
  val decls = list_cons(decl_ext, list_cons(decl_impl, list_sing(decl_main)))
  val t2penv = tr12env_free_top(env)
in
  run_one("  nerror (after tread3a) =", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== T4 : BOTH BRACKETS coexist =============================================
//   extern fun{a:t@ype} foo{c:type}(x:a, y:c):c
//   implement{a} foo{c}(x, y) = y
//   def main2() -> Int: foo<int>(5, 7)
// The d2cst's tqas carries the TEMPLATE `{a}` group; the fn type itself is universally
// quantified over the POLYMORPHIC `{c}` (an s2exp_uni0). Both coexist on one d2cst.
fun
build_template_foo
  (env: !tr12env, loc: loctn): (d2ecl, d2cst) = let
  val s2v_a = s2var_make_idst(symbl_make_name("a"), the_sort2_type)   // TEMPLATE param
  val s2v_c = s2var_make_idst(symbl_make_name("c"), the_sort2_type)   // POLYMORPHIC param
  val s2e_a = s2exp_var(s2v_a)
  val s2e_c = s2exp_var(s2v_c)
  // the inner fn type (x:a, y:c) -> c
  val argtyps = list_cons(s2e_a, list_sing(s2e_c))
  val sfun0   = s2exp_fun1_nil0((-1)(*npf*), argtyps, s2e_c)
  // wrap in a UNIVERSAL over c: {c:type} ((a,c)->c)  — the polymorphic `tqas` quantifier.
  // s2exp_uni0 takes a flat s2varlst (the dep-spike P2 recipe), not an s2qag.
  val sfun    = s2exp_uni0(list_sing(s2v_c), list_nil()(*s2ps*), sfun0)
  // the TEMPLATE quantifier group {a} on the d2cst.
  val tqa     = t2qag_make_s2vs(loc, list_sing(s2v_a))
  val tqas    = list_sing(tqa)
  val tok_id  = token_make_node(loc, T_IDALP("foo"))
  val tok_fnk = token_make_node(loc, T_FUN(FNKfn2))
  val d2c     = d2cst_make_idtp(tok_fnk, tok_id, tqas, sfun)
  val () = tr12env_add1_d2cst(env, d2c)
  val dcdcl   = d2cstdcl_make_args(loc, d2c, list_nil()(*darg*), S2RESnone(), TEQD2EXPnone())
  val dyncst  = d2ecl_make_node(loc, D2Cdynconst(tok_fnk, tqas, list_sing(dcdcl)))
  val tok_ext = token_make_node(loc, T_SRP_EXTERN())
  val decl    = d2ecl_make_node(loc, D2Cextern(tok_ext, dyncst))
in
  (decl, d2c)
end
//
fun
probe_T4((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
  val (decl_ext, _d2c) = build_template_foo(env, loc)
  //
  // def main2() -> Int: foo<int>(5, 7)   — instantiate the TEMPLATE bracket `{a}` with int;
  //   the polymorphic `{c}` is inferred from the value args, as polymorphic args always are.
  val d2v_main = d2var_new2_name(loc, symbl_make_name("main2"))
  val () = tr12env_add0_d2var(env, d2v_main)
  val cf2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
  val csres = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, cf2as)
  val callee   = resolve_callee(env, loc, "foo")
  val foo_atint = d2exp_tapp(loc, callee, list_sing(s2e_int))    // foo<int>
  val call =
    d2exp_make_node
      (loc, D2Edapp(foo_atint, (-1), list_cons(d2e_int(loc, "5"), list_sing(d2e_int(loc, "7")))))
  val () = tr12env_poplam0(env)
  val d2f_main =
    d2fundcl_make_args(loc, d2v_main, cf2as, csres, TEQD2EXPsome(tok_val(loc), call), WTHS2EXPnone())
  val decl_main =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_main)))
  //
  val decls = list_cons(decl_ext, list_sing(decl_main))
  val t2penv = tr12env_free_top(env)
in
  run_one("  nerror (after tread3a) =", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== T5 (NEGATIVE CONTROL) : type-MISMATCHED instantiation ==================
//   extern fun{a:t@ype} id(x:a):a
//   implement{a} id(x) = x
//   def main3() -> Int: id<int>("hi")   <-- "hi" : string, but arg expects a=int
// Confirms that tread3a ACTUALLY type-checks the instantiated arg against the
// substituted template type (so T3's nerror=0 is meaningful, not a no-op). EXPECT nerror>0.
// A string literal (D2Estr, token-based) is stamped `string` by trans2a's literal-type pass,
// so the int-vs-string clash is an UNAMBIGUOUS template-arg mismatch (not an unstamped-node noise).
fun
d2e_str(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Estr(token_make_node(loc, T_STRN1_clsd(s, strn_length(s)))))
//
fun
probe_T5((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
  val (decl_ext, d2c, _s2v) = build_template_id(env, loc)
  val decl_impl = build_implement_id(env, loc, d2c)
  val d2v_main = d2var_new2_name(loc, symbl_make_name("main3"))
  val () = tr12env_add0_d2var(env, d2v_main)
  val cf2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
  val csres = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, cf2as)
  val callee   = resolve_callee(env, loc, "id")
  val id_atint = d2exp_tapp(loc, callee, list_sing(s2e_int))      // id<int>
  // pass a string literal where int is required.
  val call     = d2exp_make_node(loc, D2Edapp(id_atint, (-1), list_sing(d2e_str(loc, "hi"))))
  val () = tr12env_poplam0(env)
  val d2f_main =
    d2fundcl_make_args(loc, d2v_main, cf2as, csres, TEQD2EXPsome(tok_val(loc), call), WTHS2EXPnone())
  val decl_main =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_main)))
  val decls = list_cons(decl_ext, list_cons(decl_impl, list_sing(decl_main)))
  val t2penv = tr12env_free_top(env)
in
  run_one("  nerror (after tread3a) =", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_atmpl((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## A-TEMPLATE GATING SPIKE ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- T1 (template DECL: extern fun{a} id(x:a):a) ----")
                 val _ = probe_T1() in 0 end
      | 2 => let val () = PYB_log("---- T2 (template DECL + BODY: implement{a} id(x)=x) ----")
                 val _ = probe_T2() in 0 end
      | 3 => let val () = PYB_log("---- T3 (DECL + BODY + INSTANTIATION: id<int>(5)) ----")
                 val _ = probe_T3() in 0 end
      | 4 => let val () = PYB_log("---- T4 (BOTH brackets: extern fun{a} foo{c}(x:a,y:c):c + foo<int>(5,7)) ----")
                 val _ = probe_T4() in 0 end
      | 5 => let val () = PYB_log("---- T5 (NEG CONTROL: id<int>(True) — type-mismatched arg; EXPECT nerror>0) ----")
                 val _ = probe_T5() in 0 end
      | _ => let val () = PYB_log("---- T1 ----") val _ = probe_T1()
                 val () = PYB_log("---- T2 ----") val _ = probe_T2()
                 val () = PYB_log("---- T3 ----") val _ = probe_T3()
                 val () = PYB_log("---- T4 ----") val _ = probe_T4()
                 val () = PYB_log("---- T5 ----") val _ = probe_T5()
              in 0 end
    ) : sint
in
  PYB_log("######## END A-TEMPLATE SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_atmpl()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_atmpl_spike.dats]
*)
