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
CATS/GO/bool000.dats — the GO backend arm for the [bool] prelude primitives.
Mirrors CATS/JS/bool000.dats EXACTLY, rebinding each [#impltmp] from XATS2JS_*
to XATS2GO_*; the typed Go bodies live in the companion bool000.cats.  Note
[bool_print] stays PURE ATS (it routes through [strn_print]), so it needs no
typed leaf -- only the relational ops bottom out at the .cats floor.
*)
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
bool_lt
(b1, b2) =
(
XATS2GO_bool_lt
  (b1, b2)) where
{
#extern
fun
XATS2GO_bool_lt
(b1: bool, b2: bool): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
bool_gt
(b1, b2) =
(
XATS2GO_bool_gt
  (b1, b2)) where
{
#extern
fun
XATS2GO_bool_gt
(b1: bool, b2: bool): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
bool_eq
(b1, b2) =
(
XATS2GO_bool_eq
  (b1, b2)) where
{
#extern
fun
XATS2GO_bool_eq
(b1: bool, b2: bool): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
bool_lte
(b1, b2) =
(
XATS2GO_bool_lte
  (b1, b2)) where
{
#extern
fun
XATS2GO_bool_lte
(b1: bool, b2: bool): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
bool_gte
(b1, b2) =
(
XATS2GO_bool_gte
  (b1, b2)) where
{
#extern
fun
XATS2GO_bool_gte
(b1: bool, b2: bool): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
bool_neq
(b1, b2) =
(
XATS2GO_bool_neq
  (b1, b2)) where
{
#extern
fun
XATS2GO_bool_neq
(b1: bool, b2: bool): bool = $extnam()
}
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
[bool_print]: PURE ATS (routes to [strn_print]); no typed leaf needed.
*)
//
#impltmp
<(*tmp*)>
bool_print(b0) =
(
if b0
then strn_print<>("true")
else strn_print<>("false"))//end(impl)
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_bool000.dats] *)
(***********************************************************************)
