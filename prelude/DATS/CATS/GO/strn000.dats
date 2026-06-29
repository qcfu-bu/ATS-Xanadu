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
//
(*
CATS/GO/strn000.dats — the GO arm for the [strn] (string) prelude.  Mirrors
CATS/JS/strn000.dats for the scalar primitives (XATS2JS_* -> XATS2GO_*); the
typed Go bodies are in strn000.cats.  String-CONSTRUCTION primitives
(strn_make_fwork / fset) are DEFERRED.
*)
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
strn_nilq
  ( cs ) =
(
strn_length<>(cs) = 0)
//
#impltmp
<(*tmp*)>
strn_consq
  ( cs ) =
(
strn_length<>(cs) > 0)
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
strn_length
  ( cs ) =
(
XATS2GO_strn_length
  ( cs )) where
{
#extern
fun
XATS2GO_strn_length
  (cs: strn): nint = $extnam() }
//
#impltmp
<(*tmp*)>
strn_cmp
  (x1, x2) =
(
XATS2GO_strn_cmp
  (x1, x2)) where
{
#extern
fun
XATS2GO_strn_cmp
(x1: strn, x2: strn): nint = $extnam() }
//
#impltmp
<(*tmp*)>
strn_print
  ( cs ) =
(
XATS2GO_strn_print
  ( cs )) where
{
#extern
fun
XATS2GO_strn_print(cs: strn): void = $extnam() }
//
#impltmp
<(*tmp*)>
strn_get$at
  (cs, i0) =
(
XATS2GO_strn_get$at$raw
(     cs   ,   i0     ))
where
{
#extern
fun
XATS2GO_strn_get$at$raw
(    cs: strn, i0: nint    ): char = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_strn000.dats] *)
(***********************************************************************)
