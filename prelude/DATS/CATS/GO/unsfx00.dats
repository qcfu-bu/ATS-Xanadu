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
CATS/GO/unsfx00.dats — the GO backend arm for the UNSAFE p2tr (pointer)
primitives [$UN.p2tr_get] / [$UN.p2tr_set].

The base impls (prelude/DATS/unsfx00.dats) are `$eval(p)` / `$eval(p) := x` --
a deref READ / deref WRITE on a real pointer.  Through go-arm that bottoms out
at a Go `*p`, which works for a MONOMORPHIC pointer but NOT for the prelude's
[gseq] stack counter: gseq instantiates `p2tr_get<ni>`/`p2tr_set<ni>` whose
pointer param the typed pipeline ERASES to `any`, and Go has no pointer
covariance (a real `*int` cannot flow through an `any`-erased generic, nor can
you `*` an `any`).

The GO arm overrides these two leaves to typed Go primitives that carry the
pointer as `any` and DEREFERENCE IT BY REFLECTION (`reflect.ValueOf(p).Elem()`)
-- so the real `*int` flows through the generic instance as `any` and is read /
written generically.  This is the same proof-as-of-philosophy sidestep the
a0rf / axrf000 arm uses (bind the irreducible primitive directly), and it
avoids an addressable-var BOXING pass entirely.  `$addr(v)` stays a real Go
`&v`; only the deref is reflective.  The higher-level p2tr ops
([$UN.p2tr_ret], [$UN.p2tr_set_list_nil]/[_cons]) are pure ATS on top of these
two leaves, so they ride the override for free.
*)
//
(* ****** ****** *)
//
#staload UN =
"prelude/SATS/unsfx00.sats"
//
(* ****** ****** *)
//
#impltmp
< a:vt >
$UN.p2tr_get
(p0) =
(
XATS2GO_p2tr_get
  (p0)) where
{
#extern
fun
XATS2GO_p2tr_get
(p0: p2tr(a)): (a) = $extnam() }
//
#impltmp
<a>(*tmp*)
$UN.p2tr_set
(p0, x0) =
(
XATS2GO_p2tr_set
  (p0, x0)) where
{
#extern
fun
XATS2GO_p2tr_set
(p0: p2tr(a), x0: a): void = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_unsfx00.dats] *)
(***********************************************************************)
