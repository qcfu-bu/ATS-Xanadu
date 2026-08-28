(* ****** ****** *)
(*
lsp_util.sats — byte-level string helpers shared by the server modules.

The GO arm's strings are NATIVE Go strings (byte strings): strn_length
counts BYTES, strn_get$at yields the BYTE at an index (as a char code
0..255).  All helpers here are byte-indexed; UTF-8 awareness lives in
the modules that need it (lsp_u16, later).
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
//
(* copy bytes [i0, j0) of s0 into a fresh string; bounds are the caller's *)
fun
strn_slice(s0: string, i0: sint, j0: sint): string
//
(* byte-wise string equality *)
fun
streq(s1: string, s2: string): bool
//
(* decimal rendering of a signed integer *)
fun
itoa(x0: sint): string
//
(* the byte at i0 as an integer code 0..255 *)
fun
byte_at(s0: string, i0: sint): sint
//
(* does ndl occur at position i0 of hay? *)
fun
strn_starts_at(hay: string, i0: sint, ndl: string): bool
//
(* first index >= i0 where ndl occurs in hay, or -1 *)
fun
strn_index_of(hay: string, i0: sint, ndl: string): sint
//
(* parse a decimal digit run at i0: @(value, next); next = i0 if none *)
fun
atoi_at(s0: string, i0: sint): @(sint, sint)
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_util.sats] *)
(***********************************************************************)
