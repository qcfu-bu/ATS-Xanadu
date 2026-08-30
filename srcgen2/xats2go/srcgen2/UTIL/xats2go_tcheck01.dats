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
No trxd3i0/tryd3i0/trxi0i1, no Go emission, nothing on stdout except
the [--index] records.  The diagnostic surface (stderr) is
BYTE-COMPATIBLE with xats2go_goemit01 on the same input: the LSP
server parses these stderr reports.  Built by
selfhost-build/wire-tcheck.sh into src/tcheck/ over the SAME assembled
frontend packages as the CLI driver.
//
CLAUDE-2026-08-29 (M6): the pipeline body moved to
[xats2go_tchecklib.{sats,dats}] so the resident LSP server can run the
IDENTICAL check in-process (prelude loaded once + per-check eviction).
This file is now the thin CLI: banners, argv/flag handling, stdin
acquisition — the stderr/stdout bytes are unchanged.
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
#staload "./xats2go_tchecklib.sats"
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
(* the whole stdin as one string (the --stdin buffer payload) *)
#extern
fun
XATS2GO_tcheck_stdin_readall((*void*)): strn = $extnam()
//
(* ****** ****** *)
//
(* ASCII string equality (the driver's own flags) *)
fun
my_streq
(s1: strn, s2: strn): bool =
let
val n1 = strn_length(s1)
val n2 = strn_length(s2)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s1, i0) = strn_get$at(s2, i0)
then loop(i0+1) else false
in//let
if n1 = n2 then loop(0) else false
end//endof[my_streq]
//
(* ****** ****** *)
//
(*
the driver's OWN flags ([--stdin]; [--index]) are consumed here, not
fed to the compiler flag store.
*)
fun
my_ownflagq(arg0: strn): bool =
if my_streq(arg0, "--stdin") then true else
if my_streq(arg0, "--index") then true else false
//
fun
argv$hasflag
(argv: argv, name: strn): sint =
(
  loop(3)) where
{
//
val n0 = length(argv)
//
fun
loop(i0: sint): sint =
if
(i0 < n0)
then
(if my_streq(argv[i0], name) then 1 else loop(i0+1))
else 0
}(*where*)//end-of-[argv$hasflag(argv,name)]
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
if my_ownflagq(argv[i0])
then ((*consumed*))
else xatsopt_flag$pvsadd0(argv[i0])
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
val (  ) =
tchk_prelude_load((*void*))
//
val (  ) = argv$loop(argv)
//
val stdinq =
argv$hasflag(argv, "--stdin")
//
val txt =
(
if (stdinq > 0)
then XATS2GO_tcheck_stdin_readall() else ""): strn
//
in//let
tchk_check
( argv[2]
, txt
, stdinq
, argv$hasflag(argv, "--index")
, g_stderr((*0*))
, g_stdout<>((*0*)))
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
