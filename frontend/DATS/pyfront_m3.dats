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
// M7-closures: print the PyCore ELABORATION diagnostics (parse + poison-node messages, incl. the
// @func capture check) to stderr, each on its surface span. Without this the driver dropped the
// module's `pcdiaglst` (it only printed the L2 f3perr0 errcks), so a capture's name + span were
// invisible. Each PCEerror poison still independently errcks at tread3a (nerror>0).
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
  | _ => ( strn_fprint("[m3] -- elaboration diagnostics (parse + @func capture check, stderr) --\n", out);
           loop(out, diags) )
end
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
  val+ PCModule(decls, elab_diags) = core
  //
  // M7-closures: surface the ELABORATION diagnostics (parse + poison-node messages, incl. the
  // @func capture check) to stderr ON THE .pdats SPAN. These are distinct from the L2 f3perr0
  // errcks printed later: a capture is reported HERE with its name + span, AND its poison node
  // lowers to a none-node so tread3a also errcks it (nerror>0). Previously these were dropped.
  val () = pyfront_print_elab_diags(elab_diags)
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
// #13a SPIKE: run the THREE L2 post-passes (overload resolution + symbol resolution + the L2
// read/check) on our hand-built d2parsed BEFORE d3parsed_of_trans23 — mirroring the stock
// file-path driver trans03_from_fpath (srcgen2/DATS/trans23.dats:87-92). d3parsed_of_trans23
// itself does NOT run these (verified trans23.dats:104-137), so without them an operator
// (`+ - * / == < ...`, which resolves to a D2ITMsym overload symbol) is NEVER resolved to a
// concrete d2cst -> tread3a errcks -> operators FAIL typecheck. These passes do the resolution:
//   d2parsed_of_trans2a  : OVERLOAD resolution (D2ITMsym -> concrete d2cst) + literal-type +
//                          fresh-tyvar binders (trans12.sats:366; trans2a.dats)
//   d2parsed_by_trsym2b  : symbol resolution, in place (trans12.sats:369; trsym2b.dats)
//   d2parsed_of_t2read0  : the L2 read/check (t2read0.sats:162)
// All three are already staloaded via libxatsopt.hats (trans12.sats + t2read0.sats) — no new
// staload needed.
//
// 4b RECONCILIATION (the wrinkle): the STOCK trans12 emits `d2exp_none1(d1e0)` (D2Enone1) for an
// unbound name (trans12_dynexp.dats:2003 f0_id0_d1sym), NOT a bare d2exp_none0. trans2a has NO
// D2Enone1 arm -> it falls to `_(*otherwise*)` -> d2exp_none2 (trans2a_dynexp.dats:1352); trans23
// likewise -> d3exp_none1 (trans23_dynexp.dats:1237); tread3a has no D3Enone1 arm -> its
// `_(*otherwise*)` COUNTS it (err+1; tread3a_dynexp.dats:2077-2083). So the unbound-name errck
// survives trans2a verbatim. Our pl_var was changed to emit d2exp_none1 too (was d2exp_none0,
// which trans2a's f0_none0 stamps `void` + the fresh-tyvar binder then UNIFIES away the errck —
// the M4-recovery HARD LESSON, now obsolete). See M13a-REPORT.
#implfun
pyfront_d3parsed_of_fpath(stadyn, src, text) = let
  val dpar = pyfront_d2parsed_of_fpath(stadyn, src, text)
  val dpar = d2parsed_of_trans2a(dpar)   // overload resolution (L2)  — trans03_from_fpath:89
  val ( ) = d2parsed_by_trsym2b(dpar)    // symbol resolution (L2)    — trans03_from_fpath:90
  val dpar = d2parsed_of_t2read0(dpar)   // L2 read/check             — trans03_from_fpath:92
in
  d3parsed_of_trans23(dpar)
end
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
// ---- pyrt load (M16) --------------------------------------------------------
//
// load frontend/pyrt/pyrt.dats into the global env ONCE, after the prelude bootstrap. Mirrors
// the prelude's own f0_pvsload calls in the_tr12env_pvsl00d (xglobal.dats:1040-1068). Idempotent:
// a module-level ref guards against a re-load on a second pipeline call (re-entrancy, plan §6.2)
// — the global env already holds pyrt after the first call, so we MUST NOT merge it twice (a
// double-merge would shadow-warn / duplicate the d2cons). XATSHOME is prepended by
// filpath_pvsload, so the path is XATSHOME-relative.
//
// the load-once gate is a module-level sint ref (0 = not yet loaded, 1 = loaded), declared
// EXACTLY like the compiler's own `the_ntime` (xglobal.dats:170 `a0ref_make_1val(0)` + the
// `[]` get/set sugar) — the proven, template-free pattern (`ref<bool>` hits the same prelude
// `$`-template backend gap the operators do, M3-REPORT, and would errck the driver build).
local
  val the_pyrt_loaded = a0ref_make_1val(0)
in
  fun
  pyrt_pvsload((*void*)): void =
    if the_pyrt_loaded[] > 0 then () else let
      val () = (the_pyrt_loaded[] := 1)
      val () = PYM_log("[m16] loading pyrt runtime prelude (filpath_pvsload) ...")
      // knd0=0 (STATIC): we load the INTERFACE pyrt.sats, not the .dats. A `.sats` `fun foo(...)`
      // creates a TYPED d2cst CONSTANT (-> D2ITMcst, resolves + type-checks at the call site like
      // any prelude fun), whereas a `.dats` `fun foo(...) = ...` binds a LOCAL function d2var with
      // no exported type (-> D2ITMvar, errcks on use; M16 finding). The .sats self-contains the
      // flow/iterstep datatypes (their d2cons) + the fun signatures — enough to TYPECHECK the
      // desugared loops + list_foldleft (codegen is parked, #13b, so the .dats impl is not needed
      // here). LOOP-DESUGARING §9 + plan §5.5 (the stock ATS-dependency load path). (M16-REPORT.)
      val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
      val () = PYM_log("[m16] pyrt loaded (flow/iter/foldleft now resolve via global fall-through)")
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
mymain_m3((*void*)): void = let
  //
  // one-time global bootstrap (idempotent; required before name resolution).
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
  //
  // M16: load the `pyrt` runtime prelude (the flow datatype + flow_bind + the iterator
  // protocol + list_foldleft) into the GLOBAL env, exactly as the_tr12env_pvsl00d loads the
  // stock prelude (parse -> trans01/trans12 -> merge t2penv into the_sortenv/sexpenv/dexpenv;
  // xglobal.dats f0_pvsload). `filpath_pvsload(knd0, fpth)` is the EXPORTED wrapper of
  // f0_pvsload (xglobal.sats:172); it prepends XATSHOME to `fpth`. After this, the desugared
  // loops' pyrt names (`flow_next`/`iter_open`/`list_foldleft`/...) resolve via the ordinary
  // tr12env GLOBAL fall-through — no per-file staload needed, so PCCstaload stays a no-op
  // and the load is done ONCE (idempotent re-call below is guarded by pyrt_loaded). knd0=1
  // (dynamic) because pyrt.dats is a `.dats` carrying dynamic defs (funs + the datatype's
  // d2cons) that must land in the dexpenv. (M16-REPORT.)
  val () = pyrt_pvsload()
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
