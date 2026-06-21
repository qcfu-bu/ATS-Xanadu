(* ****** ****** *)
(*
** ABSTRACT-TYPE + EXTERN GATING SPIKE driver — proves that an ABSTRACT TYPE
** declaration (`abstype Foo`, opaque) + a function that USES it opaquely
** (`def id(x: Foo) -> Foo: x`) + an `assume Foo = Int` (D2Cabsimpl) + an
** FFI bodyless signature (`extern def c_id(n: Int) -> Int`) + a CALL to it
** all CONSTRUCT DIRECTLY at level-2 and TYPECHECK to nerror=0.
**
** Hand-builds the L2 equivalent of:
**
**     abstype Foo                       # opaque: an s2cst with NO sexp
**     def id(x: Foo) -> Foo: x          # uses Foo opaquely (no inspection)
**     assume Foo = Int                  # D2Cabsimpl: hidden representation
**     extern def c_id(n: Int) -> Int    # FFI bodyless signature (a d2cst)
**     def use(n: Int) -> Int: c_id(n)   # a CALL to the extern signature
**
** RECIPE MIRRORED FROM (cited):
**   (A) abstype:  trans12_decl00.dats f0_abstype (1471) — s2cst_make_idst(loc,
**       sym, sort) with NO s2exp attached (opacity); tr12env_add1_s2cst;
**       d2ecl(D2Cabstype(s2c1, A2TDFsome())). Sort from abstype_sort2 (263) →
**       the_sort2_tbox for a boxed abstract type.
**   (A) assume:   trans12_decl00.dats f0_absimpl (1947) — select the abstract
**       s2cst by name via tr12env_find_s2itm → S2ITMcst → head; build a
**       simpl(loc, SIMPLone1(s2c)); the rep s2exp; d2ecl(D2Cabsimpl(tknd, simp,
**       s2e)). trans23 inserts the s2c into the env; opacity holds at typecheck
**       (the abstract s2cst has NO sexp ⇒ a distinct singleton).
**   (B) extern:   trans12_decl00.dats trans12_d1cstdcl (4438) — a BODYLESS fun
**       signature is a `d2cst` carrying a function type `sfun = f1_d2as(0, d2as,
**       sres)` (here directly s2exp_fun1_nil0(npf, [Int], Int)); d2cst_make_idtp
**       (tok, dpid_tok, tqas, sfun); REGISTER via tr12env_add1_d2cst so calls
**       resolve; wrap in d2cstdcl_make_args + D2Cdynconst + D2Cextern
**       (f0_dynconst 3479 / D1Cextern 845). The d2cst resolves like any function
**       ⇒ `c_id(n)` typechecks against the declared signature.
**
** PURELY ADDITIVE: only CALLS the compiler-as-a-library (lib2xatsopt). Nothing
** under srcgen2/ or language-server/ is modified. Typecheck-only (no codegen).
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
// resolve a (prelude) static type NAME to its s2exp (same as the m5b spike).
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
(* ****** ****** *)
//
// select an ALREADY-REGISTERED type s2cst by name (the assume target). Mirrors
// f1_sqid (trans12_decl00.dats:1778): tr12env_find_s2itm → S2ITMcst → head.
//
fun
find_s2cst(env: !tr12env, name: strn): s2cstopt_vt = let
  val sopt = tr12env_find_s2itm(env, symbl_make_name(name))
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then optn_vt_nil() else optn_vt_cons(s2cs.head())
      | _ => optn_vt_nil()
    )
  | ~optn_vt_nil() => optn_vt_nil()
end
//
(* ****** ****** *)
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
// resolve a CONSTANT (a d2cst, e.g. the extern signature) by name to a D2Ecst.
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
          if list_nilq(d2cs) then d2exp_none0(loc)
          else d2exp_make_node(loc, D2Ecst(d2cs.head()))
      | _ => d2exp_none0(loc)
    )
  | ~optn_vt_nil() => d2exp_none0(loc)
