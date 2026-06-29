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
CATS/GO/xtop000.dats — the GO arm for the top-level I/O prelude.  Mirrors
CATS/JS/xtop000.dats (XATS2JS_* -> XATS2GO_*).  [the_print_store_log] is a
COMPOSED template body (console_log of the flushed store); the leaves
[console_log] / [the_print_store_flush] bind to the self-contained GO floor in
xtop000.cats.
*)
//
(* ****** ****** *)
//
#abstype
console_type
#typedef
console = console_type
//
#extern
fun<>
console_log
{t0:t0}(x0: t0): void
//
#impltmp
<(*tmp*)>
console_log
  ( x0 ) =
(
XATS2GO_console_log
  ( x0 )) where
{
#extern
fun
XATS2GO_console_log
{t0:t0}(x0: t0): void = $extnam() }
//
(* ****** ****** *)
//
#extern
fun<>
the_print_store_log(): void
//
#extern
fun<>
the_print_store_flush(): strn
//
#impltmp
<(*tmp*)>
the_print_store_log() =
console_log(the_print_store_flush())
//
#impltmp
<(*tmp*)>
the_print_store_flush
  ((*void*)) =
(
XATS2GO_the_print_store_flush
  ((*void*))) where
{
#extern
fun
XATS2GO_the_print_store_flush(): strn = $extnam() }
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3_XANADU_prelude_DATS_CATS_GO_xtop000.dats] *)
(***********************************************************************)
