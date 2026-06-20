(* ****** ****** *)
(*
** M3 — Python-surface frontend: the REAL pipeline driver + codegen harness (DATS).
**
** Implements the SATS pipeline entries, then a main that:
**   (1) reads a .py file (argv[2]) via FFI,
**   (2) runs the full pipeline to a d3parsed (pyfront_d3parsed_of_fpath),
**   (3) reports nerror + the stock f3perr0 diagnostics (so a type error prints on the .py
**       span — deliverable 4b),
**   (4) if nerror=0, runs the VERIFIED M0b xats2js backend pass sequence and emits the
**       program's JavaScript between sentinels (deliverable 4a end-to-end run).
**
** RE-ENTRANT: a fresh tr12env per pipeline call (the lex/parse/elab passes are pure;
** lowering only push/pops scopes + binds locally), the global bootstrap done once. The
** backend pass spine is IDENTICAL to pyfront_m0b.dats (verified names+order).
**
** PURELY ADDITIVE; CALLS the compiler+backend (libxatsopt + lib2xats2cc + lib2xats2js) +
** the frontend passes. Nothing under srcgen2/ is modified.
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
// t3read0 is NOT in libxatsopt.hats; staload explicitly (same as M0b).
#staload "./../../srcgen2/SATS/t3read0.sats"
//
// the xats2js BACKEND SATS (NOT in libxatsopt.hats; must be in THIS DATS — a .sats's nested
// staloads do not re-export). Same set+order as pyfront_m0b.dats.
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/intrep0.sats"
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/trxd3i0.sats"
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/tryd3i0.sats"
//
#staload "./../../srcgen2/xats2js/srcgen2/SATS/intrep1.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/trxi0i1.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/xats2js.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/js1emit.sats"
//
// the frontend passes (lex/parse/elab/lower) + the pipeline SATS.
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
#staload "./../SATS/pylower.sats"
#staload "./../SATS/pyfront_m3.sats"
//
(* ****** ****** *)
//
// FFI: progress markers + the emitted-JS sentinels (stdout) ; file/argv read (reuse M1 glue
// PYL_readfile/PYL_argv_path) ; M3-owned log markers. Implemented in CATS/pyfront_m3.cats.
//
#extern fun PYM_log(s: strn): void = $extnam()
#extern fun PYM_log_int(s: strn, n: sint): void = $extnam()
#extern fun PYM_mark(s: strn): void = $extnam()
#extern fun PYM_readfile(path: strn): strn = $extnam()
#extern fun PYM_argv_path((*0*)): strn = $extnam()
//
(* ****** ****** *)
//
// ---- the pipeline -----------------------------------------------------------
//
#implfun
pyfront_d2parsed_of_fpath(stadyn, src, text) = let
  //
  // lex + parse (pyparse_module = pylex_layout + parse) -> PyAST ; elaborate -> PyCore.
  val ast  = pyparse_module(src, text)
  val core = pyelab_module(ast)
  //
  val+ PCModule(decls, _diags) = core
  //
  // lower : a FRESH tr12env (prelude fall-through), lower the decl list, free the top env.
  val env = tr12env_make_nil()
  val d2cs = pylower_decls(env, decls)
  val t2penv = tr12env_free_top(env)
  //
  val t1penv = tr01env_free_top(tr01env_make_nil())  // empty L1 fixity env (plan §6.6)
  //
in
  d2parsed_make_args(stadyn, 0(*nerror*), src, t1penv, t2penv, optn_cons(d2cs))
end
//
// M3-verified pipeline: d3parsed_of_trans23 IS the L2->L3 check; it internally drives the
// overload/symbol resolution stage for the directly-constructed L2 nodes (same as the M0b /
// spike drivers, which call it directly). The unbound-name recovery node (d2exp_none0 from
// pl_var's nil arm) flows through to a D3Et2pck errck that tread3a counts (deliverable 4b).
#implfun
pyfront_d3parsed_of_fpath(stadyn, src, text) =
  d3parsed_of_trans23(pyfront_d2parsed_of_fpath(stadyn, src, text))
//
(* ****** ****** *)
//
// ---- the codegen spine (verified M0b pass sequence) ------------------------
//
// drive a type-checked d3parsed through the xats2js backend and emit its JS to `filr`.
// IDENTICAL pass names+order as pyfront_m0b.dats (re-verified against the live SATS). The
// caller has ALREADY run tread3a (the error-counting pass) and verified nerror=0, so this
// re-runs it (idempotent: a clean d3parsed gains no new errck) and proceeds.
//
fun
emit_js(dpar0: d3parsed, filr: FILR): void = let
  // dpar0 already had tread3a run by the caller; continue the spine from trtmp3b.
  val dpar = d3parsed_of_trtmp3b(dpar0)
  val () = PYM_log("[m3] trtmp3b done")
  val dpar = d3parsed_of_trtmp3c(dpar)
  val () = PYM_log("[m3] trtmp3c done")
  val dpar = d3parsed_of_t3read0(dpar)
  val () = PYM_log("[m3] t3read0 done")
  val ipar = i0parsed_of_trxd3i0(dpar)
  val () = PYM_log("[m3] trxd3i0 (L3 -> intrep0) done")
  val ipar = i0parsed_of_tryd3i0(ipar)
  val () = PYM_log("[m3] tryd3i0 (intrep0 resolve) done")
  val ipar = i1parsed_of_trxi0i1(ipar)
  val () = PYM_log("[m3] trxi0i1 (intrep0 -> intrep1) done")
  val () = PYM_mark("//==PYM-JS-BEGIN==")
  val () = i1parsed_js1emit(ipar, filr)
  val () = PYM_mark("//==PYM-JS-END==")
  val () = PYM_log("[m3] js1emit done (emitted user-program JS to stdout)")
in
  (* nothing *)
end
//
(* ****** ****** *)
//
// ---- main -------------------------------------------------------------------
//
fun
mymain_m3((*void*)): void = let
  //
  // one-time global bootstrap (idempotent; required before name resolution).
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
  //
  val () = PYM_log("######## M3 pipeline driver (.py -> L2 -> L3 -> JS) ########")
  val path = PYM_argv_path()
  //
in
  if path = "" then
    PYM_log("!! M3: no input path (expected process.argv[2] = a .py file)")
  else let
    val () = (PYM_log("[m3] source = "); PYM_log(path))
    val text = PYM_readfile(path)
    val src  = LCSRCsome1(path)
    //
    // the full pipeline to a type-checked L3 (trans23 internally runs trans2a overload-
    // resolution + trsym2b + the L2->L3 check).
    val dpar23 = pyfront_d3parsed_of_fpath(1(*stadyn:dynamic*), src, text)
    //
    // CRITICAL: trans23 stores errors in errck NODES, not in the d2parsed `nerror` field
    // (which our d2parsed_make_args hardcoded to 0). The `tread3a` pass SCANS the parsed
    // decls for errck nodes and UPDATES nerror (tread3a.dats:155-171). So run tread3a FIRST,
    // then read the REAL nerror and report — otherwise nerror is a false 0.
    val dpar3 = d3parsed_of_tread3a(dpar23)
    val nerror = d3parsed_get_nerror(dpar3)
    val () = PYM_log_int("[m3] d3parsed nerror (after tread3a) =", nerror)
    //
    // the stock reporter (stderr) — a type error prints here ON THE .py SPAN (it prints the
    // errck nodes when nerror>0, each carrying its real Python `.lctn()`).
    val out0 = g_stderr()
    val () = PYM_log("[m3] -- f3perr0_d3parsed (stock reporter, stderr) --")
    val () = f3perr0_d3parsed(out0, dpar3)
    //
  in
    if nerror = 0 then let
      val () = PYM_log("[m3] typecheck OK (nerror=0) -> running codegen")
      val filr = g_stdout<>()
      val () = emit_js(dpar3, filr)
    in
      PYM_log("RESULT: PASS (.py -> JS, nerror=0)")
    end // then
    else
      PYM_log("RESULT: TYPE-ERROR (nerror>0 ; see f3perr0 above for the .py span)")
  end
end // end of [mymain_m3]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m3()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_m3.dats]
*)
