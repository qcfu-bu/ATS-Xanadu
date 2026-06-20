(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the ELABORATOR GOLDEN-TEST HARNESS (DATS).
**
** Reads ONE .py-surface snippet (path = process.argv[2]), parses it (pyparse_module),
** ELABORATES it (pyelab_module: PyAST -> PyCore), and dumps the PyCore module (decls +
** elaboration diagnostics) to stdout. build-m2_5.sh runs this once per snippet and diffs
** the dump against a checked-in golden.
**
** Reuses the M1 FFI glue (frontend/CATS/pylexing.cats) for file/argv access.
**
** PURELY ADDITIVE; only CALLS the parser + elaborator + printer + location model.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
//
(* ****** ****** *)
//
#extern fun PYL_readfile(path: strn): strn = $extnam()
#extern fun PYL_argv_path((*0*)): strn = $extnam()
#extern fun PYL_println(s: strn): void = $extnam()
//
(* ****** ****** *)
//
fun ps(out: FILR, s: strn): void = strn_fprint(s, out)
//
(* ****** ****** *)
//
fun
mymain_main((*void*)): void = let
//
val path = PYL_argv_path()
val out  = g_stdout()
//
in
//
if path = "" then
  PYL_println("!! M2.5 harness: no input path (expected process.argv[2])")
else let
  val text = PYL_readfile(path)
  val src  = LCSRCsome1(path)
  val ast  = pyparse_module(src, text)
  val core = pyelab_module(ast)
in
  ps(out, "==== "); ps(out, path); ps(out, " ====\n");
  pcmodule_fprint(out, core);
  ps(out, "\n")
end
//
end (* end of [mymain_main] *)
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_main()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_harness.dats]
*)
