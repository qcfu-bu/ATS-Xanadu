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
xats2go_tcheck01 — the CHECK-ONLY driver (for the ATS3 LSP server).
//
CLAUDE-2026-08-28: [xats2go_goemit01.dats] with the backend REMOVED: the
pipeline stops after the diagnostics reports —
//
  d0parsed_from_fpath -> pread00 report (PREAD00-ERROR, parse level)
    -> d3parsed_of_trans03
    -> tread3a / trtmp3b / trtmp3c / t3read0
    -> f3perr0_d3parsed report (F3PERR0-ERROR)
//
No trxd3i0/tryd3i0/trxi0i1, no Go emission, nothing on stdout.  The
diagnostic surface (stderr) is BYTE-COMPATIBLE with xats2go_goemit01 on
the same input: the LSP server parses these stderr reports.  Built by
selfhost-build/wire-tcheck.sh into src/tcheck/ over the SAME assembled
frontend packages as the CLI driver.
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
(*
[pread00] is not in libxatsopt.hats; the driver needs it for
[d0parsed_of_pread00] and [d0parsed_fpemsg] (see xats2go_goemit01).
*)
#staload "./../../../SATS/pread00.sats"
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
the diagnostics window must bracket BOTH the parse phase and the
f3perr0 report (see xats2go_goemit01): the srcgen2 resolver does not
apply the reporters' local `g_print$out<>() = out` hooks, so the
runtime default channel is flipped to stderr for the duration.
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
in//let
//
let
val
out0 = g_stderr((*0*))
in//let
prerrsln
("F3PERR0_D3PARSED:");
XATS2GO_report_begin();
f3perr0_d3parsed(out0,dpar);
XATS2GO_report_end()
end//let
//
end where
{
//
(*
the PARSE-level (PREAD00) report between the halves of
[d3parsed_of_fildats] — see the long note in xats2go_goemit01.dats.
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
(*
the SAME flag set as xats2go_goemit01: the flags select which CATS
files xatsopt_dpre includes, and the diagnostic surface must match
the CLI driver byte-for-byte on the same input.
*)
val (  ) =
xatsopt_flag$pvsadd0("--_XATS2JS_")
val (  ) =
xatsopt_flag$pvsadd0("--_SRCGEN2_XATS2JS_")
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
// Welcome from ATS3/Xanadu! (xats2go tcheck01)")
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
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_UTIL_xats2go_tcheck01.dats] *)
(***********************************************************************)
