(* ****** ****** *)
(*
** M7-import (task #34) — multi-file `import` driver / TEST harness.
**
** Checks TWO Python-surface files in ONE process (the re-entrancy gate for the SCOPED
** module-merge):
**
**   PROBE U (use)    : argv[2] — a file that `from <mod> import lib_double` then USES
**                      `lib_double(x)`. The scoped merge must make it RESOLVE -> nerror=0.
**   PROBE N (no-leak): argv[3] — a file that does NOT import the module yet references
**                      `lib_double`. Checked in the SAME process AFTER probe U. If the merge
**                      were GLOBAL (the `filpath_pvsload` pervasive bug), `lib_double` would
**                      leak into this file's env -> nerror=0 (WRONG). The SCOPED merge keeps it
**                      per-file, so it stays UNRESOLVED here -> nerror>0 (CORRECT).
**
** Typecheck-only (no codegen): runs the SAME L2->L3 pipeline as pyfront_m3 (lex/parse/elab/
** lower -> trans2a/trsym2b/t2read0 -> trans23 -> tread3a), then reports nerror. The frontend
** passes (incl. the new import lowering in pylower_decl00) are shared verbatim. RE-ENTRANT: a
** fresh tr12env per file (built inside pyfront_d2parsed_of_fpath); the global bootstrap + pyrt
** load done ONCE. Nothing under srcgen2/ is modified.
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
// the frontend passes (lex/parse/elab/lower) + the shared M3 pipeline (pyfront_d3parsed_of_fpath
// + tread3a). pyfront_m3.sats's impls live in pyfront_m3.dats, which is NOT linked into THIS
// bundle (no codegen here) — so we re-declare the typecheck-only pipeline inline below.
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
#staload "./../SATS/pylower.sats"
//
(* ****** ****** *)
//
#extern fun PYI_log(s: strn): void = $extnam()
#extern fun PYI_log_int(s: strn, n: sint): void = $extnam()
#extern fun PYI_readfile(path: strn): strn = $extnam()
#extern fun PYI_argv(i: sint): strn = $extnam()
// 1 iff env PYI_DUMP is set — dumps the use-file's lowered d2parsed (so a grep can CONFIRM a real
// D2Cstaload node is emitted for the user import, NOT a D2Cnone0). Off by default (no noise).
#extern fun PYI_dump((*0*)): sint = $extnam()
//
(* ****** ****** *)
//
// the typecheck-only pipeline (mirrors pyfront_m3.dats:66-115, minus the codegen spine).
//
fun
pyi_d2parsed_of_fpath(stadyn: sint, src: lcsrc, text: strn): d2parsed = let
  val ast  = pyparse_module(src, text)
  val core = pyelab_module(ast)
  val+ PCModule(decls, _diags) = core
  val env = tr12env_make_nil()           // FRESH env per file — the re-entrancy invariant
  val d2cs = pylower_decls(env, decls)   // the import lowering's SCOPED merge lands in THIS env
  val t2penv = tr12env_free_top(env)
  val t1penv = tr01env_free_top(tr01env_make_nil())
in
  d2parsed_make_args(stadyn, 0(*nerror*), src, t1penv, t2penv, optn_cons(d2cs))
end
//
fun
pyi_d3parsed_of_fpath(stadyn: sint, src: lcsrc, text: strn): d3parsed = let
  val dpar = pyi_d2parsed_of_fpath(stadyn, src, text)
  val dpar = d2parsed_of_trans2a(dpar)   // overload resolution (L2)
  val ( ) = d2parsed_by_trsym2b(dpar)    // symbol resolution (L2)
  val dpar = d2parsed_of_t2read0(dpar)   // L2 read/check
in
  d3parsed_of_trans23(dpar)
end
//
// check one file end-to-end, print + return its post-tread3a nerror.
fun
check_file(label: strn, path: strn): sint = let
  val () = (PYI_log("---- "); PYI_log(label); PYI_log(path))
  val text = PYI_readfile(path)
  val src  = LCSRCsome1(path)
  // DEP-GRAPH NODE EVIDENCE: when PYI_DUMP is set, dump THIS file's lowered L2 decls; grep the
  // output for `D2Cstaload(` to confirm the user import emits a real staload node (not D2Cnone0).
  val () =
    if PYI_dump() > 0 then let
      val dpar2 = pyi_d2parsed_of_fpath(1(*stadyn:dynamic*), src, text)
      val () = PYI_log(strn_append("==DUMP d2parsed== ", label))
      val () = d2parsed_fprint(dpar2, g_stderr())
      val () = PYI_log("==END DUMP==")
    in (* nothing *) end
  val dpar23 = pyi_d3parsed_of_fpath(1(*stadyn:dynamic*), src, text)
  val dpar3 = d3parsed_of_tread3a(dpar23)
  val nerror = d3parsed_get_nerror(dpar3)
  val () = PYI_log_int(strn_append(label, " nerror (after tread3a) ="), nerror)
  // print the f3perr0 diagnostics on stderr so an UNRESOLVED name in the no-leak file is visible.
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dpar3))
in
  nerror
end
//
(* ****** ****** *)
//
// pyrt load-once (mirrors pyfront_m3.dats:164-184): the auto-pyrt staload still works because the
// driver loads pyrt GLOBALLY once at startup. We REUSE this to prove auto-pyrt is unaffected.
local
  val the_pyrt_loaded = a0ref_make_1val(0)
in
  fun
  pyrt_pvsload((*void*)): void =
    if the_pyrt_loaded[] > 0 then () else let
      val () = (the_pyrt_loaded[] := 1)
      val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
    in (* nothing *) end
end
//
(* ****** ****** *)
//
fun
mymain_m7imp((*void*)): void = let
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
  val () = pyrt_pvsload()
  //
  val () = PYI_log("######## M7-import (multi-file) driver — SCOPED merge + no-leak gate ########")
  //
  val pU = PYI_argv(2)
  val pN = PYI_argv(3)
in
  if pU = "" then
    PYI_log("!! M7-import: expected argv[2]=use-file argv[3]=no-leak-file")
  else if pN = "" then
    PYI_log("!! M7-import: expected argv[3]=no-leak-file (both files required in ONE process)")
  else let
    // PROBE U: the importing file — `lib_double` must RESOLVE via the scoped merge -> nerror=0.
    val nU = check_file("[U:use]   ", pU)
    // PROBE N: the SAME process, a file that did NOT import lib — `lib_double` must be UNRESOLVED
    // (the scoped merge did NOT leak) -> nerror>0.
    val nN = check_file("[N:noleak]", pN)
    //
    val () = PYI_log("======================================================================")
    val () = PYI_log_int(">> PROBE U (import-resolve) nerror =", nU)
    val () = PYI_log_int(">> PROBE N (no-leak)        nerror =", nN)
  in
    if nU = 0 then
      (if nN > 0 then
         PYI_log(">> M7-import: PASS (U resolves nerror=0 ; N no-leak nerror>0 — scoped, no global leak)")
       else
         PYI_log(">> M7-import: FAIL (N no-leak nerror NOT >0 — the merge LEAKED globally; WRONG)"))
    else
      PYI_log(">> M7-import: FAIL (U import-resolve nerror NOT 0 — the scoped merge did not resolve)")
  end
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m7imp()
//
(* ****** ****** *)
(*
** end of [frontend/DATS/pyfront_m7imp.dats]
*)
