(* ****** ****** *)
(*
** M6a — Python-surface frontend: the TYPECHECK-ONLY LSP entry (DATS).
**
** Implements the pyfront_lsp.sats pipeline entries. This is the LEAN driver the
** resident LSP server links: the full front-end (lex/parse/elab/lower + the L2
** post-passes + trans23 + tread3a) WITHOUT the xats2js codegen backend and
** WITHOUT a top-level `main` (so linking it does not execute anything at load
** time). The one-time global bootstrap + the pyrt runtime-prelude load happen
** LAZILY on the first pipeline call, guarded by a module-level ref.
**
** RE-ENTRANT: a fresh tr12env per pipeline call (the lex/parse/elab passes are
** pure; lowering only push/pops scopes + binds locally), the global bootstrap +
** pyrt load done ONCE (idempotent guard). The pipeline spine is the SAME as
** pyfront_m3's typecheck path PLUS a trailing d3parsed_of_tread3a (so the
** returned d3parsed's errck nodes count into nerror exactly as the stock
** d3parsed_of_fil{dats,sats} -> d3parsed_of_trans03 path produces — see the SATS
** header). No codegen SATS are staloaded here (intrep/trxd3i0/js1emit are only
** needed by pyfront_m3's emit_js, which the LSP never calls).
**
** PURELY ADDITIVE; CALLS the compiler-as-a-library + the frontend passes. Nothing
** under srcgen2/ is modified.
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
// the frontend passes (lex/parse/elab/lower) + the pipeline SATS.
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
#staload "./../SATS/pylower.sats"
#staload "./../SATS/pyfront_lsp.sats"
//
(* ****** ****** *)
//
// FFI: file read (the didOpen/didSave path has only the URI). Implemented in
// CATS/pyfront_lsp.cats. (Same readfile idiom as M1's pylexing.cats / M3's
// pyfront_m3.cats; kept separate so the LSP link does not pull M3's stdout
// sentinels / argv glue.)
//
#extern fun PYLSP_readfile(path: strn): strn = $extnam()
// faithful #include: set this file's stadyn so lower_include stamps D2Cinclude knd0 (pylexing.cats).
#extern fun PYL_cur_stadyn_set(n: sint): void = $extnam()
//
(* ****** ****** *)
//
// ---- lazy global bootstrap + pyrt load (mirrors pyfront_m3's mymain_m3 prologue
//      + pyrt_pvsload, but gated so it fires on the FIRST pipeline call, not at
//      module-load time). The guard is a module-level sint ref, declared exactly
//      like the compiler's own `the_ntime` (xglobal.dats:170) — the proven,
//      template-free a0ref_make_1val pattern. ----
//
local
  val the_pyfront_booted = a0ref_make_1val(0)
in
  fun
  pyfront_boot_once((*void*)): void =
    if the_pyfront_booted[] > 0 then () else let
      val () = (the_pyfront_booted[] := 1)
      // one-time global bootstrap (idempotent; required before name resolution).
      val _ = the_fxtyenv_pvsl00d()
      val _ = the_tr12env_pvsl00d()
      // M16: load the `pyrt` runtime prelude (flow datatype + iterator protocol +
      // list_foldleft) into the GLOBAL env so the desugared loops' pyrt names
      // resolve via the ordinary tr12env global fall-through. knd0=0 (STATIC): we
      // load the INTERFACE pyrt.sats (typed d2csts), enough to TYPECHECK. XATSHOME
      // is prepended by filpath_pvsload, so the path is XATSHOME-relative.
      val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
    in
      (* nothing *)
    end
end // end of [local: pyfront_boot_once]
//
(* ****** ****** *)
//
// ---- the typecheck pipeline -------------------------------------------------
//
// lex + parse (pyparse_module = pylex_layout + parse) -> PyAST ; elaborate ->
// PyCore ; lower -> d2eclist ; wrap into a d2parsed. SAME body as pyfront_m3's
// pyfront_d2parsed_of_fpath (kept local here so the LSP link is self-contained).
//
fun
pyfront_d2parsed_of_fpath
(stadyn: sint, src: lcsrc, text: strn): d2parsed = let
  //
  val () = PYL_cur_stadyn_set(stadyn)   // faithful #include: D2Cinclude knd0 = this file's stadyn
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
  val t1penv = tr01env_free_top(tr01env_make_nil())  // empty L1 fixity env
  //
in
  d2parsed_make_args(stadyn, 0(*nerror*), src, t1penv, t2penv, optn_cons(d2cs))
end
//
#implfun
pyfront_d3parsed_of_fpath(stadyn, src, text) = let
  //
  // ensure the global env + pyrt are loaded (idempotent; the FIRST call pays it).
  val () = pyfront_boot_once()
  //
  // the L2 post-passes (overload resolution + symbol resolution + the L2 read/
  // check) BEFORE trans23 — mirroring the stock trans03_from_fpath (#13a). Without
  // these, operators (D2ITMsym overloads) never resolve to a concrete d2cst and
  // fail typecheck.
  val dpar = pyfront_d2parsed_of_fpath(stadyn, src, text)
  val dpar = d2parsed_of_trans2a(dpar)   // overload resolution (L2)
  val ( ) = d2parsed_by_trsym2b(dpar)    // symbol resolution (L2)
  val dpar = d2parsed_of_t2read0(dpar)   // L2 read/check
  val dpar = d3parsed_of_trans23(dpar)   // L2 -> L3 translation/check
  //
  // CRITICAL (M6a): run tread3a so the errck nodes that trans23 leaves in the L3
  // tree are COUNTED into nerror — exactly as the stock d3parsed_of_trans03 path
  // does (xatsopt_utils0.dats / tread3a.dats:371). The resident's shared
  // harvest_d3parsed reads diagnostics from these counted errck nodes, so without
  // this a type-erroring .pdats would harvest CLEAN. (See the SATS header.)
  val dpar = d3parsed_of_tread3a(dpar)
  //
in
  dpar
end
//
#implfun
pyfront_d3parsed_of_fname(stadyn, path) = let
  val text = PYLSP_readfile(path)
  val src  = LCSRCsome1(path)
in
  pyfront_d3parsed_of_fpath(stadyn, src, text)
end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_lsp.dats]
*)
