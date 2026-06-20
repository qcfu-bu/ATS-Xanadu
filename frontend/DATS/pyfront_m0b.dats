(* ****** ****** *)
(*
** M0b — Python-surface frontend: the CODEGEN-spine driver (DATS).
**
** Closes the "compile to JS" tracer bullet. REUSES M0a's typecheck spine
** (`pyfront_m0a_check() : d3parsed`, the hand-built `val x = 1 ; val y = x`)
** and drives that exact d3parsed through the IN-MEMORY xats2js backend,
** emitting the user program's JavaScript to stdout.
**
** The pass sequence below replicates `mymain_work` in
** srcgen2/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats:96-170 EXACTLY
** (verified names+order against the live SATS, 2026-06-20):
**
**   d3parsed_of_tread3a   srcgen2/SATS/tread3a.sats:119   (d3parsed)->(d3parsed)
**   d3parsed_of_trtmp3b   srcgen2/SATS/trtmp3b.sats:212    (d3parsed)->d3parsed
**   d3parsed_of_trtmp3c   srcgen2/SATS/trtmp3c.sats:266    (d3parsed)->d3parsed
**   d3parsed_of_t3read0   srcgen2/SATS/t3read0.sats:122    (d3parsed)->(d3parsed)
**   i0parsed_of_trxd3i0   xats2cc/srcgen1/SATS/trxd3i0.sats:53  (d3parsed)->i0parsed
**   i0parsed_of_tryd3i0   xats2cc/srcgen1/SATS/tryd3i0.sats:53  (i0parsed)->i0parsed
**   i1parsed_of_trxi0i1   xats2js/srcgen2/SATS/trxi0i1.sats:124 (i0parsed)->i1parsed
**   i1parsed_js1emit      xats2js/srcgen2/SATS/js1emit.sats:202 (i1parsed,FILR)->void
**
** PURELY ADDITIVE: nothing under srcgen2/ or language-server/ is modified; M0a's
** pyfront.{sats,dats}/build-m0a.sh are untouched. This only CALLS the
** compiler+backend linked from srcgen2/lib/lib2xatsopt.js + lib2xats2cc.js +
** lib2xats2js.js (built from source by build-m0b.sh; see frontend/docs/M0b-REPORT.md).
*)
(* ****** ****** *)
//
// Same three headers M0a verified are required for a standalone jsemit00 driver:
// libxatsopt.hats (SATS) + xatsopt_sats.hats (prelude SATS) + xatsopt_dpre.hats
// (prelude DATS = the template IMPLEMENTATIONS). Without the latter two, prelude
// templates used here (=, list ops, ...) stay un-instantiated as errck nodes.
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
// locinfo/lexing0 are NOT in libxatsopt.hats; M0a's pyfront.sats (staloaded
// below) references them, so keep them in scope exactly as M0a's DATS does.
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
//
// t3read0 is NOT in the top-level libxatsopt.hats (it has tread3a/trtmp3b/
// trtmp3c/f3perr0 but NOT t3read0); staload it explicitly for d3parsed_of_t3read0.
//
#staload "./../../srcgen2/SATS/t3read0.sats"
//
// The xats2js BACKEND SATS — these declare the codegen pass sequence and are
// NOT in libxatsopt.hats. They MUST be staloaded HERE in the DATS (a .sats's
// nested #staloads do not re-export to a DATS that staloads it). intrep0/
// trxd3i0/tryd3i0 = the xats2cc intermediate rep + L3->intrep0 / intrep0-resolve
// passes; intrep1/trxi0i1/xats2js/js1emit = the xats2js intrep1 + intrep0->
// intrep1 pass + JS emitter. (Same staload form as
// srcgen2/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats:59-72.)
//
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/intrep0.sats"
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/trxd3i0.sats"
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/tryd3i0.sats"
//
#staload "./../../srcgen2/xats2js/srcgen2/SATS/intrep1.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/trxi0i1.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/xats2js.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/js1emit.sats"
//
(* ****** ****** *)
//
// Reuse M0a's typecheck spine (pyfront_m0a_check : d3parsed). Staload its SATS
// directly here so the symbol resolves (same nested-staload caveat as above).
// (We do NOT staload pyfront_m0b.sats: pyfront_m0b_emit is a local `fun` below,
// and staloading its declaration would clash; the SATS documents the surface.)
//
#staload "./../SATS/pyfront.sats"
//
(* ****** ****** *)
//
// Frontend-owned FFI to stderr for progress markers + the stdout sentinels that
// delimit the emitted JS (so build-m0b.sh can extract exactly the emitted text
// from a stdout that also carries M0a's auto-run re-entrancy summary). The .cats
// (frontend/CATS/pyfront_m0b.cats) implements these.
//   PYF2_log*   -> process.stderr  (progress; never pollutes the emitted JS)
//   PYF2_mark   -> process.stdout  (the sentinel lines around the JS)
//
#extern fun
PYF2_log(s: strn): void = $extnam()
#extern fun
PYF2_log_int(s: strn, n: sint): void = $extnam()
#extern fun
PYF2_mark(s: strn): void = $extnam()
//
(* ****** ****** *)
//
// ---- codegen-correct L2 builder (the M0b lowering fix) ---------------------
//
// M0a's pyfront_m0a_check() builds `val x = 1` with the UNBOXED int literal
// `D2Ei00(sint)` (dynexp2.sats:923). That typechecks (M0a: nerror=0) but the
// xats2cc backend lowering has NO arm for `D3Ei00` (trxd3i0_dynexp.dats only
// handles `D3Eint of token`, line 845); an unboxed D3Ei00 falls through to an
// `I0Enone1` placeholder, so js1emit dumps a debug node instead of real JS.
//
// M0b therefore rebuilds the SAME program `val x = 1 ; val y = x` with the
// TOKEN-based literal `D2Eint(token T_INT01("1"))` — the exact node the real
// parser produces (trans23_dynexp.dats:1072 -> D3Eint -> f0_int -> I0Eint ->
// XATSINT1(1)). The binding+resolution machinery (the M0a heart: bind x via
// tr12env_add0_d2pat, resolve the use-site x via tr12env_find_d2itm) is
// replicated UNCHANGED. We still CALL pyfront_m0a_check() below to exercise and
// report the reused typecheck spine. (Discrepancy logged in M0b-REPORT.md §
// "literal-node codegen gap"; the proper fix in M1 is to lower Python int
// literals to token-based D2Eint from the start.)
//
fun
build_d2parsed_codegen((*void*)): d2parsed = let
//
val loc = loctn_dummy()
val tknd_val = token_make_node(loc, T_VAL(VLKval))
val tknd_eq  = token_make_node(loc, T_VAL(VLKval))
//
val env = tr12env_make_nil()
//
// ---- val x = 1 : RHS = D2Eint(token T_INT01("1")) (codegen-correct) -------
val sym_x  = symbl_make_name("x")
val d2v_x  = d2var_new2_name(loc, sym_x)
val pat_x  = d2pat_var(loc, d2v_x)
//
val tok_1  = token_make_node(loc, T_INT01("1"))
val rhs_1  = d2exp_make_node(loc, D2Eint(tok_1))
//
val dval_x = d2valdcl_make_args
  (loc, pat_x, TEQD2EXPsome(tknd_eq, rhs_1), WTHS2EXPnone())
