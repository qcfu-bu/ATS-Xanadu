(* ****** ****** *)
(*
** ARROW-EFFECTS (bootstrap P1, feature 2) STAGE-0 SPIKE driver.
**
** Hand-builds at L2 (NO surface, NO lexer/parser) a small program per probe and runs it through
** the real stock pipeline trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a, then prints the
** post-tread3a nerror. EACH probe runs in its OWN node process (PROBE selector) so a hard
** XATS000_cfail is ISOLATED.
**
** GOAL: determine which f2clknd (function CLASS) a surface arrow tag must lower to, and whether
** the classes are STRUCTURALLY DISTINGUISHED at L2.  Background facts (xbasics.sats:272-306):
**   F2CLfun        = CXFREF = ~1  : code-ptr-refd, NONLINEAR boxed closure  (= cloref; bare `->`)
**   F2CLclo(knd)   : closure;  knd = ~1 ref / 1 ptr / 0 flt   (all LINEAR per the HX note)
**   s2exp_fun1_full(f2cl, npf, args, res) is the class-aware maker; nil0/all1 both pin F2CLfun.
**   The result SORT is the_sort2_vtbx when f2clknd_linq(f2cl) else the_sort2_tbox (staexp2.dats
**   :1072-1077) — so the boxity/linearity IS reflected in the sort (NOT erased).
**
** Probes — each builds `fun useit(f: (Int) -><class> Int): Int = f(0)`, i.e. a HOF taking a
** function-typed PARAMETER and APPLYING it.  This is exactly the fixture shape (a HOF param).
**   AR-CLOREF  f2cl = F2CLfun         (bare `->`, cloref)   — the established GO baseline
**   AR-FUN     f2cl = F2CLclo(~1)?    — see note; `fun`/`fun0`/`fun1` is a flat code ptr
**   AR-CLO0    f2cl = F2CLclo(0)      (flat closure, `cloptr`-flat)
**   AR-CLO1    f2cl = F2CLclo(1)      (ptr closure, `cloptr`)
**   AR-CLOREFC f2cl = F2CLclo(~1)     (ref closure via F2CLclo, alt spelling of cloref)
** plus a DISTINCTION probe:
**   AR-DIST    a fn whose param expects a F2CLclo(1) (cloptr) is APPLIED to a value of type
**              F2CLfun (cloref) — does unify reject it?  (Is the class checked, or collapsed?)
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ or language-server/ is touched.
** Typecheck-only (no codegen).
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
fun
run_one(label: strn, decls: d2eclist, t2penv: d2topenv): sint = let
  val source = LCSRCnone0()
  val dpar =
    d2parsed_make_args
    ( 1(*stadyn:dynamic*), 0(*nerror*), source
    , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
//
  val dpar = d2parsed_of_trans2a(dpar)
  val ( ) = d2parsed_by_trsym2b(dpar)
  val dpar = d2parsed_of_t2read0(dpar)
  val dp3 = d3parsed_of_trans23(dpar)
  val dp3 = d3parsed_of_tread3a(dp3)
  val nerror = d3parsed_get_nerror(dp3)
  val () = PYB_log_int(label, nerror)
//
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dp3))
in
  nerror
end
//
(* ****** ****** *)
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
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2))
//
fun
resolve_var(env: !tr12env, loc: loctn, name: strn): d2exp = let
  val dopt = tr12env_find_d2itm(env, symbl_make_name(name))
in
  case+ dopt of
  | ~optn_vt_cons(d2i) =>
    (case+ d2i of
     | D2ITMvar(d2v) => d2exp_make_node(loc, D2Evar(d2v))
     | _ => d2exp_none0(loc))
  | ~optn_vt_nil() => d2exp_none0(loc)
