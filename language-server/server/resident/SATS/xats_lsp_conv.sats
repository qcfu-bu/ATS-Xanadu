(* ****** ****** *)
(*
Per-check conversion layer — INTERFACE (portable ATS3).

The harvest sinks (xats_lsp_index) convert their raw rows at PUSH time using a
few per-check facts: the friendly typename remap for mismatch messages, whether a
def-target uri IS the current document, and path -> file:// uri (with the
cur-document remap so a within-file definition keeps the editor's own uri).  The
per-check state (current uri + current normalized path) is set by the validate
driver via conv_set_cur before each check (conv_set_cur("","") clears it).

The UTF-16 column conversions (LSP_cur_b2u / LSP_other_b2u) stay backend leaves
for now — they need a per-line prefix cache to stay O(1), unlike these O(path)
ops.  Names keep the LSP_ prefix so the index call sites are unchanged (they now
resolve to these ATS funs, not the old glue leaves).

Implementation in DATS/xats_lsp_conv.dats.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// set the current check's editor uri + raw fs path (normalized internally); pass
// ("","") to clear between checks.
fun conv_set_cur(uri: string, path: string): void
//
// remap any `name` (backtick-delimited identifier) that has a friendly alias.
fun LSP_friendly(msg: string): string
//
// is this def-target uri the document currently under check?
fun LSP_def_in_current(uri: string): bool
//
// path -> file:// uri; if `path` normalizes to the current document's path return
// the editor's own uri (so within-file go-to-def stays in the same document).
fun LSP_path2uri(path: string): string
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_conv.sats]
*)