val () = tr12env_add0_d2pat(env, pat_x)
val decl_x = d2ecl_make_node(loc, D2Cvaldclst(tknd_val, list_sing(dval_x)))
//
// ---- val y = x : RHS = resolve `x` through the env (template A) -----------
val rhs_x = resolve_dexp_m0b(env, loc, sym_x)
//
val sym_y  = symbl_make_name("y")
val d2v_y  = d2var_new2_name(loc, sym_y)
val pat_y  = d2pat_var(loc, d2v_y)
//
val dval_y = d2valdcl_make_args
  (loc, pat_y, TEQD2EXPsome(tknd_eq, rhs_x), WTHS2EXPnone())
val () = tr12env_add0_d2pat(env, pat_y)
val decl_y = d2ecl_make_node(loc, D2Cvaldclst(tknd_val, list_sing(dval_y)))
//
val d2cs = list_cons(decl_x, list_cons(decl_y, list_nil()))
val t2penv = tr12env_free_top(env)
val source = LCSRCnone0()
//
val dpar2 =
  d2parsed_make_args
  ( 1(*stadyn:dynamic*), 0(*nerror*), source
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(d2cs) )
//
in
  dpar2
end // end of [build_d2parsed_codegen]
//
// identifier resolver (template A), same shape as M0a's resolve_dexp.
and
resolve_dexp_m0b
( env: !tr12env, loc: loc_t, sym: sym_t): d2exp = let
  val dopt = tr12env_find_d2itm(env, sym)
