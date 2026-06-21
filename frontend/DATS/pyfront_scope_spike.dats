(* ****** ****** *)
(*
** STAGE-0 SCOPING SURFACE SPIKE driver (bootstrap P1, feature 1).
**
** Hand-builds at L2 (NO surface, NO lexer/parser) and runs each probe through the
** real stock pipeline trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a, then prints
** the post-tread3a nerror. EACH probe is an INDEPENDENT d2parsed in its OWN node
** process (PYB_probe selector) so a hard XATS000_cfail is ISOLATED.
**
** Probes (the scoping-surface parity area):
**   S1  D2Ewhere      def f(n) = (go(n,1)) where { def go(k,acc) = ... }
**                     — the BODY references `go`, defined in the WHERE-block.
**                     Confirms the where-decls are in scope for the body.
**   S2  D2Clocal0     local { def helper(x) = x+1 } in { def public(y) = helper(y) } end
**                     — `public` references the PRIVATE `helper`; the whole thing
**                     EXPORTS `public` (helper visible in D2, not past the end).
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
// resolve a (prelude or env) static NAME to its s2exp (head s2cst on hit).
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
// resolve a (prelude) static NAME to its head s2cst (for #stacst0 operators like add_i0_i0).
//
fun
resolve_s2cst(env: !tr12env, name: strn): s2cstopt_vt = let
  val key = symbl_make_name(name)
  val sopt = tr12env_find_s2itm(env, key)
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
// resolve a dynamic NAME to a d2exp reference (var or cst).
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
// build a static arithmetic application  op(a, b)  from a prelude #stacst0 (add_i0_i0/...).
//
fun
build_binop
(env: !tr12env, loc: loctn, opname: strn, a: s2exp, b: s2exp): s2exp = let
  val copt = resolve_s2cst(env, opname)
in
  case+ copt of
  | ~optn_vt_cons(c) =>
      s2exp_apps(loc, s2exp_cst(c), list_cons(a, list_sing(b)))
  | ~optn_vt_nil()    => s2exp_none0()
end
//
(* ****** ****** *)
//
// helper: build a simple non-generic fun decl
//   def NAME(p0:Int, ...) -> Int : BODY
// where BODY is produced by `mkbody` given the env with the params bound + registered.
// Returns the d2ecl; the function's d2var is pre-registered in `env` (so callers/recursion see it).
//
fun
build_fun1
( env: !tr12env, loc: loctn
, name: strn, pnames: list(strn)
, s2e_int: s2exp
, mkbody: (!tr12env) -<cloref1> d2exp ): d2ecl = let
//
  val sym_f = symbl_make_name(name)
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)        // register the fn name (recursion + later refs)
//
  // build the param patterns (each `p : Int`) and the f2arg
  fun
  mk_pats(env: !tr12env, ns: list(strn)): d2patlst =
    case+ ns of
    | list_nil() => list_nil()
    | list_cons(nm, rest) => let
        val d2v_p = d2var_new2_name(loc, symbl_make_name(nm))
        val pat0  = d2pat_var(loc, d2v_p)
        val pat   = d2pat_make_node(loc, D2Pannot(pat0, s1exp_none0(loc), s2e_int))
        val () = tr12env_add0_d2var(env, d2v_p)
      in
        list_cons(pat, mk_pats(env, rest))
      end
//
  val sres = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val pats = mk_pats(env, pnames)
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), pats)))
  val () = tr12env_add0_f2arglst(env, f2as)
  val body = mkbody(env)
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, body), WTHS2EXPnone())
in
  d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2f)))
end
//
(* ****** ****** *)
//
// ===== PROBE S1 : D2Ewhere (where-decls in scope for the body) ==================
//
//   def f(n) -> Int:
//       go(n, 1)            <- body REFERENCES `go`
//   where:
//       def go(k, acc) -> Int: acc   <- the where-decl, in scope for f's body
//
//   Lowered as the def `f` whose BODY is D2Ewhere(body_expr, [go_decl]).
//
fun
probe_S1((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  // outer def f(n) -> Int : ( go(n, 1) where { def go(k,acc) = acc } )
  val dcl_f =
    build_fun1( env, loc, "f", list_sing("n"), s2e_int
    , lam (env) =<cloref1>
      let
        // build the WHERE-decl `go` in a CHILD scope so its name is visible to the body.
        // (faithful: where-decls scope around the body — register `go` before building the body.)
        val dcl_go =
          build_fun1( env, loc, "go", list_cons("k", list_sing("acc")), s2e_int
          , lam (env2) =<cloref1> resolve_var(env2, loc, "acc") )
        // the body expr: go(n, 1)
        val d2e_go = resolve_var(env, loc, "go")
        val d2e_n  = resolve_var(env, loc, "n")
        val d2e_1  = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("1"))))
        val body_expr = d2exp_dapp(loc, d2e_go, (-1), list_cons(d2e_n, list_sing(d2e_1)))
      in
        d2exp_make_node(loc, D2Ewhere(body_expr, list_sing(dcl_go)))
      end
    )
//
  val decls = list_sing(dcl_f)
  val t2penv = tr12env_free_top(env)
in
  run_one("[S1] D2Ewhere: f(n)=(go(n,1) where {def go(k,acc)=acc})  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE S2 : D2Clocal0 public/private split ================================
//
//   local
//     def helper(x) -> Int: x + 1     <- D1 = the PRIVATE decls
//   in
//     def public(y) -> Int: helper(y) <- D2 = the rest-of-suite; SEES helper, is EXPORTED
//   end
//
fun
probe_S2((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  // D1: def helper(x) -> Int : x   (registered in env -> visible to D2's body)
  // (body is a bare param read — isolates D2Clocal0 scoping from any prelude-operator
  // resolution; the public/private VISIBILITY is what this probe characterizes.)
  val dcl_helper =
    build_fun1( env, loc, "helper", list_sing("x"), s2e_int
    , lam (env2) =<cloref1> resolve_var(env2, loc, "x") )
//
  // D2: def public(y) -> Int : helper(y)   (references the PRIVATE helper)
  val dcl_public =
    build_fun1( env, loc, "public", list_sing("y"), s2e_int
    , lam (env2) =<cloref1>
      let
        val d2e_h = resolve_var(env2, loc, "helper")
        val d2e_y = resolve_var(env2, loc, "y")
      in
        d2exp_dapp(loc, d2e_h, (-1), list_sing(d2e_y))
      end
    )
//
  val d1 = list_sing(dcl_helper)            // PRIVATE  (local-head)
  val d2 = list_sing(dcl_public)            // PUBLIC   (local-body, exports `public`)
  val dcl_local = d2ecl_make_node(loc, D2Clocal0(d1, d2))
//
  val decls = list_sing(dcl_local)
  val t2penv = tr12env_free_top(env)
in
  run_one("[S2] D2Clocal0: local{def helper(x)=x+1} in {def public(y)=helper(y)} end  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_scope((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## STAGE-0 SCOPING SURFACE SPIKE ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE S1 (D2Ewhere) ----")
                 val _ = probe_S1() in 0 end
      | 2 => let val () = PYB_log("---- PROBE S2 (D2Clocal0 split) ----")
                 val _ = probe_S2() in 0 end
      | _ => let val () = PYB_log("---- S1 ----") val _ = probe_S1()
                 val () = PYB_log("---- S2 ----") val _ = probe_S2()
              in 0 end
    ) : sint
in
  PYB_log("######## END STAGE-0 SCOPE SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_scope()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_scope_spike.dats]
*)
