(* ****** ****** *)
(* ****** ****** *)
(*
xats2chez: pulls in the backend tmplib (g_print/g_cmp template instances
for the intrep0 IR nodes the emitter touches).  Backend-agnostic; mirrors
xats2go/srcgen2/HATS/mytmplib00.hats but the tmplib it loads references
ONLY intrep0 (this backend emits from intrep0; intrep1 is not staloaded).
*)
(* ****** ****** *)
(* ****** ****** *)
//
#staload _ =
"./../DATS/xats2chez_tmplib.dats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_HATS_mytmplib00.hats] *)
(***********************************************************************)
