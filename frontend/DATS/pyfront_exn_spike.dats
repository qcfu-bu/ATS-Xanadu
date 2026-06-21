(* ****** ****** *)
(*
** EXCEPTIONS GATING SPIKE — characterizes the TYPECHECK behavior of hand-built
** L2 exception machinery BEFORE the Python surface is wired. Proves three
** constructions typecheck end-to-end to nerror=0 through the stock passes:
**
**   (1) an EXCEPTION-CONSTRUCTOR declaration `exception MyExn of (Int)` —
**       a D2Cexcptcon whose d2con is a constructor of the built-in `exn` type
**       (the_s2cst_excptn, sort the_sort2_vtbx — a LINEAR/viewtype). Built
**       EXACTLY as the stock f0_excptcon (trans12_decl00.dats:3084): a
**       d2con_make_idtp over s2cst=the_s2cst_excptn(), con-fun result type
**       s2exp_cst(the_s2cst_excptn()), tag STAYS -1 (NOT a datatype positional
**       tag), then tr12env_add1_d2conlst to register it.
**   (2) a `raise` — D2Eraise(T_DLR_RAISE, e) where e : exn. trans23 f0_raise
**       typechecks e against the_s2typ_excptn() and gives the whole raise a
**       FRESH type var (s2typ_new0_x2tp) — raise has any type / does not return.
**   (3) a `try ... with` — D2Etry0(T_TRY, body, clauses). trans23 f0_try0
**       typechecks body -> tres, then the clauses as case-arms over a synthetic
**       exn-typed scrutinee, each branch unifying to tres. The clauses are
**       ordinary d2cls (reusing the match-clause machinery): `MyExn(x) => x`
**       and a catch-all `_ => 0`.
**
** The whole program built here is morally:
**
**     exception MyExn of (Int)
**     def f() -> Int:
**         try:
**             raise MyExn(5)
**         except MyExn(x):
**             x
**         except _:
**             0
**
** RECIPE MIRRORED FROM the proven datatype spike pyfront_m5b_spike.dats. ONLY
** DELTAS: the con's s2cst is the_s2cst_excptn() (not a fresh datatype s2cst);
** tag stays -1; the decl is D2Cexcptcon (not D2Cdatatype); the body uses
** D2Eraise + D2Etry0 (not a plain match).
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ or
** language-server/ is modified. Typecheck-only (no codegen).
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
// resolve a (prelude) static type NAME to its s2exp (the_s2exp_sint0 = the M5a
// direct Int that int literals/annotations carry). Same as the proven spikes.
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
// build the d2parsed: exception decl + a function that raises & catches it.
//
fun
build_d2parsed((*void*)): d2parsed = let
//
val loc = loctn_dummy()
//
val env = tr12env_make_nil()
//
// ===== exception MyExn of (Int) ===============================================
//
// Int's s2exp for the con argument (the prelude internal sint, M5a alias target).
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// the EXN type itself (result type of the con-fun). EXACTLY as f0_excptcon:
//   s2c0 = the_s2cst_excptn() ;  con result = s2exp_cst(s2c0).
val s2c_exn = the_s2cst_excptn()
val s2e_exn = s2exp_cst(s2c_exn)
//
// the constructor `MyExn` : (Int) -> exn. d2con_make_idtp needs a T_IDALP name.
val tok_myexn = token_make_node(loc, T_IDALP("MyExn"))
val sexp_myexn = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_int), s2e_exn)
val d2c_myexn = d2con_make_idtp(tok_myexn, list_nil()(*tqas*), sexp_myexn)
//
// f0_excptcon comment: "The tags of d2cs should stay (-1)" — so we do NOT call
// d2con_set_ctag. Register the con into the env exactly like f0_excptcon does
// (tr12env_add1_d2conlst), so `raise MyExn` / `except MyExn` resolve.
val d2cs_exn = list_sing(d2c_myexn)
val () = tr12env_add1_d2conlst(env, d2cs_exn)
//
// the D2Cexcptcon decl. FIRST field is a level-1 d1ecl — VESTIGIAL for typecheck
// (trans23 f0_excptcon binds it but never reads it), so a dummy is safe.
val excdecl =
  d2ecl_make_node(loc, D2Cexcptcon(d1ecl_none0(loc), d2cs_exn))
