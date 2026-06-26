(* ****** ****** *)
(*
Per-check conversion layer — INTERFACE (portable ATS3).

The harvest sinks (xats_lsp_index) convert their raw rows at PUSH time using a
few per-check facts: the friendly typename remap for mismatch messages, whether a
def-target uri IS the current document, and path -> file:// uri (with the
cur-document remap so a within-file definition keeps the editor's own uri).  The
per-check state (current uri + current normalized path) is set by the validate
driver via conv_set_cur before each check (conv_set_cur("","") clears it).

The UTF-16 column conversions (LSP_cur_b2u / LSP_other_b2u) are here too: a
whole-text ASCII fast path (byteCol == utf16Col, O(1)) covers the common case
(incl. the all-ASCII compiler-linking files); a mixed/non-ASCII text falls back to
the tested xats_lsp_u16 walk.  Names keep the LSP_ prefix so the index call sites
are unchanged (they now resolve to these ATS funs, not the old glue leaves).

Implementation in DATS/xats_lsp_conv.dats.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// set the current check's editor uri + raw fs path (normalized internally) + the
// source text (for UTF-16 conversion); pass ("","","") to clear between checks.
// Also resets the per-check other-file conversion cache.
fun conv_set_cur(uri: string, path: string, text: string): void
//
// byte column -> UTF-16 code-unit column on 0-based `line`: of the CURRENT document
// (cur_b2u), or of another def-target file `path` read on demand + cached per check
// (other_b2u).  Disabled (ATS3_LSP_UTF16=0) => returns the byte column unchanged.
fun LSP_cur_b2u(line: int, col: int): int
fun LSP_other_b2u(path: string, line: int, col: int): int
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
// is `path` under one of the loaded-prelude roots ($XATSHOME/{prelude,srcgen1,
// srcgen2,xassets}/)?  Immutable files: never live-validated, trigger a prelude
// reload on save.  Roots are computed once from $XATSHOME at module load.
fun JS_path_is_prelude(path: string): bool
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_conv.sats]
*)
