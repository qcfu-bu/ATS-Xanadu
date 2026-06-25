(* ****** ****** *)
(*
** M7-import GATING SPIKE driver — feasibility test for MULTI-FILE support:
** does loading a user `.sats` module via the SAME pervasive loader the pyrt
** prelude uses (filpath_pvsload -> f0_pvsload) make its exported `fun` RESOLVE
** and TYPECHECK at a call site in a separately-built L2 program?
**
** This is the GATING question for lowering `import M` / `from M import x`
** (currently a NO-OP: PCCimport -> list_nil, PCCstaload -> D2Cnone0). Our
** frontend builds directly at L2 and SKIPS trans01/trans12, so building a
** D2Cstaload node does NOT itself trigger the file load (that happens in the
** stock f0_staload during trans12, which we never run). The pyrt prelude proves
** the workaround: load the .sats OUT-OF-BAND with filpath_pvsload, which merges
** its exports into the GLOBAL pervasive env, after which the names resolve via
** the ordinary tr12env global fall-through — no per-file staload node needed.
**
** PROBE I1 (the GO/NO-GO):
**   1. filpath_pvsload(0, "/frontend/TEST/m7imp/lib.sats")  -- load the user module
**   2. build, DIRECTLY at L2, the importing program:
**        def f(x: Int) -> Int: lib_double(x)
**      where `lib_double` is RESOLVED BY NAME from the (now-merged) global env.
**   3. run the full L2->L3 typecheck pipeline (trans2a/trsym2b/t2read0/trans23/
**      tread3a) and report nerror.
**   nerror=0  => the pervasive-load template GENERALIZES to user modules => GO.
**   nerror>0  => characterize the errck (the exact blocker).
**
** PROBE I0 (control / sanity): the SAME program WITHOUT loading lib.sats first.
**   `lib_double` must then be UNRESOLVED -> nerror>0. Confirms the probe-I1 pass
**   is due to the load (not an accidental prelude name).
**
** RECIPE MIRRORED FROM the proven spikes (pyfront_m5b6_spike.dats) + the proven
** pyrt load (pyfront_m3.dats:164-184 / pyfront_lsp.dats:58-77). ONLY DELTA: the
** loaded file is an ARBITRARY user .sats (not the fixed pyrt.sats), and the L2
** program REFERENCES one of its exports by name.
**
** PURELY ADDITIVE: only CALLS lib2xatsopt + filpath_pvsload (exported,
** xglobal.sats:172). Nothing under srcgen2/ or language-server/ is modified.
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
// L1 AST makers (vestigial s1exp_none0 for the D2Pannot given-slot), as the
// proven boxed spikes do.
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
// resolve a (prelude) static type NAME to its s2exp (the_s2exp_sint0 = the M5a
// direct T2Pcst Int that int literals/annotations carry). Same as the boxed spikes.
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
// resolve a bound dynamic VARIABLE by name to a D2Evar reference (the param `x`).
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
// resolve a dynamic CONSTANT (an imported .sats `fun`) by name. After the
// pervasive load it lands in the global env as D2ITMcst(d2cstlst). Returns a
// D2Ecsts reference (the overload set), which trans2a/trans23 resolves to the
// concrete d2cst at the call site — exactly like a prelude function. Returns
// d2exp_none0 (-> errck downstream) if the name is UNRESOLVED (probe I0).
//
fun
resolve_cst(env: !tr12env, loc: loctn, name: strn): d2exp = let
  val dopt = tr12env_find_d2itm(env, symbl_make_name(name))
in
  case+ dopt of
  | ~optn_vt_cons(d2i) =>
    (
      case+ d2i of
      | D2ITMcst(d2cs) =>
          if list_nilq(d2cs) then d2exp_none0(loc) else d2exp_csts(loc, d2cs)
      | D2ITMvar(d2v) => d2exp_make_node(loc, D2Evar(d2v))
      | D2ITMsym(_, _) => d2exp_none0(loc)  // unresolved symbol overload
      | _ => d2exp_none0(loc)
    )
  | ~optn_vt_nil() => d2exp_none0(loc)  // NAME NOT FOUND -> errck (probe I0)
end
//
(* ****** ****** *)
//
// run ONE d2parsed (one decl list) through the full L2->L3 pipeline and return
// the post-tread3a nerror. EACH probe builds its own fresh env + d2parsed.
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
  // stock reporter on stderr (prints errck nodes when nerror>0) — characterizes
  // the EXACT blocker text for the NO-GO / control case.
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dp3))
in
  nerror