end
//
(* ****** ****** *)
//
// BUILD the whole program directly at L2 and return a d2parsed.
//
fun
build_d2parsed((*void*)): d2parsed = let
//
val loc = loctn_dummy()
//
val env = tr12env_make_nil()
//
// ===== (A) the abstract type `abstype Foo` (boxed, OPAQUE: NO sexp) =============
//
// f0_abstype: s2cst_make_idst(loc, sym, sort) with NO s2exp attached → opacity.
// Sort = the_sort2_tbox (abstype_sort2 of the default boxed `abstype` kind).
val sym_foo = symbl_make_name("Foo")
val s2c_foo = s2cst_make_idst(loc, sym_foo, the_sort2_tbox)
val () = tr12env_add1_s2cst(env, s2c_foo)
//
// `Foo` as a type (its s2exp) — used by the interface function. This is an
// OPAQUE singleton: s2c_foo carries no underlying sexp, so it is distinct from
// every other type until `assume` (below).
val s2e_foo = s2exp_cst(s2c_foo)
//
// the D2Cabstype decl. A2TDFsome() = a plain abstract declaration (unspecified
// erasure), exactly what f0_abstype builds for `abstype Foo` (no `= T`).
val absdecl = d2ecl_make_node(loc, D2Cabstype(s2c_foo, A2TDFsome()))
//
// ===== (A) the interface function `def id(x: Foo) -> Foo: x` ====================
//
// Uses `Foo` OPAQUELY: takes a Foo, returns the same Foo, never inspects it.
// This typechecks against the abstract singleton WITHOUT a representation.
val sym_id = symbl_make_name("id")
val d2v_id = d2var_new2_name(loc, sym_id)
val () = tr12env_add0_d2var(env, d2v_id)
//
val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
val pat_x = d2pat_var(loc, d2v_x)
val pat_x_annot = d2pat_make_node(loc, D2Pannot(pat_x, s1exp_none0(loc), s2e_foo))
val f2as_id = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_x_annot))))
val sres_id = S2RESsome(S2EFFnone(), s2e_foo)
//
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as_id)
val body_id = resolve_var(env, loc, "x")
val () = tr12env_poplam0(env)
//
val tok_val = token_make_node(loc, T_VAL(VLKval))
val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
val d2f_id =
  d2fundcl_make_args
    (loc, d2v_id, f2as_id, sres_id, TEQD2EXPsome(tok_val, body_id), WTHS2EXPnone())
val iddecl =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2f_id)))
//
// ===== (A) the assume `assume Foo = Int` (D2Cabsimpl) ===========================
//
// select the abstract s2cst `Foo` by name (mirrors f1_sqid), build SIMPLone1,
// give it the concrete representation `Int`'s s2exp.
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
val simp_foo =
(
  case+ find_s2cst(env, "Foo") of
  | ~optn_vt_cons(s2c) => simpl_make_node(loc, SIMPLone1(s2c))
  // unreachable: Foo was just registered above.
  | ~optn_vt_nil()     => simpl_make_node(loc, SIMPLone1(s2c_foo))
)
val tok_absimpl = token_make_node(loc, T_ABSIMPL())
val asmdecl = d2ecl_make_node(loc, D2Cabsimpl(tok_absimpl, simp_foo, s2e_int))
//
// ===== (B) the FFI signature `extern def c_id(n: Int) -> Int` ===================
//
// a BODYLESS function signature = a d2cst carrying the function type
// (Int) -> Int, registered so a call resolves. Mirrors trans12_d1cstdcl
// (s2exp_fun1_nil0 for the fun type; d2cst_make_idtp; tr12env_add1_d2cst;
// d2cstdcl_make_args; D2Cdynconst), wrapped in D2Cextern.
val tok_cid = token_make_node(loc, T_IDALP("c_id"))
val sfun_cid = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_int), s2e_int)
val tok_dyncst = token_make_node(loc, T_FUN(FNKfn2))
val d2c_cid = d2cst_make_idtp(tok_dyncst, tok_cid, list_nil()(*tqas*), sfun_cid)
val () = tr12env_add1_d2cst(env, d2c_cid)
//
// the d2cstdcl: a constant decl carrying the d2cst, no args list / no body.
// (darg=[], sres=none, dres=none — the function type already lives in d2c_cid.)
val dcdcl_cid =
  d2cstdcl_make_args(loc, d2c_cid, list_nil()(*darg*), S2RESnone(), TEQD2EXPnone())
