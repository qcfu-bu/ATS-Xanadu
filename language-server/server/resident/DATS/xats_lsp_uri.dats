(* ****** ****** *)
(*
path <-> file:// URI — IMPLEMENTATION (portable ATS3, char-code + UTF-8 arithmetic).

Mirrors the Scheme glue's LSP_path2uri / vscode_url_to_path: per-char percent
encoding keeping path separators + unreserved ASCII; full UTF-8 multi-byte
encode/decode via plain integer arithmetic (mod = a-(a/64)*64).  Interface:
SATS/xats_lsp_uri.sats.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_uri.sats"
//
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
#extern fun str_of_code(c: sint): string = $extnam()
//
(* ****** ****** *)
//
// codepoint legend: 37 %  47 /  48..57 0-9  65..70 A-F  97..102 a-f
// unreserved per RFC/encodeURIComponent: A-Z a-z 0-9 - _ . ! ~ * ' ( )
//
fun uri_unreserved(c: sint): bool =
  if (if (c >= 65) then (c <= 90) else false) then true        (* A-Z *)
  else if (if (c >= 97) then (c <= 122) else false) then true  (* a-z *)
  else if (if (c >= 48) then (c <= 57) else false) then true   (* 0-9 *)
  else if (c = 45) then true else if (c = 95) then true        (* - _ *)
  else if (c = 46) then true else if (c = 33) then true        (* . ! *)
  else if (c = 126) then true else if (c = 42) then true       (* ~ * *)
  else if (c = 39) then true else if (c = 40) then true        (* ' ( *)
  else (c = 41)                                                (* ) *)
//
fun umod64(x: sint): sint = x - ((x / 64) * 64)
//
fun
uri_hexdig(n: sint): string =                       (* UPPERCASE hex, to match VSCode encodeURIComponent *)
  if (n < 10) then str_of_code(48 + n) else str_of_code(65 + n - 10)
// hex of the low nibble: b mod 16 = b - (b/16)*16
fun uri_lonib(b: sint): sint = b - ((b / 16) * 16)
//
(* ****** ****** *)
(* ---- encode: codepoint -> "%XX..." (UTF-8) or the raw char ---- *)
//
fun
uri_enc_char(cp: sint): string =
  if (cp = 47) then "/"                              (* keep path separator *)
  else if uri_unreserved(cp) then str_of_code(cp)    (* ASCII unreserved as-is *)
  else if (cp < 128) then uri_pctb(cp)               (* other ASCII -> %XX *)
  else if (cp < 2048) then                           (* 2-byte UTF-8 *)
    strn_append(uri_pctb(192 + (cp / 64)), uri_pctb(128 + umod64(cp)))
  else if (cp < 65536) then let                      (* 3-byte UTF-8 *)
    val b1 = cp / 4096
    val r1 = cp - (b1 * 4096)
    val b2 = r1 / 64
  in
    strn_append(uri_pctb(224 + b1), strn_append(uri_pctb(128 + b2), uri_pctb(128 + umod64(r1))))
  end
  else let                                           (* 4-byte UTF-8 *)
    val b1 = cp / 262144
    val r1 = cp - (b1 * 262144)
    val b2 = r1 / 4096
    val r2 = r1 - (b2 * 4096)
    val b3 = r2 / 64
  in
    strn_append(uri_pctb(240 + b1),
      strn_append(uri_pctb(128 + b2), strn_append(uri_pctb(128 + b3), uri_pctb(128 + umod64(r2)))))
  end
// one byte -> "%XX"
and
uri_pctb(b: sint): string =
  strn_append("%", strn_append(uri_hexdig(b / 16), uri_hexdig(uri_lonib(b))))
//
#implfun lsp_path2uri(path) = let
  val n = str_len(path)
  fun loop(i: sint, acc: string): string =
    if (i >= n) then acc else loop(i+1, strn_append(acc, uri_enc_char(str_char_code(path, i))))
in
  if (n = 0) then "" else strn_append("file://", loop(0, ""))
end
//
(* ****** ****** *)
(* ---- decode: "%XX" sequences (UTF-8) back to a string ---- *)
//
fun
uri_hexval(c: sint): sint =
  if (if (c >= 48) then (c <= 57) else false) then (c - 48)
  else if (if (c >= 97) then (c <= 102) else false) then (c - 87)
  else if (if (c >= 65) then (c <= 70) else false) then (c - 55)
  else 0
//
// read k continuation "%XX" bytes from p; fold into acc (acc*64 + (byte-128)).
fun
uri_cont(s: string, n: sint, p: sint, k: sint, acc: sint): @(sint, sint) =
  if (k <= 0) then @(acc, p)
  else if (if (p+2 < n) then (str_char_code(s, p) = 37) else false) then let
    val b = (uri_hexval(str_char_code(s, p+1)) * 16) + uri_hexval(str_char_code(s, p+2))
  in
    uri_cont(s, n, p+3, k-1, (acc * 64) + (b - 128))
  end
  else @(acc, p)
//
// decode s starting at code-index `start` (so "file://" can be skipped without a substring).
fun
uri_decode(s: string, start: sint): string = let
  val n = str_len(s)
  fun
  loop(i: sint, acc: string): string =
    if (i >= n) then acc
    else if (if (str_char_code(s, i) = 37) then (i+2 < n) else false) then let
      val b = (uri_hexval(str_char_code(s, i+1)) * 16) + uri_hexval(str_char_code(s, i+2))
    in
      if (b < 128) then loop(i+3, strn_append(acc, str_of_code(b)))
      else if (b < 224) then let val cj = uri_cont(s, n, i+3, 1, b - 192) in loop(cj.1, strn_append(acc, str_of_code(cj.0))) end
      else if (b < 240) then let val cj = uri_cont(s, n, i+3, 2, b - 224) in loop(cj.1, strn_append(acc, str_of_code(cj.0))) end
      else let val cj = uri_cont(s, n, i+3, 3, b - 240) in loop(cj.1, strn_append(acc, str_of_code(cj.0))) end
    end
    else loop(i+1, strn_append(acc, str_of_code(str_char_code(s, i))))
in
  loop(start, "")
end
//
// does s start with `pre` (compare code units; no `<>`/`&&` in this dialect)?
fun
str_startswith(s: string, pre: string): bool = let
  val np = str_len(pre)
  fun chk(i: sint): bool =
    if (i >= np) then true
    else if (str_char_code(s, i) = str_char_code(pre, i)) then chk(i+1) else false
in
  if (str_len(s) < np) then false else chk(0)
end
//
#implfun lsp_uri2path(uri) =
  if str_startswith(uri, "file://") then uri_decode(uri, 7) else uri_decode(uri, 0)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_uri.dats]
*)
