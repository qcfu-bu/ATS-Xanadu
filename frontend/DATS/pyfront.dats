(* ****** ****** *)
(*
** M0a — Python-surface frontend: the typecheck-spine driver (DATS).
**
** Hand-builds (NO lexer/parser) an L2 `d2parsed` for the trivial DYNAMIC program
**
**     val x = 1
**     val y = x
**
** then drives it through the reused L2->L3 entry `d3parsed_of_trans23`, asserts
** `nerror = 0`, reports the L3 with the stock reporter `f3perr0_d3parsed`, and
** prints `nerror` to stdout. The WHOLE build-and-check is run TWICE in the same
** process to prove re-entrancy (plan §6.2): a fresh `tr12env` per check, no
** global mutation.
**
** PURELY ADDITIVE: nothing under srcgen2/ or language-server/ is modified; this
** only CALLS the compiler-as-a-library (linked from srcgen2/lib/lib2xatsopt.js).
**
** Mirrors: LOWERING-MAP §4 (templates C "val binding" & A "identifier ref"), §5
** (worked example), and srcgen2/DATS/trans12_decl00.dats `f0_valdclst`.
*)
(* ****** ****** *)
//
// The stock compiler front-end header: brings in xbasics (sint, valkind, FILR),
// xsymbol (symbl_make_name), trans01 (tr01env_make_nil/_free_top -> nil d1topenv),
// dynexp2 (d2parsed/d2exp/d2pat/d2ecl makers, d2var_new2_name, D2*-nodes,
// d2parsed_make_args), dynexp3 (d3parsed_get_nerror), trans12 (tr12env API),
// trans23 (d3parsed_of_trans23), f3perr0 (f3perr0_d3parsed), xglobal (the global
// bootstrap the_fxtyenv_pvsl00d / the_tr12env_pvsl00d), xatsopt.
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
//
// xatsopt_sats.hats + xatsopt_dpre.hats bring in the PRELUDE (gbas/gint/strn/...)
// SATS *and DATS* — i.e. the TEMPLATE IMPLEMENTATIONS for `=` (gint_eq$sint$sint),
// `prerrsln`/`proutsln` (gs_*), list ops, etc. WITHOUT these, a standalone driver
// transpiled by jsemit00 leaves those prelude templates UN-INSTANTIATED and every
// use is wrapped in a TIMPLall1(...; T2JAG($list())) errck. (Discrepancy vs the
// design docs, which cite only libxatsopt.hats; mirrors xats_lsp_check.dats, which
// includes all three. Verified 2026-06-20 — see frontend/docs/M0a-REPORT.md.)
//
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
// libxatsopt.hats does NOT staload locinfo (loctn_dummy, lcsrc/LCSRCnone0) or
// lexing0 (token_make_node, T_VAL, T_INT01) — add them exactly as the resident
// header and xats_lsp_check.dats do.
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
//
(* ****** ****** *)
//
#staload "./../SATS/pyfront.sats"
//
(* ****** ****** *)
//
// FFI to JS for stdout success markers (printing an sint cleanly). The .cats
// (frontend/CATS/pyfront.cats) implements PYF_println / PYF_println_int.
// (We could route through the prelude `proutsln`, but a tiny FFI keeps the
// success line unambiguous and frontend-owned.)
//
#extern fun
PYF_print(s: strn): void = $extnam()
#extern fun
PYF_println(s: strn): void = $extnam()
#extern fun
PYF_println_int(s: strn, n: sint): void = $extnam()
//
(* ****** ****** *)
//
// ---- the nil L1 fixity env (plan §6.6, open Q2) ----------------------------
//
// `d2parsed` carries a `t1penv: d1topenv` produced by `trans01`. We skip L1, so
// we supply an EMPTY one. RESOLVED APPROACH: `tr01env_free_top(tr01env_make_nil())`
// (trans01.sats:386,388). This is self-contained — no $MAP/$FIX namespacing, no
// reliance on the (now-visible-but-fragile) D1TOPENV constructor. trans23 reads
// t2penv+parsed for type-checking, not t1penv, so an empty fixity env is sound.
//
fun
the_empty_d1topenv((*void*)): d1topenv =
  tr01env_free_top(tr01env_make_nil())
