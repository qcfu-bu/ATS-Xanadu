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
CATS/GO/char000.dats — the GO backend arm for the [char] prelude primitives.
Mirrors CATS/JS/char000.dats EXACTLY, rebinding each [#impltmp] from XATS2JS_*
to XATS2GO_*; the typed Go bodies (char -> Go `rune`) live in the companion
char000.cats.
*)
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_lt
(c1, c2) =
(
XATS2GO_char_lt
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_lt
(c1: char, c2: char): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_gt
(c1, c2) =
(
XATS2GO_char_gt
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_gt
(c1: char, c2: char): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_eq
(c1, c2) =
(
XATS2GO_char_eq
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_eq
(c1: char, c2: char): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_lte
(c1, c2) =
(
XATS2GO_char_lte
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_lte
(c1: char, c2: char): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_gte
(c1, c2) =
(
XATS2GO_char_gte
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_gte
(c1: char, c2: char): bool = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_neq
(c1, c2) =
(
XATS2GO_char_neq
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_neq
(c1: char, c2: char): bool = $extnam()
}
//
(* ****** ****** *)
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_add$sint
(c1, i2) =
(
XATS2GO_char_add$sint
  (c1, i2)) where
{
#extern
fun
XATS2GO_char_add$sint
(c1: char, i2: sint): char = $extnam()
}
//
#impltmp
<(*tmp*)>
char_sub$char
(c1, c2) =
(
XATS2GO_char_sub$char
  (c1, c2)) where
{
#extern
fun
XATS2GO_char_sub$char
(c1: char, c2: char): sint = $extnam()
}
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
char_print(c0) =
(
XATS2GO_char_print
  ( c0 )) where
{
#extern
fun
XATS2GO_char_print
(c0: char): void = $extnam()
}
//
(* ****** ****** *)
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
sint_make_char(ch) =
(
XATS2GO_sint_make_char(ch)) where
{
#extern
fun
XATS2GO_sint_make_char(ch: char): sint = $extnam()
}
//
#impltmp
<(*tmp*)>
char_make_sint(i0) =
(
XATS2GO_char_make_sint(i0)) where
{
#extern
fun
XATS2GO_char_make_sint(i0: sint): char = $extnam()
}
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_char000.dats] *)
(***********************************************************************)
