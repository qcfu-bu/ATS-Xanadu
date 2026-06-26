(* ****** ****** *)
(*
Document store — IMPLEMENTATION (portable ATS3).

The editor text buffers as an assoc-list (uri -> @(text, version)) behind one
cell, the incremental range-edit (prefix ++ newtext ++ suffix via str_slice), and
the cursor completion-context scan (backward word run + `recv.` member detection,
char codes only).  Mirrors the Scheme glue's LSP_docs / LSP-offset-at /
LSP-apply-change / LSP_build_completion byte-for-byte.  Interface:
SATS/xats_lsp_doc.sats.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_doc.sats"
//
#include "./../HATS/xats_lsp_ref.hats"
//
(* ****** ****** *)
//
// leaves: int->text + the string primitives.  str_slice = O(len) substring
// (Chez `substring`; codepoint-indexed, matching the str_len/str_char_code
// codepoint contract) — used so range edits on a large buffer stay O(n), not the
// O(n^2) of char-by-char strn_append.
#extern fun int2str(n: sint): string = $extnam()
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
#extern fun str_of_code(c: sint): string = $extnam()
#extern fun str_slice(s: string, a: sint, b: sint): string = $extnam()
//
(* ****** ****** *)
//
#typedef dval = @(string, sint)             // (text, version)
#typedef dmap = list(@(string, dval))       // uri -> (text, version)
//
val the_docs: lspcell(dmap) = cell_make(list_nil())
//
(* ---- assoc-list store helpers ---- *)
//
fun dmap_has(m: dmap, k: string): bool =
  (case+ m of list_nil() => false | list_cons(kv, r) => (if strn_eq(kv.0, k) then true else dmap_has(r, k)))
fun dmap_get(m: dmap, k: string): dval =
  (case+ m of list_nil() => @("", 0) | list_cons(kv, r) => (if strn_eq(kv.0, k) then kv.1 else dmap_get(r, k)))
fun dmap_put(m: dmap, k: string, v: dval): dmap =
  (case+ m of
   | list_nil() => list_cons(@(k, v), list_nil())
   | list_cons(kv, r) => (if strn_eq(kv.0, k) then list_cons(@(k, v), r) else list_cons(kv, dmap_put(r, k, v))))
fun dmap_del(m: dmap, k: string): dmap =
  (case+ m of
   | list_nil() => list_nil()
   | list_cons(kv, r) => (if strn_eq(kv.0, k) then r else list_cons(kv, dmap_del(r, k))))
//
(* ****** ****** *)
//
#implfun doc_set(uri, text, version) =
  cell_set(the_docs, dmap_put(cell_get(the_docs), uri, @(text, version)))
//
#implfun doc_has(uri) = dmap_has(cell_get(the_docs), uri)
//
#implfun doc_text(uri) = let val v = dmap_get(cell_get(the_docs), uri) in v.0 end
//
#implfun doc_del(uri) = cell_set(the_docs, dmap_del(cell_get(the_docs), uri))
//
// newline-join the keys WITH a trailing newline (so the empty store -> "").
fun keys_join(m: dmap): string =
  (case+ m of
   | list_nil() => ""
   | list_cons(kv, r) => strn_append(strn_append(kv.0, str_of_code(10)), keys_join(r)))
#implfun doc_uris() = keys_join(cell_get(the_docs))
//
(* ****** ****** *)
//
// 0-based (line,char) -> char offset (matches glue LSP-offset-at: clamp to end of
// text by min, NOT to the line's end).
fun
offset_at(text: string, line: sint, char: sint): sint = let
  val n = str_len(text)
  fun loop(i: sint, ln: sint): sint =
    if (ln = line) then (if (i + char < n) then i + char else n)
    else if (i >= n) then n
    else if (str_char_code(text, i) = 10) then loop(i+1, ln+1)
    else loop(i+1, ln)
in
  loop(0, 0)
end
//
#implfun doc_apply_range(text, sl, sc, el, ec, newtext) = let
  val n = str_len(text)
  val so = offset_at(text, sl, sc)
  val eo = offset_at(text, el, ec)
in
  strn_append(strn_append(str_slice(text, 0, so), newtext), str_slice(text, eo, n))
end
//
(* ****** ****** *)
//
// identifier char (matches glue LSP-ident-ch?): A-Z a-z 0-9 _ $ '
fun
is_ident_code(c: sint): bool =
  if (if (c >= 65) then (c <= 90) else false) then true
  else if (if (c >= 97) then (c <= 122) else false) then true
  else if (if (c >= 48) then (c <= 57) else false) then true
  else if (c = 95) then true
  else if (c = 36) then true
  else if (c = 39) then true
  else false
//
#implfun doc_complete_ctx(uri, line, char) = let
  val text = doc_text(uri)
  val offset = offset_at(text, line, char)
  // wstart: scan back over the identifier run ending at the cursor.
  fun back_word(i: sint): sint =
    if (i <= 0) then 0
    else if is_ident_code(str_char_code(text, i - 1)) then back_word(i - 1)
    else i
  val wstart = back_word(offset)
  val word = str_slice(text, wstart, offset)
  // j0: skip spaces/tabs before the word; member? iff the char there is '.'.
  fun back_ws(j: sint): sint =
    if (j < 0) then j
    else let val cj = str_char_code(text, j) in
      (if (if (cj = 32) then true else (cj = 9)) then back_ws(j - 1) else j) end
  val j0 = back_ws(wstart - 1)
  val isMember = (if (j0 >= 0) then (str_char_code(text, j0) = 46) else false)
  val wcol = char - (offset - wstart)
  val dotCol = (if isMember then char - (offset - j0) else 0)
  val mflag = (if isMember then "1" else "0")
  val nl = str_of_code(10)
in
  strn_append(word, strn_append(nl,
    strn_append(mflag, strn_append(nl,
      strn_append(int2str(dotCol), strn_append(nl, int2str(wcol)))))))
end
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_doc.dats]
*)
