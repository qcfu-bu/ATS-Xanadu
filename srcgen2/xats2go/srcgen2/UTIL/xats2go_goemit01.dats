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
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/trxi0i1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
#staload "./../SATS/go1emit_byref0.sats"//for[go_arm_set]
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
in//let
prerrsln
("F3PERR0_D3PARSED:");
f3perr0_d3parsed(out0,dpar)
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
val
dpar = d3parsed_of_fildats(fpth)
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
//
// CATS/GO prelude pivot: if any arg is `--go-arm`, enable GO-arm emission
// (emit prelude template bodies down to the typed XATS2GO_* .cats leaves).
val (  ) =
let
  val n0 = length(argv)
  fun
  chk(i0: sint): void =
  if (i0 < n0)
  then
    (
    (if (argv[i0] = "--go-arm") then go_arm_set() else ((*skip*)));
    chk(i0+1))
in
  chk(3)
end
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