val dyncst_cid =
  d2ecl_make_node(loc, D2Cdynconst(tok_dyncst, list_nil()(*tqas*), list_sing(dcdcl_cid)))
val tok_extern = token_make_node(loc, T_SRP_EXTERN())
val externdecl = d2ecl_make_node(loc, D2Cextern(tok_extern, dyncst_cid))
//
// ===== (B) the caller `def use(n: Int) -> Int: c_id(n)` =========================
//
// a CALL to the extern signature — resolves to the registered d2cst, applied to
// `n : Int`, yielding Int. Proves the signature is in scope + callable.
val sym_use = symbl_make_name("use")
val d2v_use = d2var_new2_name(loc, sym_use)
val () = tr12env_add0_d2var(env, d2v_use)
//
val d2v_n = d2var_new2_name(loc, symbl_make_name("n"))
val pat_n = d2pat_var(loc, d2v_n)
val pat_n_annot = d2pat_make_node(loc, D2Pannot(pat_n, s1exp_none0(loc), s2e_int))
val f2as_use = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_n_annot))))
val sres_use = S2RESsome(S2EFFnone(), s2e_int)
//
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as_use)
val d2head_cid = resolve_cst(env, loc, "c_id")
val d2arg_n = resolve_var(env, loc, "n")
// the call c_id(n): a dynamic application D2Edapp(head, npf=-1, [arg]).
val body_use =
  d2exp_make_node(loc, D2Edapp(d2head_cid, (-1)(*npf*), list_sing(d2arg_n)))
val () = tr12env_poplam0(env)
//
val d2f_use =
  d2fundcl_make_args
    (loc, d2v_use, f2as_use, sres_use, TEQD2EXPsome(tok_val, body_use), WTHS2EXPnone())
val usedecl =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2f_use)))
//
// ===== assemble the d2parsed in declaration order ==============================
//
//   abstype Foo ; def id ; assume Foo=Int ; extern def c_id ; def use
val decls =
  list_cons(absdecl,
  list_cons(iddecl,
  list_cons(asmdecl,
  list_cons(externdecl,
  list_sing(usedecl)))))
//
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
  val () = PYB_log("[abs] trans2a (overload res) done")
  val ( ) = d2parsed_by_trsym2b(dpar)
  val () = PYB_log("[abs] trsym2b (symbol res) done")
  val dpar = d2parsed_of_t2read0(dpar)
  val () = PYB_log("[abs] t2read0 (L2 read/check) done")
  val dp3 = d3parsed_of_trans23(dpar)
  val () = PYB_log("[abs] trans23 (L2 -> L3) done")
in
  dp3
end
//
(* ****** ****** *)
//
fun
mymain_abs((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYB_log("######## ABSTYPE + EXTERN construction GATING SPIKE ########")
val () = PYB_log("[abs] building abstype Foo + id + assume + extern c_id + use ...")
val dpar = build_d2parsed()
val () = PYB_log("[abs] d2parsed built; running L2->L3 pipeline ...")
//
val dp3 = run_pipeline(dpar)
//
val dp3 = d3parsed_of_tread3a(dp3)
val nerror = d3parsed_get_nerror(dp3)
val () = PYB_log_int("[abs] nerror (after tread3a) =", nerror)
//
val out0 = g_stderr()
val () = PYB_log("[abs] -- f3perr0_d3parsed (stock reporter) --")
val () = f3perr0_d3parsed(out0, dp3)
//
in
  if nerror = 0 then
    PYB_log("RESULT: PASS (abstype opaque-use + assume + extern call typecheck, nerror=0)")
  else
    PYB_log("RESULT: FAIL (nerror != 0 ; see f3perr0 above)")
end // end of [mymain_abs]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_abs()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_abs_spike.dats]
*)
