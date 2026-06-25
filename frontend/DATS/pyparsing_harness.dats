(* ****** ****** *)
(*
** M2 — Python-surface frontend: the PARSER GOLDEN-TEST HARNESS (DATS).
**
** Reads ONE .py-surface snippet (path = process.argv[2], via the FFI), parses it with
** `pyparse_module`, and dumps the PyAST (decls + recovery diagnostics) to stdout. The
** build harness (frontend/build-m2.sh) runs this once per snippet and diffs the dump
** against a checked-in golden file in frontend/TEST/.
**
** Reuses the M1 FFI glue (frontend/CATS/pylexing.cats): PYL_load / PYL_byte_at /
** PYL_slice feed the lexer; PYL_readfile / PYL_argv_path drive the harness.
**
** PURELY ADDITIVE; only CALLS the parser + lexer + location model.
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
  PYL_println("!! M2 harness: no input path (expected process.argv[2])")
else let
  val text = PYL_readfile(path)
  val src  = LCSRCsome1(path)
  val ast  = pyparse_module(src, text)
in
  ps(out, "==== "); ps(out, path); ps(out, " ====\n");
  pymodule_fprint(out, ast);
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
//
(*
end of [frontend/DATS/pyparsing_harness.dats]
*)
