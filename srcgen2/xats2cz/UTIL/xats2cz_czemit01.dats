(***********************************************************************)
(*                         Applied Type System                         *)
(***********************************************************************)
(*
xats2cz_czemit01 — the xats2cz CLI driver (M0).

Pipeline (consumes the COMPLETE xats2js backend's intrep0; NOT xats2cc):
  d3parsed_of_fildats
    -> tread3a / trtmp3b / trtmp3c / t3read0      (frontend D3, template resolve)
    -> i0parsed_of_trxd3i0                          (D3 -> intrep0, xats2js)
  -> i0parsed_cz0emit                               (intrep0 -> Chez Scheme, stdout)
NO i0parsed_of_tryd3i0 (xats2cc-only).  NO trxi0i1/intrep1.

Loads the_{fxty,tr12}env_pvsl00d (the srcgen2 prelude tree — NOT 01d, which
mis-resolves env-templates and drops fn chains) and sets the _XATS2JS_ flags so
the complete JS compile-time CATS resolves the prelude/templates.
*)
(* ****** ****** *)
#include
"./../../HATS/xatsopt_sats.hats"
#include
"./../../HATS/xatsopt_dpre.hats"
(* ****** ****** *)
#include
"./../HATS/libxatsopt.hats"
(* ****** ****** *)
//
#staload
"./../../xats2js/srcgen1/SATS/intrep0.sats"
#staload
"./../../xats2js/srcgen1/SATS/trxd3i0.sats"
//
#staload "./../SATS/cz0emit.sats"
//
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
//
in//let
//
let
val
filr = g_stdout<>()
in//let
(
  i0parsed_cz0emit(ipar, filr))
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
the_tr12env_pvsl00d((*nil*))
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
// Welcome from ATS3/Xanadu! (xats2cz M0)")
val (  ) =
prerrsln("\
// XATSHOME = ", the_XATSHOME())
//
val argv = XATSOPT_argv$get((*0*))
//
}(*where*)//end-of-[mymain_main(...)]
//
(* ****** ****** *)
val ((*the_entry_point*)) = mymain_main((*void*))
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2cz_UTIL_xats2cz_czemit01.dats] *)
(***********************************************************************)
