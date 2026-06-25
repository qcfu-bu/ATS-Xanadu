(* ****** ****** *)
(*
** M1 — Python-surface frontend: the GOLDEN-TEST HARNESS (DATS).
**
** Reads ONE .py-surface snippet (path = process.argv[2], via the FFI), lexes it,
** and dumps the LAYOUT token stream (`token@span`, one per line) to stdout. The
** build harness (frontend/build-m1.sh) runs this once per snippet and diffs the
** dump against a checked-in golden file in frontend/TEST/.
**
** The dump uses `pylex_layout` (raw scan + off-side rule) — i.e. the exact stream
** M2 will consume — so the goldens pin down BOTH the tokens and the INDENT/DEDENT/
** NEWLINE layout with real (row:bytecol) spans.
**
** PURELY ADDITIVE; only CALLS the lexer + the location model.
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
  PYL_println("!! M1 harness: no input path (expected process.argv[2])")
else let
  val text = PYL_readfile(path)
  // the source identity stamped into every token span (so spans report on the .py).
  val src  = LCSRCsome1(path)
  val toks = pylex_layout(src, text)
in
  ps(out, "==== "); ps(out, path); ps(out, " ====\n");
  pytokenlst_fprint(out, toks)
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
end of [frontend/DATS/pylexing_harness.dats]
*)
