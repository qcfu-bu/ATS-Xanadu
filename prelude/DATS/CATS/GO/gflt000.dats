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
CATS/GO/gflt000.dats — the GO backend arm for the [dflt] (double) prelude
primitives.  Mirrors CATS/JS/gflt000.dats EXACTLY, rebinding each [#impltmp]
from XATS2JS_* to XATS2GO_*; the typed Go bodies (dflt -> Go `float64`) live
in the companion gflt000.cats.  [g_si<dflt>] is the sint->dflt coercion.
*)
//
(* ****** ****** *)
//
#impltmp
g_si<dflt>
  ( i1 ) =
(
XATS2GO_si2dflt
  ( i1 )) where
{
#extern
fcast
XATS2GO_si2dflt
(i1: sint): dflt = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
dflt_neg
  ( f1 ) =
(
XATS2GO_dflt_neg
  ( f1 )) where
{
#extern
fun
XATS2GO_dflt_neg
(f1: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_abs
  ( f1 ) =
(
XATS2GO_dflt_abs
  ( f1 )) where
{
#extern
fun
XATS2GO_dflt_abs
(f1: dflt): dflt = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
dflt_sqrt
  ( f1 ) =
(
XATS2GO_dflt_sqrt
  ( f1 )) where
{
#extern
fun
XATS2GO_dflt_sqrt
(f1: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_cbrt
  ( f1 ) =
(
XATS2GO_dflt_cbrt
  ( f1 )) where
{
#extern
fun
XATS2GO_dflt_cbrt
(f1: dflt): dflt = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
dflt_lt$dflt
  (f1, f2) =
(
XATS2GO_dflt_lt$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_lt$dflt
(f1: dflt, f2: dflt): bool = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_gt$dflt
  (f1, f2) =
(
XATS2GO_dflt_gt$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_gt$dflt
(f1: dflt, f2: dflt): bool = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_eq$dflt
  (f1, f2) =
(
XATS2GO_dflt_eq$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_eq$dflt
(f1: dflt, f2: dflt): bool = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_lte$dflt
  (f1, f2) =
(
XATS2GO_dflt_lte$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_lte$dflt
(f1: dflt, f2: dflt): bool = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_gte$dflt
  (f1, f2) =
(
XATS2GO_dflt_gte$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_gte$dflt
(f1: dflt, f2: dflt): bool = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_neq$dflt
  (f1, f2) =
(
XATS2GO_dflt_neq$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_neq$dflt
(f1: dflt, f2: dflt): bool = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_cmp$dflt
  (f1, f2) =
(
XATS2GO_dflt_cmp$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_cmp$dflt
(f1: dflt, f2: dflt): sint = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
dflt_add$dflt
  (f1, f2) =
(
XATS2GO_dflt_add$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_add$dflt
(f1: dflt, f2: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_sub$dflt
  (f1, f2) =
(
XATS2GO_dflt_sub$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_sub$dflt
(f1: dflt, f2: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_mul$dflt
  (f1, f2) =
(
XATS2GO_dflt_mul$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_mul$dflt
(f1: dflt, f2: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_div$dflt
  (f1, f2) =
(
XATS2GO_dflt_div$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_div$dflt
(f1: dflt, f2: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_mod$dflt
  (f1, f2) =
(
XATS2GO_dflt_mod$dflt
  (f1, f2)) where
{
#extern
fun
XATS2GO_dflt_mod$dflt
(f1: dflt, f2: dflt): dflt = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
dflt_print
  ( f0 ) =
(
XATS2GO_dflt_print
  ( f0 )) where
{
#extern
fun
XATS2GO_dflt_print
(f0: dflt): void = $extnam() }
//
(* ****** ****** *)
//
#impltmp
<(*tmp*)>
dflt_ceil
  ( df ) =
(
XATS2GO_dflt_ceil
  ( df )) where
{
#extern
fun
XATS2GO_dflt_ceil
(df: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_floor
  ( df ) =
(
XATS2GO_dflt_floor
  ( df )) where
{
#extern
fun
XATS2GO_dflt_floor
(df: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_round
  ( df ) =
(
XATS2GO_dflt_round
  ( df )) where
{
#extern
fun
XATS2GO_dflt_round
(df: dflt): dflt = $extnam() }
//
#impltmp
<(*tmp*)>
dflt_trunc
  ( df ) =
(
XATS2GO_dflt_trunc
  ( df )) where
{
#extern
fun
XATS2GO_dflt_trunc
(df: dflt): dflt = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_gflt000.dats] *)
(***********************************************************************)
