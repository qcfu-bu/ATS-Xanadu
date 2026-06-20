(* ****** ****** *)
(*
** M2.5 STEP-0 GATING SPIKE driver — compiles frontend/pyrt/flow_spike.dats
** (the 2-parameter `flow(a,r)` datatype + `flow_bind` + a build/bind/match driver)
** END-TO-END and reports the evidence:
**
**   [typecheck] d3parsed_of_fildats(<flow_spike.dats>) ; print nerror (must be 0)
**   [codegen]   run the verified M0b xats2js backend pass sequence over that
**               d3parsed and emit the program's JS between sentinels.
**
** The emitted JS is then run on `node` by frontend/build-m2_5.sh; its stdout
** (the printed flow tags/payloads) proves the 2-parameter datatype + the `case`
** over it WORK at run time, not just type-check.
**
** Mirrors frontend/DATS/pyfront_m0b.dats EXACTLY for the backend spine; the only
** change is the SOURCE of the d3parsed: `d3parsed_of_fildats(path)` (read a real
** ATS surface file) instead of the M0a/M0b hand-built program. So this also
** confirms the file-path entry compiles a parametric datatype cleanly.
**
** PURELY ADDITIVE: only CALLS the compiler+backend (libxatsopt + lib2xats2cc +
** lib2xats2js). Nothing under srcgen2/ is modified.
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
// the xats2js BACKEND SATS (NOT in libxatsopt.hats; must be in THIS DATS).
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/intrep0.sats"
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/trxd3i0.sats"
#staload "./../../srcgen2/xats2cc/srcgen1/SATS/tryd3i0.sats"
//
#staload "./../../srcgen2/xats2js/srcgen2/SATS/intrep1.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/trxi0i1.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/xats2js.sats"
#staload "./../../srcgen2/xats2js/srcgen2/SATS/js1emit.sats"
//
(* ****** ****** *)
//
// FFI: progress markers to stderr; the emitted-JS sentinels to stdout; the spike
// source path comes from process.argv[2]. Implemented in CATS/pyfront_spike.cats.
//
#extern fun PYS_log(s: strn): void = $extnam()
#extern fun PYS_log_int(s: strn, n: sint): void = $extnam()
#extern fun PYS_mark(s: strn): void = $extnam()
#extern fun PYS_argv_path((*0*)): strn = $extnam()
//
(* ****** ****** *)
//
// Compile the spike file: typecheck (d3parsed_of_fildats) then run the verified
// xats2js backend spine and emit. Returns the L3 nerror.
//
fun
spike_emit(fpth: strn, filr: FILR): sint = let
//
// [typecheck] read + typecheck the real ATS surface file at `fpth`.
val dpar = d3parsed_of_fildats(fpth)
val nerror = d3parsed_get_nerror(dpar)
val () = PYS_log_int("[spike] d3parsed_of_fildats nerror =", nerror)
//
// surface any typecheck errors via the stock reporter (stderr) for the evidence.
val () =
let val out0 = g_stderr() in
  PYS_log("[spike] -- f3perr0_d3parsed (stock reporter) --");
  f3perr0_d3parsed(out0, dpar)
end
//
// [codegen] the verified M0b pass sequence (L3 read passes -> intrep0 -> intrep1).
val dpar = d3parsed_of_tread3a(dpar)
val () = PYS_log("[spike] tread3a done")
val dpar = d3parsed_of_trtmp3b(dpar)
val () = PYS_log("[spike] trtmp3b done")
val dpar = d3parsed_of_trtmp3c(dpar)
val () = PYS_log("[spike] trtmp3c done")
val dpar = d3parsed_of_t3read0(dpar)
val () = PYS_log("[spike] t3read0 done")
//
val ipar = i0parsed_of_trxd3i0(dpar)
val () = PYS_log("[spike] trxd3i0 (L3 -> intrep0) done")
val ipar = i0parsed_of_tryd3i0(ipar)
val () = PYS_log("[spike] tryd3i0 (intrep0 resolve) done")
//
val ipar = i1parsed_of_trxi0i1(ipar)
val () = PYS_log("[spike] trxi0i1 (intrep0 -> intrep1) done")
//
val () = PYS_mark("//==PYS-JS-BEGIN==")
val () = i1parsed_js1emit(ipar, filr)
val () = PYS_mark("//==PYS-JS-END==")
val () = PYS_log("[spike] js1emit done (emitted flow-spike JS to stdout)")
//
in
  nerror
end // end of [spike_emit]
//
(* ****** ****** *)
//
fun
mymain_spike((*void*)): void = let
//
// one-time global bootstrap (idempotent; required before name resolution).
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYS_log("######## M2.5 STEP-0 flow-spike driver ########")
val path = PYS_argv_path()
//
in
//
if path = "" then
  PYS_log("!! spike: no input path (expected process.argv[2] = flow_spike.dats)")
else let
  val () = PYS_log("[spike] source =")
  val () = PYS_log(path)
  val filr = g_stdout()
  val nerror = spike_emit(path, filr)
in
  if nerror = 0 then
    PYS_log("RESULT: PASS (flow-spike typecheck+codegen, nerror=0)")
  else
    PYS_log("RESULT: FAIL (flow-spike nerror != 0)")
end
//
end // end of [mymain_spike]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_spike()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_spike.dats]
*)
