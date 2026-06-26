(* ****** ****** *)
(*
Document store — INTERFACE (portable ATS3).

The editor's in-memory text buffers (uri -> current text + version), the
incremental-change application (range edit -> new full text), and the
completion-context extraction (the partial word + member-mode `recv.` detection
at the cursor).  Pure string + list + sint work behind one mutable cell; mirrors
the Scheme glue's LSP_docs / LSP-apply-change / LSP_build_completion shim.

Implementation in DATS/xats_lsp_doc.dats.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// store ops: set/overwrite a doc's text+version, test presence, fetch text
// (""=absent — callers guard with doc_has), drop a doc.
fun doc_set(uri: string, text: string, version: int): void
fun doc_has(uri: string): bool
fun doc_text(uri: string): string
fun doc_del(uri: string): void
//
// the open-doc uris, newline-joined with a trailing newline ("" if none); the
// backend splits + drops empties.  Used to revalidate open docs after a prelude
// reload / watched-file change.
fun doc_uris(): string
//
// apply ONE incremental {range,text} contentChange to `text`, returning the new
// full text (PURE — the backend threads it across a multi-change array, then
// doc_set's the result).  A whole-document change (no range) needs no call.
fun doc_apply_range
  (text: string, sl: int, sc: int, el: int, ec: int, newtext: string): string
//
// completion context at 0-based (line,char): the four doc-derived values the ATS
// completion builder needs, newline-joined as "word\nisMember(0/1)\ndotCol\nwcol".
fun doc_complete_ctx(uri: string, line: int, char: int): string
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_doc.sats]
*)