//
// ===== def f() -> Int: try (raise MyExn(5)) with MyExn(x) => x | _ => 0 ========
//
// bind the fun NAME first (a def group is recursive).
val sym_f = symbl_make_name("f")
val d2v_f = d2var_new2_name(loc, sym_f)
val () = tr12env_add0_d2var(env, d2v_f)
//
// f takes no args -> a single empty F2ARGdapp (the unit param `()`).
val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
val sres = S2RESsome(S2EFFnone(), s2e_int)
//
// enter the fun scope, bind params (none), build the body, pop.
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as)
//
// ---- the body `try: raise MyExn(5)  except MyExn(x): x  except _: 0` ----------
//
// the TRY body: `raise MyExn(5)`.
//   the con application MyExn(5): D2Edapp(D2Econ(MyExn), -1, [5]) — apply the
//   constructor function to the int literal. Then wrap in D2Eraise.
val d2e_con = d2exp_make_node(loc, D2Econ(d2c_myexn))
val d2e_five = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("5"))))
val d2e_app = d2exp_make_node(loc, D2Edapp(d2e_con, (-1)(*npf*), list_sing(d2e_five)))
val tok_raise = token_make_node(loc, T_DLR_RAISE())
val d2e_raise = d2exp_make_node(loc, D2Eraise(tok_raise, d2e_app))
//
// ---- the WITH clauses (case-arms over the caught exn) -------------------------
//
// arm 1 : `MyExn(x) => x` — a UNARY con-application pattern D2Pdapp(con, -1, [x]);
//         the binder `x` is visible to the body, which is just `x`.
val arm1 = let
  val phd = d2pat_con(loc, d2c_myexn)
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val pat_x = d2pat_var(loc, d2v_x)
  val d2p = d2pat_make_node(loc, D2Pdapp(phd, (-1), list_sing(pat_x)))
  val dgpt = d2gpt_make_node(loc, D2GPTpat(d2p))
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_d2gpt(env, dgpt)
  val body = resolve_var(env, loc, "x")
  val () = tr12env_poplam0(env)
in
  d2cls_make_node(loc, D2CLScls(dgpt, body))
end
//
// arm 2 : `_ => 0` — a wildcard catch-all. body is `0`.
val arm2 = let
  val d2p = d2pat_make_node(loc, D2Pany())
  val dgpt = d2gpt_make_node(loc, D2GPTpat(d2p))
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_d2gpt(env, dgpt)
  val body = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0"))))
  val () = tr12env_poplam0(env)
in
  d2cls_make_node(loc, D2CLScls(dgpt, body))
end
//
val dcls = list_cons(arm1, list_sing(arm2))
//
// the TRY expression: D2Etry0(T_TRY, body=raise, clauses).
val tok_try = token_make_node(loc, T_TRY())
val d2e_try = d2exp_make_node(loc, D2Etry0(tok_try, d2e_raise, dcls))
//
val () = tr12env_poplam0(env)  // exit the fun scope
//
val tok_val = token_make_node(loc, T_VAL(VLKval))
val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
//
val d2f =
  d2fundcl_make_args
    (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2e_try), WTHS2EXPnone())
val fundecl =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
//
// ===== assemble the d2parsed (excptcon decl + fun decl in ONE decl list) =======
//
val decls = list_cons(excdecl, list_sing(fundecl))
val t2penv = tr12env_free_top(env)
val source = LCSRCnone0()
//
val dpar =
  d2parsed_make_args
  ( 1(*stadyn:dynamic*), 0(*nerror*), source
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
//
in
  dpar
end // end of [build_d2parsed]
//
(* ****** ****** *)
//
fun
run_pipeline(dpar: d2parsed): d3parsed = let
  val dpar = d2parsed_of_trans2a(dpar)
  val () = PYB_log("[exn] trans2a (overload res) done")
  val ( ) = d2parsed_by_trsym2b(dpar)
  val () = PYB_log("[exn] trsym2b (symbol res) done")
  val dpar = d2parsed_of_t2read0(dpar)
  val () = PYB_log("[exn] t2read0 (L2 read/check) done")
  val dp3 = d3parsed_of_trans23(dpar)
  val () = PYB_log("[exn] trans23 (L2 -> L3) done")
in
  dp3
end
//
(* ****** ****** *)
//
fun
mymain_exn((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYB_log("######## EXCEPTIONS gating SPIKE ########")
val () = PYB_log("[exn] building `exception MyExn of (Int)` + f() raise/try at L2 ...")
val dpar = build_d2parsed()
val () = PYB_log("[exn] d2parsed built; running L2->L3 pipeline ...")
//
val dp3 = run_pipeline(dpar)
//
val dp3 = d3parsed_of_tread3a(dp3)
val nerror = d3parsed_get_nerror(dp3)
val () = PYB_log_int("[exn] nerror (after tread3a) =", nerror)
//
val out0 = g_stderr()
val () = PYB_log("[exn] -- f3perr0_d3parsed (stock reporter) --")
val () = f3perr0_d3parsed(out0, dp3)
//
in
  if nerror = 0 then
    PYB_log("RESULT: PASS (exception decl + raise + try/with typecheck, nerror=0)")
  else
    PYB_log("RESULT: FAIL (nerror != 0 ; see f3perr0 above)")
end // end of [mymain_exn]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_exn()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_exn_spike.dats]
*)