//
(* ****** ****** *)
//
// ---- hand-build the L2 `d2parsed` for `val x = 1 ; val y = x` ---------------
//
// RE-ENTRANT: a fresh tr12env per call. The prelude is visible through the
// global fall-through (plan §4) thanks to the once-only `the_tr12env_pvsl00d()`
// bootstrap done in mymain_main; we never write the global env.
//
fun
build_d2parsed((*void*)): d2parsed = let
//
val loc = loctn_dummy()
//
// a plain `val` token (T_VAL of valkind; valkind VLKval = "val").
val tknd_val = token_make_node(loc, T_VAL(VLKval))
// the `=` token carried inside TEQD2EXPsome (its exact lexeme is irrelevant to
// trans23; only its presence/shape matters). Reuse the val token's loc.
val tknd_eq  = token_make_node(loc, T_VAL(VLKval))
//
val env = tr12env_make_nil()
//
// ---- decl #1 : val x = 1 -------------------------------------------------
//   pattern  : D2Pvar(fresh d2var for `x`)
//   RHS      : D2Ei00 1   (unboxed int literal; LOWERING-MAP §2.1)
//   bind     : AFTER lowering the RHS (non-recursive) — template C.
//
val sym_x  = symbl_make_name("x")
val d2v_x  = d2var_new2_name(loc, sym_x)
val pat_x  = d2pat_var(loc, d2v_x)
//
val rhs_1  = d2exp_make_node(loc, D2Ei00(1))
//
val dval_x = d2valdcl_make_args
  (loc, pat_x, TEQD2EXPsome(tknd_eq, rhs_1), WTHS2EXPnone())
//
// non-recursive val: bind the pattern AFTER lowering its RHS (template C).
val () = tr12env_add0_d2pat(env, pat_x)
//
val decl_x = d2ecl_make_node
  (loc, D2Cvaldclst(tknd_val, list_sing(dval_x)))
//
// ---- decl #2 : val y = x -------------------------------------------------
//   RHS use-site `x` : RESOLVE through the env (template A). This is the heart
//   of direct-to-L2 — it proves binding AND lookup share the same d2var object.
//
val rhs_x = resolve_dexp(env, loc, sym_x)
//
val sym_y  = symbl_make_name("y")
val d2v_y  = d2var_new2_name(loc, sym_y)
val pat_y  = d2pat_var(loc, d2v_y)
//
val dval_y = d2valdcl_make_args
  (loc, pat_y, TEQD2EXPsome(tknd_eq, rhs_x), WTHS2EXPnone())
//
val () = tr12env_add0_d2pat(env, pat_y)
//
val decl_y = d2ecl_make_node
  (loc, D2Cvaldclst(tknd_val, list_sing(dval_y)))
//
// ---- assemble the top-level decl list + the d2parsed ---------------------
//
val d2cs = list_cons(decl_x, list_cons(decl_y, list_nil()))
//
val t2penv = tr12env_free_top(env)
//
val source = LCSRCnone0()   // synthetic: no Python source yet (M1+ threads it)
//
val dpar2 =
  d2parsed_make_args
  ( 1(*stadyn: 1 = dynamic*)
  , 0(*nerror: our own lowering had none*)
  , source
  , the_empty_d1topenv()
  , t2penv
  , optn_cons(d2cs) )
//
in
  dpar2
