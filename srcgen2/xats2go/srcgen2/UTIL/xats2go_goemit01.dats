(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(* ****** ****** *)
//
(*
xats2go_goemit01 — the xats2go CLI driver (milestone M0).
//
Mirrors xats2js/srcgen2/UTIL/xats2js_jsemit01.dats: it runs the REAL,
shared frontend pipeline on an input .dats/.sats —
//
  d3parsed_of_fildats
    -> tread3a / trtmp3b / trtmp3c / t3read0   (frontend D3)
    -> i0parsed_of_trxd3i0                      (D3 -> intrep0, xats2cc)
    -> i0parsed_of_tryd3i0                      (intrep0 fixups, xats2cc)
    -> i1parsed_of_trxi0i1                      (intrep0 -> intrep1, copied)
//
— and then calls [i1parsed_go1emit] (instead of [i1parsed_js1emit]) to
emit Go text to stdout. For M0 the emitter writes a fixed minimal Go
program between //==XATS2GO-BEGIN==/ //==XATS2GO-END== sentinels.
*)
//
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
(*
#include
"./../../..\
/HATS/xatsopt_dats.hats"
*)
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
(* ****** ****** *)
#include
"./../HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../HATS/mytmplib00.hats"
(* ****** ****** *)
(* ****** ****** *)
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
#staload ".\
/../../xats2cc\
/srcgen1/SATS/trxd3i0.sats"//...
#staload ".\
/../../xats2cc\
/srcgen1/SATS/tryd3i0.sats"//...
//
(*
CLAUDE-2026-08: [pread00] is not in libxatsopt.hats; the driver needs it
for [d0parsed_of_pread00] and [d0parsed_fpemsg].  Staloaded HERE rather
than in the shared .hats so only this module's stamps move.
*)
#staload "./../../../SATS/pread00.sats"
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/trxi0i1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
#staload "./../SATS/go1emit_byref0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#if
defq(_XATS2JS_)
#typedef argv=jsa1sz(strn)
#endif//#if(defq(_XATS2JS_))
//
#if
defq(_XATS2PY_)
#typedef argv=pya1sz(strn)
#endif//#if(defq(_XATS2PY_))
//
#extern
fun
XATSOPT_argv$get
  ((*0*)): argv = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
CLAUDE-2026-08: hoisted to module scope -- the diagnostics window must also
bracket the PARSE phase (see the where-clause below), not just f3perr0.
*)
#extern
fun
XATS2GO_report_begin((*void*)): void = $extnam()
#extern
fun
XATS2GO_report_end((*void*)): void = $extnam()
//
fun
mymain_work
(fpth: string): void =
let
//
val dpar =
d3parsed_of_tread3a(dpar)
//
val dpar =
d3parsed_of_trtmp3b(dpar)
val dpar =
d3parsed_of_trtmp3c(dpar)
//
val dpar =
d3parsed_of_t3read0(dpar)
//
val (  ) =
let
val
out0 = g_stderr((*0*))
(*
CLAUDE-2026-08: the srcgen2 resolver does not apply the reporters'
local `g_print$out<>() = out` hooks, so their print-family calls land
on the DEFAULT channel.  Bracket the diagnostics window so the runtime
default is STDERR for its duration — matching the srcgen1/JS-compiled
reference byte-for-byte on both streams.
*)
in//let
prerrsln
("F3PERR0_D3PARSED:");
XATS2GO_report_begin();
f3perr0_d3parsed(out0,dpar);
XATS2GO_report_end()
end//let//end-of-(val(...))
//
val ipar =
(
  i0parsed_of_trxd3i0(dpar))
val ipar =
(
  i0parsed_of_tryd3i0(ipar))
//
val ipar =
(
  i1parsed_of_trxi0i1(ipar))
//
in//let
//
let
val
filr = g_stdout<>()
in//let
(
  i1parsed_go1emit(ipar, filr))
