(* ****** ****** *)
(*
** pyfront_cz — Python-surface frontend driven ALL THE WAY to Chez Scheme.
**
** THE BOOTSTRAP STEP "emit chez": it fuses the two halves that already work
** independently —
**   (frontend) pyfront_m3.dats : Pythonic source -> d3parsed (typechecked L3)
**   (backend)  xats2cz         : d3parsed -> trxd3i0 -> intrep0 -> cz0emit -> Chez
** — into one pipeline.  The xats2cz backend is the COMPLETE one (it self-hosts
** 171 files + passes 77/77 tests), and it uses ONLY i0parsed_of_trxd3i0 (NO
** tryd3i0), so it sidesteps the i0varfst_mklst codegen-lib gap that crippled the
** xats2cc/intrep1 JS path (#13b).
**
** Pipeline (per .pdats file):
**   pyparse_module -> pyelab_module -> pylower_decls -> d2parsed
**     -> tread12 -> trans2a -> trsym2b -> t2read0 -> trans23   (stock L2 post-passes)
**     -> tread3a  (count nerror; bail if >0)
**     -> trtmp3b -> trtmp3c -> t3read0                          (template resolve)
**     -> i0parsed_of_trxd3i0                                    (D3 -> intrep0, xats2js srcgen1)
**     -> i0parsed_cz0emit                                       (intrep0 -> Chez, stdout)
**
** RE-ENTRANT frontend (fresh tr12env per call); the global bootstrap + the
** _XATS2JS_ backend flags are set once.  PURELY ADDITIVE: nothing under srcgen2/
** is modified; it CALLS the compiler + the xats2js srcgen1 backend + cz0emit.
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
// t3read0 is NOT in libxatsopt.hats; staload explicitly (same as M3).
#staload "./../../srcgen2/SATS/t3read0.sats"
//
// the xats2cz backend: the COMPLETE xats2js srcgen1 intrep0 + trxd3i0, then cz0emit.
// (NOT xats2cc; NOT xats2js srcgen2 intrep1 — cz0emit emits Scheme directly from intrep0.)
#staload "./../../srcgen2/xats2js/srcgen1/SATS/intrep0.sats"
#staload "./../../srcgen2/xats2js/srcgen1/SATS/trxd3i0.sats"
#staload "./../../srcgen2/xats2cz/SATS/cz0emit.sats"
//
// the frontend passes (lex/parse/elab/lower) + the pipeline SATS.
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
#staload "./../SATS/pylower.sats"
//
(* ****** ****** *)
//
// FFI: progress markers + file/argv read (reuse the M3 glue PYM_*). Implemented in
// CATS/pyfront_m3.cats. PYL_cur_stadyn_set is in CATS/pylexing.cats.
//
#extern fun PYM_log(s: strn): void = $extnam()
#extern fun PYM_log_int(s: strn, n: sint): void = $extnam()
#extern fun PYM_readfile(path: strn): strn = $extnam()
#extern fun PYM_argv_path((*0*)): strn = $extnam()
#extern fun PYL_cur_stadyn_set(n: sint): void = $extnam()
//
(* ****** ****** *)
//
// print the PyCore ELABORATION diagnostics (parse + poison-node messages) to stderr.
fun
pyfront_print_elab_diags(diags: list(pcdiag)): void = let
  val out = g_stderr()
  fun loop(out: FILR, gs: list(pcdiag)): void =
    ( case+ gs of
      | list_nil() => ()
      | list_cons(g, rest) =>
          ( strn_fprint("[elab-diag] ", out); pcdiag_fprint(out, g); strn_fprint("\n", out);
            loop(out, rest) ) )
in
  case+ diags of
  | list_nil() => ()
  | _ => ( strn_fprint("[cz] -- elaboration diagnostics (parse + @func capture check, stderr) --\n", out);
           loop(out, diags) )
end
//
(* ****** ****** *)
//
// ---- the frontend pipeline (IDENTICAL to pyfront_m3, re-authored locally) ----
//
fun
cz_d2parsed_of_fpath
(stadyn: sint, src: lcsrc, text: strn): d2parsed = let
  val () = PYL_cur_stadyn_set(stadyn)
  val ast  = pyparse_module(src, text)
  val core = pyelab_module(ast)
  val+ PCModule(decls, elab_diags) = core
  val () = pyfront_print_elab_diags(elab_diags)
  val env = tr12env_make_nil()
  val d2cs = pylower_decls(env, decls)
  val t2penv = tr12env_free_top(env)
  val t1penv = tr01env_free_top(tr01env_make_nil())
in
  d2parsed_make_args(stadyn, 0(*nerror*), src, t1penv, t2penv, optn_cons(d2cs))
end
//
fun
cz_d3parsed_of_fpath
(stadyn: sint, src: lcsrc, text: strn): d3parsed = let
  // Run the COMPLETE stock pipeline the codegen path uses — `d3parsed_of_trans03`
  // (xatsopt_utils0.dats:307-392, what d3parsed_of_fildats runs), NOT the shorter
  // `trans03_from_fpath`. The first five passes ARE trans03_from_fpath (trans23.dats:87-92);
  // the crucial additions are tread23 + trans3a. **trans3a builds the t3penv** (the impl-name
  // map) and RECURSES into staloads (trans3a_decl00.dats:338) to build THEIR t3penvs — which
  // is exactly what `static_search_dcst` reads to resolve a prelude template's #impltmp brought
  // in via an `include`'s nested #staloads. Omitting it left every staloaded template instance
  // unresolved at codegen (the #13b "$-template" gap). tread3a (the error count) runs after.
  val dpar = cz_d2parsed_of_fpath(stadyn, src, text)
  val dpar = d2parsed_of_tread12(dpar)   // L1->L2 read/check     (trans03_from_fpath:87)
  val dpar = d2parsed_of_trans2a(dpar)   // overload resolution   (trans03_from_fpath:89)
  val ( ) = d2parsed_by_trsym2b(dpar)    // symbol resolution     (trans03_from_fpath:90)
  val dpar = d2parsed_of_t2read0(dpar)   // L2 read/check         (trans03_from_fpath:92)
  val dpar = d3parsed_of_trans23(dpar)   // L2 -> L3
  val dpar = d3parsed_of_tread23(dpar)   // L3 read/check         (d3parsed_of_trans03:380)
  val dpar = d3parsed_of_trans3a(dpar)   // BUILD t3penv (+ staload t3penvs) (d3parsed_of_trans03:389)
in
  dpar
end
//
(* ****** ****** *)
//
// ---- the chez codegen spine (xats2cz mymain_work) --------------------------
//
// dpar0 already had tread3a run by the caller (nerror verified 0); continue from trtmp3b.
fun
emit_cz(dpar0: d3parsed, filr: FILR): void = let
  val dpar = d3parsed_of_trtmp3b(dpar0)
  val () = PYM_log("[cz] trtmp3b done")
  val dpar = d3parsed_of_trtmp3c(dpar)
  val () = PYM_log("[cz] trtmp3c done")
  val dpar = d3parsed_of_t3read0(dpar)
  val () = PYM_log("[cz] t3read0 done")
  val ipar = i0parsed_of_trxd3i0(dpar)
  val () = PYM_log("[cz] trxd3i0 (L3 -> intrep0) done")
  val () = i0parsed_cz0emit(ipar, filr)
  val () = PYM_log("[cz] cz0emit done (emitted Chez Scheme to stdout)")
in
  (* nothing *)
end
//
(* ****** ****** *)
//
// ---- pyrt load (M16) — same as pyfront_m3 ----------------------------------
//
local
  val the_pyrt_loaded = a0ref_make_1val(0)
in
  fun
  pyrt_pvsload((*void*)): void =
    if the_pyrt_loaded[] > 0 then () else let
      val () = (the_pyrt_loaded[] := 1)
      val () = PYM_log("[cz] loading pyrt runtime prelude (filpath_pvsload) ...")
      val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
      val () = PYM_log("[cz] pyrt loaded")
    in
      (* nothing *)
    end
end // end of [local: pyrt_pvsload]
//
(* ****** ****** *)
//
// ---- main -------------------------------------------------------------------
//
fun
mymain_cz((*void*)): void = let
  //
  // one-time global bootstrap (the srcgen2 prelude tree — pvsl00d, NOT 01d).
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
  //
  // the xats2cz backend flags: the complete JS compile-time CATS resolves the
  // prelude/template instances against these (xats2cz_czemit01.dats:158-160).
  val () = xatsopt_flag$pvsadd0("--_XATS2JS_")
  val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATS2JS_")
  //
  // NB: NO global JS-prelude merge. The prelude is brought in FAITHFULLY by the source's
  // own `include` decls (the pythonic spelling of `#include`), exactly like a stock .dats:
  // lower_include splices the prelude's #extern/#impltmp decls into THIS file's d2parsed,
  // so name + TEMPLATE resolution work through the unchanged backend. We never touch L3.
  val () = pyrt_pvsload()
  //
  val () = PYM_log("######## pyfront_cz driver (.pdats -> L2 -> L3 -> intrep0 -> Chez) ########")
  val path = PYM_argv_path()
  //
in
  if path = "" then
    PYM_log("!! cz: no input path (expected process.argv[2] = a .pdats file)")
  else let
    val () = (PYM_log("[cz] source = "); PYM_log(path))
    val text = PYM_readfile(path)
    val src  = LCSRCsome1(path)
    //
    val dpar23 = cz_d3parsed_of_fpath(1(*stadyn:dynamic*), src, text)
    //
    // tread3a SCANS for errck nodes and updates nerror (our d2parsed hardcoded 0).
    val dpar3 = d3parsed_of_tread3a(dpar23)
    val nerror = d3parsed_get_nerror(dpar3)
    val () = PYM_log_int("[cz] d3parsed nerror (after tread3a) =", nerror)
    //
    val out0 = g_stderr()
    val () = PYM_log("[cz] -- f3perr0_d3parsed (stock reporter, stderr) --")
    val () = f3perr0_d3parsed(out0, dpar3)
    //
  in
    if nerror = 0 then let
      val () = PYM_log("[cz] typecheck OK (nerror=0) -> running cz0emit codegen")
      val filr = g_stdout<>()
      val () = emit_cz(dpar3, filr)
    in
      PYM_log("RESULT: PASS (.pdats -> Chez Scheme, nerror=0)")
    end // then
    else
      PYM_log("RESULT: TYPE-ERROR (nerror>0 ; see f3perr0 above for the .pdats span)")
  end
end // end of [mymain_cz]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_cz()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_cz.dats]
*)
