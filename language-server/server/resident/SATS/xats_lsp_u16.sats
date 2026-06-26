(* ****** ****** *)
(*
UTF-16 column conversion — INTERFACE (portable ATS3).

The compiler reports positions as UTF-8 BYTE offsets within a line; LSP wants
UTF-16 code-unit offsets.  `lsp_byte2utf16` walks the line's codepoints summing
each one's UTF-8 byte length until it reaches byteCol, counting UTF-16 units (1
for BMP, 2 for astral / surrogate pair) — pure sint arithmetic, mirrors the
Scheme glue's LSP_u16 prefix logic.  ASCII lines yield byteCol unchanged.

Implementation in DATS/xats_lsp_u16.dats.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// utf16 code-unit column for `byteCol` (a UTF-8 byte offset) on 0-based `line` of `text`.
fun lsp_byte2utf16(text: string, line: sint, byteCol: sint): sint
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_u16.sats]
*)
