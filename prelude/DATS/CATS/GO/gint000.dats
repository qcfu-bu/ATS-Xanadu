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
CATS/GO/gint000.dats — the GO backend arm for the [sint] (machine int)
prelude primitives.  Mirrors CATS/JS/gint000.dats EXACTLY, rebinding each
[#impltmp] from XATS2JS_* to XATS2GO_*; the typed Go bodies live in the
companion gint000.cats.  This is the principled prelude path: the shared
prelude ATS is compiled to Go by xats2go, and bottoms out at this small
typed primitive floor (NOT a hand-written runtime mirror of the prelude).
*)
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
sint_neg
  ( i1 ) =
(
XATS2GO_sint_neg
  ( i1 )) where
{
#extern
fun
XATS2GO_sint_neg
(i1: sint): sint = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
sint_lt$sint
  (i1, i2) =
(
XATS2GO_sint_lt$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_lt$sint
(i1: sint, i2: sint): bool = $extnam() }
//
#impltmp
<(*tmp*)>
sint_gt$sint
  (i1, i2) =
(
XATS2GO_sint_gt$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_gt$sint
(i1: sint, i2: sint): bool = $extnam() }
//
#impltmp
<(*tmp*)>
sint_lte$sint
  (i1, i2) =
(
XATS2GO_sint_lte$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_lte$sint
(i1: sint, i2: sint): bool = $extnam() }
//
#impltmp
<(*tmp*)>
sint_gte$sint
  (i1, i2) =
(
XATS2GO_sint_gte$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_gte$sint
(i1: sint, i2: sint): bool = $extnam() }
//
#impltmp
<(*tmp*)>
sint_eq$sint
  (i1, i2) =
(
XATS2GO_sint_eq$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_eq$sint
(i1: sint, i2: sint): bool = $extnam() }
//
#impltmp
<(*tmp*)>
sint_neq$sint
  (i1, i2) =
(
XATS2GO_sint_neq$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_neq$sint
(i1: sint, i2: sint): bool = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
sint_add$sint
  (i1, i2) =
(
XATS2GO_sint_add$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_add$sint
(i1: sint, i2: sint): sint = $extnam() }
//
#impltmp
<(*tmp*)>
sint_sub$sint
  (i1, i2) =
(
XATS2GO_sint_sub$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_sub$sint
(i1: sint, i2: sint): sint = $extnam() }
//
#impltmp
<(*tmp*)>
sint_mul$sint
  (i1, i2) =
(
XATS2GO_sint_mul$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_mul$sint
(i1: sint, i2: sint): sint = $extnam() }
//
#impltmp
<(*tmp*)>
sint_div$sint
  (i1, i2) =
(
XATS2GO_sint_div$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_div$sint
(i1: sint, i2: sint): sint = $extnam() }
//
#impltmp
<(*tmp*)>
sint_mod$sint
  (i1, i2) =
(
XATS2GO_sint_mod$sint
  (i1, i2)) where
{
#extern
fun
XATS2GO_sint_mod$sint
(i1: sint, i2: sint): sint = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
sint_print
  ( i0 ) =
(
XATS2GO_sint_print
  ( i0 )) where
{
#extern
fun
XATS2GO_sint_print
(i0: sint): void = $extnam() }
//
#impltmp
<(*tmp*)>
uint_print
  ( u0 ) =
(
XATS2GO_uint_print
  ( u0 )) where
{
#extern
fun
XATS2GO_uint_print
(u0: uint): void = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
sint_to$uint
  ( i0 ) =
(
XATS2GO_sint_to$uint
  ( i0 )) where
{
#extern
fun
XATS2GO_sint_to$uint
(i0: sint): uint = $extnam() }
//
#impltmp
<(*tmp*)>
uint_to$sint
  ( u0 ) =
(
XATS2GO_uint_to$sint
  ( u0 )) where
{
#extern
fun
XATS2GO_uint_to$sint
(u0: uint): sint = $extnam() }
//
(* ****** ****** *)
//
(*
The [uint] logical ops below are arm-bound to match CATS/JS/gint000.dats
exactly; like the JS floor, their bodies are NOT in the companion .cats
(they are never instantiated by the current surface).  Add typed Go bodies
to gint000.cats if a program ever forces one.
*)
//
#impltmp
<(*tmp*)>
uint_pre(u0) =
XATS2GO_uint_pre(u0) where
{ #extern fun XATS2GO_uint_pre(u0: uint): uint = $extnam() }
//
#impltmp
<(*tmp*)>
uint_suc(u0) =
XATS2GO_uint_suc(u0) where
{ #extern fun XATS2GO_uint_suc(u0: uint): uint = $extnam() }
//
#impltmp
<(*tmp*)>
uint_lnot(u0) =
XATS2GO_uint_lnot(u0) where
{ #extern fun XATS2GO_uint_lnot(u0: uint): uint = $extnam() }
//
#impltmp
<(*tmp*)>
uint_ladd(u1, u2) =
XATS2GO_uint_ladd(u1, u2) where
{ #extern fun XATS2GO_uint_ladd(u1: uint, u2: uint): uint = $extnam() }
//
#impltmp
<(*tmp*)>
uint_lmul(u1, u2) =
XATS2GO_uint_lmul(u1, u2) where
{ #extern fun XATS2GO_uint_lmul(u1: uint, u2: uint): uint = $extnam() }
//
#impltmp
<(*tmp*)>
uint_lneq(u1, u2) =
XATS2GO_uint_lneq(u1, u2) where
{ #extern fun XATS2GO_uint_lneq(u1: uint, u2: uint): uint = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_gint000.dats] *)
(***********************************************************************)