end
//
fun d2e_int(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
//
(* ****** ****** *)
//
// build `fun useit(f: (Int) -><f2cl> Int): Int = f(0)` and run it.
// The fn-typed param `f` is built via s2exp_fun1_full(f2cl, npf, [Int], Int) — the class-aware
// maker; the body APPLIES f to 0 (D2Edapp), forcing the typechecker to treat `f` as a callable
// of the given class.  Returns nerror.
//
fun
probe_param(label: strn, f2cl: f2clknd): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//   the function-typed parameter:  (Int) -><class> Int
  val s2e_fn = s2exp_fun1_full(f2cl, (-1)(*npf*), list_sing(s2e_int), s2e_int)
//
  val sym_useit = symbl_make_name("useit")
  val d2v_useit = d2var_new2_name(loc, sym_useit)
  val () = tr12env_add0_d2var(env, d2v_useit)
//
  val d2v_f = d2var_new2_name(loc, symbl_make_name("f"))
  val pat_f = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_f), s1exp_none0(loc), s2e_fn))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_f)))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//   body:  f(0)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_f = resolve_var(env, loc, "f")
  val d2body =
    d2exp_make_node(loc, D2Edapp(d2e_f, (-1)(*npf*), list_sing(d2e_int(loc, "0"))))
  val () = tr12env_poplam0(env)
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_useit, f2as, sres,
       TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one(label, decls, t2penv)
end
//
(* ****** ****** *)
//
// DISTINCTION probe.  Build TWO defs:
//   fun mk(): (Int) -><CLO1=cloptr> Int = lam x => x      -- a producer of a cloptr fn
//   fun useref(f: (Int) -><FUN=cloref> Int): Int = f(0)   -- a consumer expecting cloref
//   fun main(): Int = useref(mk())                        -- pass cloptr where cloref expected
// If the class is checked, the call mismatches and nerror>0.  We REPORT the verdict.
// (We hand-build mk's body as a lambda of the cloptr class via d2exp_lam? — simpler: use a
//  bodyless extern-style cst carrying the producer type, then call it; the value it yields has
//  the cloptr type, which we then feed to useref.)
//
fun
probe_dist((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
//   producer type:  () -> ((Int) -<cloptr=F2CLclo(1)> Int)
  val s2e_cloptr = s2exp_fun1_full(F2CLclo(1), (-1), list_sing(s2e_int), s2e_int)
//   consumer's param type: (Int) -<cloref=F2CLfun> Int
  val s2e_cloref = s2exp_fun1_full(F2CLfun(), (-1), list_sing(s2e_int), s2e_int)
//
//   extern producer:  fun mkclo(): (Int) -<cloptr> Int
  val tok_mk = token_make_node(loc, T_IDALP("mkclo"))
  val sfun_mk = s2exp_fun1_nil0((-1), list_nil(), s2e_cloptr)
  val tok_dyncst = token_make_node(loc, T_FUN(FNKfn2))
  val d2c_mk = d2cst_make_idtp(tok_dyncst, tok_mk, list_nil()(*tqas*), sfun_mk)
  val () = tr12env_add1_d2cst(env, d2c_mk)
  val dcdcl_mk =
    d2cstdcl_make_args(loc, d2c_mk, list_nil(), S2RESnone(), TEQD2EXPnone())
  val dyncst_mk =
    d2ecl_make_node(loc, D2Cdynconst(tok_dyncst, list_nil(), list_sing(dcdcl_mk)))
  val tok_extern = token_make_node(loc, T_SRP_EXTERN())
  val externdecl = d2ecl_make_node(loc, D2Cextern(tok_extern, dyncst_mk))
//
//   consumer:  fun useref(f: (Int) -<cloref> Int): Int = f(0)
  val sym_useref = symbl_make_name("useref")
  val d2v_useref = d2var_new2_name(loc, sym_useref)
  val () = tr12env_add0_d2var(env, d2v_useref)
  val d2v_f = d2var_new2_name(loc, symbl_make_name("f"))
  val pat_f = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_f), s1exp_none0(loc), s2e_cloref))
  val f2as_ref = list_sing(f2arg_make_node(loc, F2ARGdapp(0, list_sing(pat_f)))) : f2arglst
  val sres_ref = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as_ref)
  val d2e_f = resolve_var(env, loc, "f")
  val body_ref =
    d2exp_make_node(loc, D2Edapp(d2e_f, (-1), list_sing(d2e_int(loc, "0"))))
  val () = tr12env_poplam0(env)
  val d2f_ref =
    d2fundcl_make_args
      (loc, d2v_useref, f2as_ref, sres_ref,
       TEQD2EXPsome(tok_val(loc), body_ref), WTHS2EXPnone())
  val urefdecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_ref)))