end // end of [build_d2parsed]
//
// ---- template A : resolve an identifier to a d2exp -------------------------
//   mirrors trans12_dynexp.dats:1920-2037 (identifier reference). For M0a we
//   only need the D2ITMvar arm (the bound `x`); the other arms are written for
//   parity and to fail LOUDLY if M0a's invariant (x resolves to a var) breaks.
//
and
resolve_dexp
( env: !tr12env
, loc: loc_t, sym: sym_t): d2exp = let
//
val dopt = tr12env_find_d2itm(env, sym)
//
in
//
case+ dopt of
| ~optn_vt_cons(d2i1) =>
  (
    case+ d2i1 of
    | D2ITMvar(d2v) => d2exp_var(loc, d2v)
    | D2ITMcst(d2cs) => d2exp_csts(loc, d2cs)
    | D2ITMcon(d2cs) => d2exp_cons(loc, d2cs)
    | D2ITMsym(_, _) =>
      let
        val () = PYF_println("!! M0a: `x` resolved to D2ITMsym (unexpected)")
      in d2exp_none0(loc) end
  )
| ~optn_vt_nil() =>
  let
    val () = PYF_println("!! M0a: `x` did NOT resolve through the env (unbound)")
  in d2exp_none0(loc) end
//
end // end of [resolve_dexp]
//
(* ****** ****** *)
//
// ---- one self-contained build+check+report run -----------------------------
//
#implfun
pyfront_m0a_check() = let
//
val dpar2 = build_d2parsed()
//
// the reused L2 -> L3 entry: type-check the binding-resolved program.
val dpar3 = d3parsed_of_trans23(dpar2)
//
in
  dpar3
end // end of [pyfront_m0a_check]
//
(* ****** ****** *)
//
#implfun
pyfront_m0a_run(iter) = let
//
val () = PYF_println_int("== M0a iteration ==", iter)
//
val dpar3 = pyfront_m0a_check()
//
val nerror = d3parsed_get_nerror(dpar3)
//
// stock reporter: prints any `…errck` nodes (to stderr, like the stock driver).
val out0 = g_stderr()
val () = PYF_println("-- f3perr0_d3parsed (stock reporter, stderr) --")
val () = f3perr0_d3parsed(out0, dpar3)
//
// success marker on stdout so `nerror=0` is visible without parsing stderr.
val () = PYF_println_int("nerror =", nerror)
val () =
  if (nerror = 0)
  then PYF_println("RESULT: PASS (nerror=0) -- L2->L3 typecheck spine OK")
  else PYF_println("RESULT: FAIL (nerror>0)")
//
in
  nerror
end // end of [pyfront_m0a_run]
//
(* ****** ****** *)
//
// ---- main : the re-entrancy loop (run twice in one process) ----------------
//
fun
mymain_main((*void*)): void = let
//
// ONE-TIME global bootstrap (plan §6.1) — must precede ANY name resolution.
// Idempotent (gated by the_ntime); harmless to keep parity with the stock
// driver mymain_main (UTIL/xatsopt_tcheck00.dats:217).
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYF_println("######## M0a typecheck-spine driver ########")
val () = PYF_println("program (hand-built L2): val x = 1 ; val y = x")
//
// re-entrancy: run the ENTIRE build-and-check TWICE in this same process.
val n1 = pyfront_m0a_run(1)
val n2 = pyfront_m0a_run(2)
//
val () = PYF_println("######## re-entrancy summary ########")
val () = PYF_println_int("iteration 1 nerror =", n1)
val () = PYF_println_int("iteration 2 nerror =", n2)
val () =
  if (n1 = 0)
  then if (n2 = 0)
    then if (n1 = n2)
      then PYF_println("RE-ENTRANCY: PASS (both iterations nerror=0, identical)")
      else PYF_println("RE-ENTRANCY: FAIL (nerror diverged between iterations)")
    else PYF_println("RE-ENTRANCY: FAIL (iteration 2 accumulated errors -- STATE LEAK)")
  else PYF_println("RE-ENTRANCY: FAIL (iteration 1 already had errors)")
//
in
  (* nothing *)
end // end of [mymain_main]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_main()
//
(* ****** ****** *)
//
(*
end of [frontend/DATS/pyfront.dats]
*)
