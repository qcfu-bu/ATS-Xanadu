(* ****** ****** *)
(*
** GAP B (DYNAMIC P1 feature 5) REF-CELL SPIKE driver — proves the surface `r[]` /
** `r[] := e` maps to prelude REF-CELL calls that TYPECHECK to nerror=0 through the
** stock pipeline, BEFORE wiring the surface.
**
** The surface mapping (decided here, wired in pyelab_core.dats / pyparsing_dynexp.dats):
**   r[]        ->  a0ref_get(r)       (read THROUGH the cell — the prelude ref-get)
**   r[] := e   ->  a0ref_set(r, e)    (write THROUGH the cell — the prelude ref-set)
**   ref(x)     ->  a0ref_make_1val(x) (build a cell — used by the test fixtures)
**
** These are NOT a core L2 node: `[]`/`[]:=` are PRELUDE FUNCTIONS (srcgen1/prelude/SATS/
** arrn000.sats:43-56) that the stock prelude even `#symload`s onto `[]` (arrn000.sats:299-
** 300). The `a0ref(a)` TYPE is a `#typedef a0ref(a:vt) = a0ref_vt_tx(a)` in basics0.sats:1488.
**
** This spike builds, DIRECTLY at level-2 (no lexer/parser/L1):
**     def use_ref() -> Int:
**         let r = a0ref_make_1val(0)   # a0ref(Int)
**         let _ = a0ref_set(r, 10)     # void  (r[] := 10)
**         a0ref_get(r)                 # Int   (r[])
** i.e. a D2Elet0 chain over three calls to the prelude ref API, and probes nerror after
** tread3a. nerror=0 => GO (the L2 is well-typed; the surface can be wired to it).
**
** NB: the ref names resolve because this spike's pipeline runs the_tr12env_pvsl00d (the
** compiler-as-a-library prelude bootstrap), which makes the prelude ref fns visible exactly
** as the M3 driver makes them visible to USER programs by re-exporting them in pyrt.sats.
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ is modified. Typecheck-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
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
// resolve a (prelude) static type NAME to its s2exp. `Int` aliases the_s2exp_sint0.
fun
resolve_typ_name(env: !tr12env, name: strn): s2exp = let
  val sopt = tr12env_find_s2itm(env, symbl_make_name(name))
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
// resolve a (prelude) FUNCTION NAME (a0ref_make_1val / a0ref_get / a0ref_set) to a callable
// d2exp. A prelude `fun` is a d2cst CONSTANT -> D2ITMcst -> d2exp_cst (the SAME node the M3
// user path builds for a prelude call head). UNRESOLVED -> a counted none1 poison.
fun
resolve_fn(env: !tr12env, loc: loctn, name: strn): d2exp = let
  val sym  = symbl_make_name(name)
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
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2))
//
fun d2e_int(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
//
// an application  fn(args)  ->  D2Edapp(fn, -1, args).
fun d2e_app(loc: loctn, fn: d2exp, args: d2explst): d2exp =
  d2exp_make_node(loc, D2Edapp(fn, (-1), args))
//
(* ****** ****** *)
//
//   def use_ref() -> Int:
//       let r = a0ref_make_1val(0)
//       let _ = a0ref_set(r, 10)        # r[] := 10
//       a0ref_get(r)                    # r[]
//
fun
build_case((*void*)): d2parsed = let
//
val loc = loctn_dummy()
val env = tr12env_make_nil()
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
val d2v_f = d2var_new2_name(loc, symbl_make_name("use_ref"))
val () = tr12env_add0_d2var(env, d2v_f)
val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil())))
val sres = S2RESsome(S2EFFnone(), s2e_int)
//
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as)
val () = tr12env_pshlet0(env)
//
// let r = a0ref_make_1val(0)
val d2v_r  = d2var_new2_name(loc, symbl_make_name("r"))
val pat_r  = d2pat_var(loc, d2v_r)
val mk     = resolve_fn(env, loc, "a0ref_make_1val")
val mkcall = d2e_app(loc, mk, list_sing(d2e_int(loc, "0")))
val ()     = tr12env_add0_d2var(env, d2v_r)
val dval_r = d2valdcl_make_args(loc, pat_r, TEQD2EXPsome(tok_val(loc), mkcall), WTHS2EXPnone())
val decl_r = d2ecl_make_node(loc, D2Cvaldclst(tok_val(loc), list_sing(dval_r)))
//
// let _ = a0ref_set(r, 10)            (the `r[] := 10` write)
val d2v_u  = d2var_new2_name(loc, symbl_make_name("_u"))
val pat_u  = d2pat_var(loc, d2v_u)
val setfn  = resolve_fn(env, loc, "a0ref_set")
val setcall= d2e_app(loc, setfn, list_cons(resolve_var(env, loc, "r"), list_sing(d2e_int(loc, "10"))))
val ()     = tr12env_add0_d2var(env, d2v_u)
val dval_u = d2valdcl_make_args(loc, pat_u, TEQD2EXPsome(tok_val(loc), setcall), WTHS2EXPnone())
val decl_u = d2ecl_make_node(loc, D2Cvaldclst(tok_val(loc), list_sing(dval_u)))
//
// a0ref_get(r)                        (the `r[]` read — the tail value)
val getfn  = resolve_fn(env, loc, "a0ref_get")
val getcall= d2e_app(loc, getfn, list_sing(resolve_var(env, loc, "r")))
//
// body: let r = ...; let _ = ...; a0ref_get(r).
val inner  = d2exp_make_node(loc, D2Elet0(list_sing(decl_u), getcall))
val d2body = d2exp_make_node(loc, D2Elet0(list_sing(decl_r), inner))
//
val () = tr12env_poplet0(env)
val () = tr12env_poplam0(env)
//
val d2f =
  d2fundcl_make_args
    (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
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
end // end of [build_case]
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
mymain_refcell((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
// Load pyrt.sats (which re-exports a0ref_make_1val/a0ref_get/a0ref_set into the user env)
// EXACTLY as the M3 driver does (pyfront_m3.dats:207). `the_tr12env_pvsl00d` loads only the
// REDUCED prelude (basics0 has the `a0ref` TYPE, but NOT arrn000's fns), so without this the
// ref fns resolve to a counted none1 poison. knd0=0 (static .sats).
val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
//
val () = PYB_log("######## GAP B (REF-CELL) SPIKE ########")
val () = PYB_log("[case] def use_ref(): let r=a0ref_make_1val(0); a0ref_set(r,10); a0ref_get(r)")
val n1 = run_case("case", build_case())
//
in
  if n1 = 0 then PYB_log("RESULT: PASS (ref-get/set/make typecheck, nerror=0 — GO to wire r[]/r[]:=)")
  else PYB_log("RESULT: FAIL (ref-cell L2 did NOT typecheck, nerror != 0)")
end // end of [mymain_refcell]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_refcell()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_refcell_spike.dats]
*)