//
//   main:  fun callit(): Int = useref(mkclo())
  val sym_callit = symbl_make_name("callit")
  val d2v_callit = d2var_new2_name(loc, sym_callit)
  val () = tr12env_add0_d2var(env, d2v_callit)
  val f2as_main = list_sing(f2arg_make_node(loc, F2ARGdapp(0, list_nil()))) : f2arglst
  val sres_main = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as_main)
  val d2e_useref = resolve_var(env, loc, "useref")
  val d2e_mk =
    (case+ tr12env_find_d2itm(env, symbl_make_name("mkclo")) of
     | ~optn_vt_cons(d2i) =>
       (case+ d2i of
        | D2ITMcst(d2cs) =>
            if list_nilq(d2cs) then d2exp_none0(loc)
            else d2exp_make_node(loc, D2Ecst(d2cs.head()))
        | _ => d2exp_none0(loc))
     | ~optn_vt_nil() => d2exp_none0(loc)) : d2exp
//   the cloptr value:  mkclo()
  val d2_clovalue =
    d2exp_make_node(loc, D2Edapp(d2e_mk, (-1), list_nil()))
//   feed it to useref (expects cloref):  useref(mkclo())
  val body_main =
    d2exp_make_node(loc, D2Edapp(d2e_useref, (-1), list_sing(d2_clovalue)))
  val () = tr12env_poplam0(env)
  val d2f_main =
    d2fundcl_make_args
      (loc, d2v_callit, f2as_main, sres_main,
       TEQD2EXPsome(tok_val(loc), body_main), WTHS2EXPnone())
  val maindecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f_main)))
//
  val decls = list_cons(externdecl, list_cons(urefdecl, list_sing(maindecl)))
  val t2penv = tr12env_free_top(env)
in
  run_one("[AR-DIST] useref(mkclo()): pass cloptr where cloref expected  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// negative knd helper (avoids the `~1` token in expr position).
fun f2cl_cloref_clo(): f2clknd = F2CLclo(0 - 1)
//
fun
mymain_arrow((*void*)): void = let
  val () = PYB_log("######## BEGIN ARROW SPIKE ########")
  val sel = PYB_probe()
  val () =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE AR-CLOREF (F2CLfun, bare ->) ----")
                 val _ = probe_param("[AR-CLOREF] useit(f:(Int)-<F2CLfun>Int):Int=f(0)  nerror=",
                                     F2CLfun()) in () end
      | 2 => let val () = PYB_log("---- PROBE AR-CLOREFC (F2CLclo(-1), ref) ----")
                 val _ = probe_param("[AR-CLOREFC] useit(f:(Int)-<F2CLclo(-1)>Int):Int=f(0)  nerror=",
                                     f2cl_cloref_clo()) in () end
      | 3 => let val () = PYB_log("---- PROBE AR-CLO0 (F2CLclo(0), flat) ----")
                 val _ = probe_param("[AR-CLO0] useit(f:(Int)-<F2CLclo(0)>Int):Int=f(0)  nerror=",
                                     F2CLclo(0)) in () end
      | 4 => let val () = PYB_log("---- PROBE AR-CLO1 (F2CLclo(1), ptr/cloptr) ----")
                 val _ = probe_param("[AR-CLO1] useit(f:(Int)-<F2CLclo(1)>Int):Int=f(0)  nerror=",
                                     F2CLclo(1)) in () end
      | 5 => let val () = PYB_log("---- PROBE AR-DIST (cloptr vs cloref distinction) ----")
                 val _ = probe_dist() in () end
      | _ => let
                 val () = PYB_log("---- AR-CLOREF ----")
                 val _ = probe_param("[AR-CLOREF] F2CLfun  nerror=", F2CLfun())
                 val () = PYB_log("---- AR-CLOREFC ----")
                 val _ = probe_param("[AR-CLOREFC] F2CLclo(-1)  nerror=", f2cl_cloref_clo())
                 val () = PYB_log("---- AR-CLO0 ----")
                 val _ = probe_param("[AR-CLO0] F2CLclo(0)  nerror=", F2CLclo(0))
                 val () = PYB_log("---- AR-CLO1 ----")
                 val _ = probe_param("[AR-CLO1] F2CLclo(1)  nerror=", F2CLclo(1))
                 val () = PYB_log("---- AR-DIST ----")
                 val _ = probe_dist()
              in () end
    ) : void
in
  PYB_log("######## END ARROW SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_arrow()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_arrow_spike.dats]
*)
