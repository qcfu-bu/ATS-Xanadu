(* ****** ****** *)
(*
UTF-16 column conversion — IMPLEMENTATION (portable ATS3).

Mirrors the Scheme glue's LSP_u16_make: pref[byteCol] = UTF-16 code units in the
line's first byteCol UTF-8 bytes.  Here we walk codepoints (str_char_code) instead
of bytes, summing each codepoint's UTF-8 byte length, so we never need raw byte
access.  Interface: SATS/xats_lsp_u16.sats.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_u16.sats"
//
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
//
(* ****** ****** *)
//
// UTF-8 byte length of a codepoint.
fun
u16_utf8len(cp: sint): sint =
  if (cp < 128) then 1 else if (cp < 2048) then 2 else if (cp < 65536) then 3 else 4
//
#implfun lsp_byte2utf16(text, line, byteCol) = let
  val n = str_len(text)
  // codepoint index where 0-based `line` starts (newline = code 10 = 1 byte = 1 cp).
  fun
  find_start(i: sint, ln: sint): sint =
    if (ln >= line) then i
    else if (i >= n) then i
    else if (str_char_code(text, i) = 10) then find_start(i+1, ln+1)
    else find_start(i+1, ln)
  val start = (if (line <= 0) then 0 else find_start(0, 0))
  // count UTF-16 units of codepoints whose byte-range lies fully within [0, byteCol).
  fun
  walk(i: sint, bytes: sint, units: sint): sint =
    if (i >= n) then units
    else let val cp = str_char_code(text, i) in
      if (cp = 10) then units                          (* end of line *)
      else let val sq = u16_utf8len(cp) in
        if ((bytes + sq) > byteCol) then units          (* this char crosses byteCol: stop *)
        else walk(i+1, bytes + sq, units + (if (cp >= 65536) then 2 else 1))
      end
    end
in
  if (byteCol <= 0) then 0 else walk(start, 0, 0)
end
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_u16.dats]
*)