end//let
//
end where
{
//
(*
CLAUDE-2026-08: report the PARSE-level diagnostics.
//
[d3parsed_of_fildats(fpth)] is exactly
//
  d3parsed_of_trans03(d0parsed_of_pread00(d0parsed_from_fpath(1, fpth)))
//
(xatsopt_utils0.dats:308).  The [d0parsed] threaded through it carries the
parse-error count -- [d0parsed_get_nerror] -- and pread00 populates the
[D0Cerrck]/[D0Perrck] nodes that [d0parsed_fpemsg] prints as PREAD00-ERROR.
But NOTHING in srcgen2 ever calls [d0parsed_fpemsg]: it is declared in
pread00.sats:515, defined at pread00.dats:141, and has no caller in the
tree.  So the value is built, consumed by trans03, and the parse-level
report is never produced -- by ANY srcgen2 driver, ours or xats2js's.
//
So we expand the chain here and report [d0par] between the two halves.
This is a DRIVER-local fix: it does not touch the shared frontend, so no
other backend's stamps move.
//
Note this is a REPORTING gap, not a detection gap: a parse error still
reaches level 3 as a [D3Cerrck] node, so [f3perr0_d3parsed] below already
flags it (on the malformed-pattern probe both this compiler and the JS
reference print the same 17 F3PERR0-ERROR lines).  What was missing is the
earlier, finer-grained PREAD00 report -- which is what an LSP wants, since
it names the offending token rather than the enclosing declaration.
*)
val ( ) = XATS2GO_report_begin()
//
val
d0par =
d0parsed_of_pread00
  (d0parsed_from_fpath(1(*dyn*), fpth))
//
val ( ) =
d0parsed_fpemsg(g_stderr((*0*)), d0par)
//
val
dpar = d3parsed_of_trans03(d0par)
//
val ( ) = XATS2GO_report_end()
//
}(*where*)//end-of-[mymain_work(fpth)]
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
argv$loop
(argv: argv): void =
(
  loop(3)) where
{
//
val n0 = length(argv)
//
fun
loop(i0: sint): void =
if
(i0 < n0)
then
(
  loop(i0+1)) where
{
val () =
xatsopt_flag$pvsadd0(argv[i0])
}
}(*where*)//end-of-[argv$loop(argv)]
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
mymain_main(): void =
let
//
val alen = length(argv)
//
val (  ) =
if
(
alen >= 3)
then
let // let
//
val ret1 =
the_fxtyenv_pvsl00d((*0*))
val (  ) =
if // if
(ret1 > 0)
then
prerrsln("\
// The fixity-defs loaded!")
val ret2 =
the_tr12env_pvsl01d((*nil*))
val (  ) =
if // if
(ret2 > 0)
then prerrsln("\
// The trans12-defs loaded!")
//
val (  ) =
xatsopt_flag$pvsadd0("--_XATS2JS_")
val (  ) =
xatsopt_flag$pvsadd0("--_SRCGEN2_XATS2JS_")
(*
CLAUDE-2026-08 (arm migration): the GO arm overlays the JS costume --
xatsopt_dpre.hats includes libcats/DATS/CATS/GO/libcats.dats under
_XATS2GO_ AFTER the JS/NODE block, so the GO-named leaf bindings
(XATS2GO_g_stdout etc) register later and win; leaves the JS arm as
the fallback surface until GO analogs of the remaining CATS files
exist, at which point _XATS2JS_ is dropped here.
*)
val (  ) =
xatsopt_flag$pvsadd0("--_XATS2GO_")
//
in//let
(
argv$loop(argv); mymain_work(argv[2]))
endlet // let // if(length(argv) >= 3)
//
val (  ) =
if
(
alen<=2)
then
let//let
val (  ) =
(
prerrsln
("ERROR: no source is given: ", argv))
endlet // let // if(length(argv) <= 2)
//
endlet where
{
//
val (  ) =
prerrsln("\
// Welcome from ATS3/Xanadu! (xats2go M0)")
val (  ) =
prerrsln("\
// XATSHOME = ", the_XATSHOME())
//
val argv = XATSOPT_argv$get((*0*))
//
}(*where*)//end-of-[mymain_main(...)]
//
(* ****** ****** *)
(* ****** ****** *)
val ((*the_entry_point*)) = mymain_main((*void*))
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_UTIL_xats2go_goemit01.dats] *)
(***********************************************************************)
