(* ****** ****** *)
(*
** M6a — Python-surface frontend: the TYPECHECK-ONLY LSP entry (SATS).
**
** A LEANER companion to pyfront_m3.{sats,dats}: it provides ONLY the front-end
** typecheck pipeline (lex -> parse -> elab -> lower -> trans2a/trsym2b/t2read0 ->
** trans23 -> tread3a) and NO codegen backend, NO top-level `main` entry. This is
** what the resident LSP server links: it only TYPECHECKS .psats/.pdats buffers and
** harvests diagnostics from the returned d3parsed — it never emits JS.
**
** Two differences from pyfront_m3's entry that MATTER for the LSP:
**   (1) the returned d3parsed has `d3parsed_of_tread3a` RUN (the error-counting
**       pass). pyfront_m3's `pyfront_d3parsed_of_fpath` stops at trans23, which
**       leaves type errors as errck NODES whose count tread3a folds into nerror.
**       The stock d3parsed_of_fil{dats,sats} -> d3parsed_of_trans03 path DOES run
**       tread3a (xatsopt_utils0.dats / tread3a.dats:371), so to harvest IDENTICALLY
**       the Python entry must run it too. We run it HERE so the resident's shared
**       harvest_d3parsed picks up the type-error diagnostics with no special-casing.
**   (2) the one-time global bootstrap (the_fxtyenv_pvsl00d / the_tr12env_pvsl00d)
**       + the pyrt runtime-prelude load are done LAZILY on first call (a module
**       guard), so simply LINKING this DATS into the resident does not execute
**       anything at load time (pyfront_m3.dats's `val ... = mymain_m3()` would).
**
** PURELY ADDITIVE; CALLS the compiler-as-a-library + the frontend passes. Nothing
** under srcgen2/ is modified.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
(* ****** ****** *)
//
// the typecheck pipeline on in-memory text. `src` is the lcsrc source identity
// (LCSRCsome1(path)) the lexer stamps into every token's loctn, so spans flow
// into the L2/L3 nodes and a diagnostic lands on the .psats/.pdats span. The
// returned d3parsed has tread3a RUN (so its errck nodes count into nerror and the
// resident's harvest sees them).
//
fun
pyfront_d3parsed_of_fpath
(stadyn: sint, src: lcsrc, text: strn): d3parsed
//
// convenience: read the file at `path` (FFI), then run the pipeline with the
// source identity LCSRCsome1(path). Used by the resident's didOpen/didSave path,
// which has only the URI (not the buffer text).
//
fun
pyfront_d3parsed_of_fname
(stadyn: sint, path: strn): d3parsed
//
(* ****** ****** *)
(*
end of [frontend/SATS/pyfront_lsp.sats]
*)
