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
(*
xats2chez_czemit01 — the xats2chez CLI driver (milestone M0).
//
Mirrors xats2go/srcgen2/UTIL/xats2go_goemit01.dats, but STOPS at intrep0:
this backend emits Scheme from the expression-shaped intrep0 directly, so
the pipeline is
//
  d3parsed_of_fildats
    -> tread3a / trtmp3b / trtmp3c / t3read0   (frontend D3)
    -> i0parsed_of_trxd3i0                      (D3 -> intrep0, xats2cc shared)
    -> i0parsed_of_tryd3i0                      (intrep0 fixups, xats2cc shared)
//
— NO i1parsed_of_trxi0i1 (intrep1/trxi0i1 are not used) — and then calls
[i0parsed_chez0emit] to emit Chez Scheme to stdout between the
;;==XATS2CHEZ-BEGIN==/;;==XATS2CHEZ-END== sentinels.
*)
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
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
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/trxd3i0.sats"//...
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/tryd3i0.sats"//...
//
#staload "./../SATS/chez0emit.sats"
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
in//let
//
let
val
filr = g_stdout<>()
in//let
(
  i0parsed_chez0emit(ipar, filr))
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
// Welcome from ATS3/Xanadu! (xats2chez M0)")
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
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_UTIL_xats2chez_czemit01.dats] *)
(***********************************************************************)
