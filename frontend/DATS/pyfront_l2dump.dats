(* ****** ****** *)
(*
** L2DUMP — Pythonic-ATS round-trip FIDELITY harness: the raw-L2 structural dumper.
**
** Two modes, picked by argv[2]; the input file is argv[3]; argv[4] is the stadyn
** flag (0 = static .sats/.psats, 1 = dynamic .dats/.pdats):
**
**   stock   <F> <stadyn>  : print d2parsed_fprint(trans02_from_fpath(stadyn, F)).
**       = the d2parsed the STOCK compiler builds from the canonical ATS source F
**         (parse + trans01 + trans12, the RAW lowered L2, BEFORE the post-passes
**         tread12/trans2a/trsym2b/t2read0).
**
**   pyfront <P> <stadyn>  : print d2parsed_fprint(pyfront_d2parsed_of_fpath(stadyn,
**                            LCSRCsome1(P), readfile(P))).
**       = the d2parsed OUR Pythonic frontend builds from the pretty-printed pythonic
**         file P (= pyprint(F)). This is the SAME raw-L2 entry the M3 pipeline lowers
**         to BEFORE its `_d3parsed_` post-passes — we do NOT run any post-pass here.
**
** Both sides serialize with the SAME printer, d2parsed_fprint (dynexp2.sats:1945),
** which prints the full node tree D2PARSED(stadyn;nerror;source;parsed) where `parsed`
** recursively dumps every d2ec / d2exp / d2pat / d2con / d2cst / d2var node. We use
** d2parsed_fprint rather than f2perr0_d2parsed because the latter only emits anything
** when nerror>0 (f2perr0.dats:103) — a CLEAN file would print nothing — whereas
** d2parsed_fprint is the unconditional structural serializer (and is the alternative
** the task lists, dynexp2.sats:1945). Both calls feed it the SAME node printer, so the
** stock and pyfront dumps are byte-comparable once normalized (see build-l2diff.sh).
**
** If the two normalized dumps match, the Pythonic round-trip is structurally FAITHFUL
** (both pyprint AND our lowering); if they differ, the diff pinpoints the diverging
** construct. This is the automated form of the by-hand "diff our L2 vs stock".
**
** PURELY ADDITIVE; CALLS the compiler-as-a-library (libxatsopt) + the M1/M2/M2.5/M3
** frontend passes via pyfront_d2parsed_of_fpath. Nothing under srcgen2/ is modified;
** the M3 pipeline (pyfront_m3.dats) is untouched — this is a separate driver.
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
// the frontend passes (lex/parse/elab/lower) + the pipeline SATS. We staload
// pyfront_m3.sats for the `pyfront_d2parsed_of_fpath` SIGNATURE, but we IMPLEMENT
// it locally below (and do NOT link pyfront_m3.dats) so the M3 driver's `main`
// (which runs codegen via the xats2cc/xats2js backend libs we do not bundle) is
// never executed. The lowering body is identical to pyfront_m3.dats's #implfun.
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
#staload "./../SATS/pylower.sats"
#staload "./../SATS/pyfront_m3.sats"
//
(* ****** ****** *)
//
// FFI: progress markers + file/argv read. argv[2]=mode, argv[3]=path, argv[4]=stadyn.
// Implemented in CATS/pyfront_l2dump.cats (a tiny self-contained glue).
//
#extern fun PYL2_log(s: strn): void = $extnam()
#extern fun PYL2_readfile(path: strn): strn = $extnam()
#extern fun PYL2_argv_mode((*0*)): strn = $extnam()
#extern fun PYL2_argv_path((*0*)): strn = $extnam()
#extern fun PYL2_argv_stadyn((*0*)): sint = $extnam()
// faithful #include: set the CURRENT file's stadyn so `lower_include` stamps the D2Cinclude knd0
// with the INCLUDING file's stadyn (stock's `f00`), not the included file's. (pylexing.cats glue.)
#extern fun PYL_cur_stadyn_set(n: sint): void = $extnam()
//
(* ****** ****** *)
//
// pyfront_d2parsed_of_fpath — IMPLEMENTED HERE (body identical to pyfront_m3.dats:88;
// see the staload note above for why we re-implement rather than link pyfront_m3.dats).
// lex (pyparse_module) -> elaborate (pyelab_module) -> lower (a FRESH tr12env, prelude
// fall-through) -> d2parsed_make_args. This is the RAW lowered L2, BEFORE any post-pass.
fun
pyfront_print_elab_diags(diags: list(pcdiag)): void = let
  val out = g_stderr()
  fun loop(out: FILR, gs: list(pcdiag)): void =
    ( case+ gs of
      | list_nil() => ()
      | list_cons(g, rest) =>
          ( strn_fprint("[elab-diag] ", out); pcdiag_fprint(out, g);
            strn_fprint("\n", out); loop(out, rest) ) )
in
  case+ diags of
  | list_nil() => ()
  | _ => loop(out, diags)
end
//
#implfun
pyfront_d2parsed_of_fpath(stadyn, src, text) = let
  val () = PYL_cur_stadyn_set(stadyn)   // faithful #include: D2Cinclude knd0 = this file's stadyn
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
(* ****** ****** *)
//
// the M3 pipeline loads pyrt (the flow/iterator/foldleft runtime prelude) into the
// GLOBAL env so the desugared loops' names resolve via tr12env fall-through. Our
// pyfront dump runs the SAME lowering, so we must load pyrt too — otherwise a file
// using loops would lower its pyrt names to unbound (none) nodes and the dump would
// (spuriously) differ from stock. Mirrors pyfront_m3.dats's pyrt_pvsload (load-once,
// guarded by a module-level sint ref a0ref_make_1val — the template-free pattern).
local
  val the_pyrt_loaded = a0ref_make_1val(0)
in
  fun
  pyrt_pvsload((*void*)): void =
    if the_pyrt_loaded[] > 0 then () else let
      val () = (the_pyrt_loaded[] := 1)
      val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
    in
      (* nothing *)
    end
end // end of [local: pyrt_pvsload]
//
(* ****** ****** *)
//
fun
mymain_l2dump((*void*)): void = let
  //
  // one-time global bootstrap (idempotent; required before name resolution + lowering).
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
  val () = pyrt_pvsload()
  //
  val mode   = PYL2_argv_mode()
  val path   = PYL2_argv_path()
  val stadyn = PYL2_argv_stadyn()
  //
  val () = (PYL2_log("[l2dump] mode="); PYL2_log(mode);
            PYL2_log(" path="); PYL2_log(path); PYL2_log("\n"))
  //
  val out = g_stdout<>()
  //
in
  if path = "" then
    PYL2_log("!! l2dump: no input path (expected argv[3] = a source file)\n")
  else if mode = "stock" then let
    // STOCK raw L2: parse + trans01 + trans12 from the canonical ATS source file.
    // trans02_from_fpath(stadyn, source) — trans12.sats:1126 — yields the d2parsed
    // BEFORE the post-passes (exactly the raw lowering we want to compare against).
    val dpar = trans02_from_fpath(stadyn, path)
    val () = d2parsed_fprint(dpar, out)
    val () = strn_fprint("\n", out)
  in
    PYL2_log("[l2dump] stock dump done\n")
  end // end-of-[stock]
  else if mode = "pyfront" then let
    // PYTHONIC raw L2: lex/parse/elab/lower the pythonic file through OUR frontend.
    // pyfront_d2parsed_of_fpath is the M3 entry BEFORE the _d3parsed_ post-passes.
    val text = PYL2_readfile(path)
    val src  = LCSRCsome1(path)
    val dpar = pyfront_d2parsed_of_fpath(stadyn, src, text)
    val () = d2parsed_fprint(dpar, out)
    val () = strn_fprint("\n", out)
  in
    PYL2_log("[l2dump] pyfront dump done\n")
  end // end-of-[pyfront]
  else
    (PYL2_log("!! l2dump: unknown mode (expected 'stock' or 'pyfront'): ");
     PYL2_log(mode); PYL2_log("\n"))
end // end of [mymain_l2dump]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_l2dump()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_l2dump.dats]
*)
