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
(*
CLAUDE-2026-08-28: string CONSTRUCTION lands (the go-arm higher-order
calling convention is settled: closures emit as typed Go funcs).  The
fwork emits char CODES; under the GO arm's byte-string model a code
<= 0xFF appends that BYTE verbatim (per-byte copies round-trip UTF-8),
a code > 0xFF appends its UTF-8 encoding.  This makes the prelude
string builders (strn_append & co, prelude/DATS/strn001.dats) resolve
to the floor instead of bridging to a nonexistent runtime leaf.
[strn_fmake_env$fwork]/[strn_fset$at$raw] remain deferred.
*)
#impltmp
<(*tmp*)>
strn_make_fwork
  (fwork) =
(
XATS2GO_strn_make_fwork
  (fwork)) where
{
#extern
fun
XATS2GO_strn_make_fwork
( fwork
: ((cgtz)->void)->void): strn = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_strn000.dats] *)
(***********************************************************************)