end
//
(* ****** ****** *)
//
// build, directly at L2, the importing program:
//
//   def f(x: Int) -> Int: lib_double(x)
//
// `lib_double` is resolved BY NAME (resolve_cst) from the env — so whether it
// resolves depends ENTIRELY on whether lib.sats was loaded first. The body is a
// dynamic application D2Edapp(lib_double, [x]).
//
fun
build_using_prog(env: !tr12env, loc: loctn): d2eclist = let
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val sym_f = symbl_make_name("f")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val pat_x = d2pat_var(loc, d2v_x)
  val pat_x_annot = d2pat_make_node(loc, D2Pannot(pat_x, s1exp_none0(loc), s2e_int))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_x_annot))))
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
  // the call body: lib_double(x). The HEAD is resolved by name (the import test).
  val d2_libdouble = resolve_cst(env, loc, "lib_double")
  val d2_x = resolve_var(env, loc, "x")
  val d2body = d2exp_make_node(loc, D2Edapp(d2_libdouble, 0(*npf*), list_sing(d2_x)))
//
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
in
  list_sing(fundecl)
end
//
(* ****** ****** *)
//
// ===== PROBE I1 : the GO/NO-GO — LOAD lib.sats, then USE lib_double ============
//
fun
probe_I1((*void*)): sint = let
//
  // ==== THE IMPORT: load the user module via the pyrt pervasive-load template ====
  // filpath_pvsload prepends XATSHOME, so the path is XATSHOME-relative. knd0=0
  // (STATIC) — load the .sats INTERFACE (typed d2cst), as pyrt does for typecheck.
  val () = PYB_log("[I1] filpath_pvsload(0, /frontend/TEST/m7imp/lib.sats) ...")
  val () = filpath_pvsload(0(*static*), "/frontend/TEST/m7imp/lib.sats")
  val () = PYB_log("[I1] lib.sats loaded (lib_double should now resolve via global fall-through)")
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val decls = build_using_prog(env, loc)
  val t2penv = tr12env_free_top(env)
in
  run_one("[I1] LOADED lib.sats ; def f(x:Int)->Int: lib_double(x)  nerror=", decls, t2penv)
end
//
// ===== PROBE I0 : the CONTROL — do NOT load lib.sats ; lib_double UNRESOLVED ====
//
fun
probe_I0((*void*)): sint = let
//
  val () = PYB_log("[I0] (control) NOT loading lib.sats ; lib_double should be UNRESOLVED")
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val decls = build_using_prog(env, loc)
  val t2penv = tr12env_free_top(env)
in
  run_one("[I0] NO load ; def f(x:Int)->Int: lib_double(x)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_import((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## M7-import (multi-file) GATING SPIKE ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE I1 (LOAD lib.sats then USE lib_double) ----")
                 val _ = probe_I1() in 0 end
      | 0 => let val () = PYB_log("---- PROBE I0 (control: NO load) ----")
                 val _ = probe_I0() in 0 end
      | _ => let val () = PYB_log("---- PROBE I0 (control: NO load) ----") val _ = probe_I0()
                 val () = PYB_log("---- PROBE I1 (LOAD then USE) ----") val _ = probe_I1()
              in 0 end
    ) : sint
in
  PYB_log("######## END M7-import SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_import()
//
(* ****** ****** *)
(*
** end of [frontend/DATS/pyfront_import_spike.dats]
*)