in
  case+ dopt of
  | ~optn_vt_cons(d2i1) =>
    (
      case+ d2i1 of
      | D2ITMvar(d2v) => d2exp_var(loc, d2v)
      | D2ITMcst(d2cs) => d2exp_csts(loc, d2cs)
      | D2ITMcon(d2cs) => d2exp_cons(loc, d2cs)
      | D2ITMsym(_, _) =>
        let val () = PYF2_log("!! m0b: `x` resolved to D2ITMsym (unexpected)")
        in d2exp_none0(loc) end
    )
  | ~optn_vt_nil() =>
    let val () = PYF2_log("!! m0b: `x` did NOT resolve through the env (unbound)")
    in d2exp_none0(loc) end
end // end of [resolve_dexp_m0b]
//
(* ****** ****** *)
//
// ---- the M0b codegen spine -------------------------------------------------
//
// Build the codegen-correct d3parsed, then run the verified xats2js backend
// pass sequence and emit to `filr`. Returns the L3 nerror.
//
// Declared as a LOCAL `fun` with an explicit FILR annotation (not via the SATS):
// a cross-SATS call passing a FILR tripped a T2Pnone0 type-pack on the FILEref
// param identity; a same-DATS `fun` with the annotation resolves cleanly. The
// SATS still declares pyfront_m0b_emit for documentation of the M0b surface.
//
fun
pyfront_m0b_emit(filr: FILR): sint = let
//
// REUSE M0a's typecheck spine to exercise+report it (the hand-built `val x=1;
// val y=x` with D2Ei00 -> trans23 -> L3, nerror should be 0).
//
val dpar_m0a = pyfront_m0a_check()
val nerror_m0a = d3parsed_get_nerror(dpar_m0a)
val () = PYF2_log_int("[m0b] (reused) pyfront_m0a_check nerror =", nerror_m0a)
//
// 1) the codegen-correct program: D2Eint token literal -> trans23 -> L3.
//
val dpar = d3parsed_of_trans23(build_d2parsed_codegen())
//
val nerror = d3parsed_get_nerror(dpar)
val () = PYF2_log_int("[m0b] codegen d3parsed nerror =", nerror)
//
// 2) template/read passes (L3 -> L3). Same names+order as mymain_work.
//
val dpar = d3parsed_of_tread3a(dpar)
val () = PYF2_log("[m0b] tread3a done")
val dpar = d3parsed_of_trtmp3b(dpar)
val () = PYF2_log("[m0b] trtmp3b done")
val dpar = d3parsed_of_trtmp3c(dpar)
val () = PYF2_log("[m0b] trtmp3c done")
val dpar = d3parsed_of_t3read0(dpar)
val () = PYF2_log("[m0b] t3read0 done")
//
// 3) xats2cc lowering: L3 -> intrep0, then intrep0 type-resolve.
//
val ipar = i0parsed_of_trxd3i0(dpar)
val () = PYF2_log("[m0b] trxd3i0 (L3 -> intrep0) done")
val ipar = i0parsed_of_tryd3i0(ipar)
val () = PYF2_log("[m0b] tryd3i0 (intrep0 resolve) done")
//
// 4) xats2js lowering: intrep0 -> intrep1.
//
val ipar = i1parsed_of_trxi0i1(ipar)
val () = PYF2_log("[m0b] trxi0i1 (intrep0 -> intrep1) done")
//
// 5) emit the user program's JS to `filr` (caller passes g_stdout()).
//
val () = PYF2_mark("//==PYF2-JS-BEGIN==")
val () = i1parsed_js1emit(ipar, filr)
val () = PYF2_mark("//==PYF2-JS-END==")
val () = PYF2_log("[m0b] js1emit done (emitted user-program JS to stdout)")
//
in
  nerror
end // end of [pyfront_m0b_emit]
//
(* ****** ****** *)
//
// ---- main : run the codegen spine once -------------------------------------
//
fun
mymain_m0b((*void*)): void = let
//
// ONE-TIME global bootstrap (idempotent, gated by the_ntime). Required before
// any name resolution; harmless to keep parity with the stock driver. M0a's
// auto-run mymain_main already did this, but M0b must be self-sufficient too.
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYF2_log("######## M0b codegen-spine driver ########")
val () = PYF2_log("program (reused from M0a): val x = 1 ; val y = x")
//
// the emit target: process.stdout (clean text; markers/logs go to stderr).
//
val filr = g_stdout<>()
//
val nerror = pyfront_m0b_emit(filr)
//
val () =
  if (nerror = 0)
  then PYF2_log("RESULT: PASS (codegen spine: d3parsed -> xats2js -> JS, nerror=0)")
  else PYF2_log("RESULT: FAIL (nerror>0 feeding codegen)")
//
in
  (* nothing *)
end // end of [mymain_m0b]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m0b()
//
(* ****** ****** *)
//
(*
end of [frontend/DATS/pyfront_m0b.dats]
*)
