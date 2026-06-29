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
CATS/GO/axrf000.dats — the GO backend arm for the [a0rf] (single-cell mutable
REFERENCE) prelude primitives.  The compiler's side-tables (stampers, tytab,
the byref set) are all built on these, so the reference floor is on the
self-hosting critical path.

UNLIKE the JS arm (which provides only the linear LEAVES a0rf_lget/a0rf_lset
and lets a0rf_get/a0rf_set be the base pure-ATS impls built on top with an
[owed] PROOF tuple), the GO arm ALSO overrides a0rf_get/a0rf_set directly to
typed Go primitives.  This keeps the go-arm emitter OFF the proof-tuple path
(`(owed(a) | a)`), whose linear-proof erasure the Go value-emit surface does
not yet model -- a0rf_get/set ARE primitives at the Go floor, so binding them
directly is both simpler and faithful.  (The linear a0rf_lget/a0rf_lset leaves
are still provided for any code that uses them explicitly.)
*)
//
(* ****** ****** *)
//
#impltmp
< a:t0 >
a0rf_make_1val
  ( x0 ) =
(
XATS2GO_a0rf_make_1val
  ( x0 )) where
{
#extern
fun
XATS2GO_a0rf_make_1val
(x0: a): a0rf(a) = $extnam() }
//
(* ****** ****** *)
//
#impltmp
< a:t0 >
a0rf_get
  ( A ) =
(
XATS2GO_a0rf_get
  ( A )) where
{
#extern
fun
XATS2GO_a0rf_get
(A: a0rf(a)): (a) = $extnam() }
//
#impltmp
< a:t0 >
a0rf_set
  (A, x) =
(
XATS2GO_a0rf_set
  (A, x)) where
{
#extern
fun
XATS2GO_a0rf_set
(A: a0rf(a), x: a): void = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_axrf000.dats] *)
(***********************************************************************)
