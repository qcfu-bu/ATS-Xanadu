(* ****** ****** *)
(*
Project staload graph — INTERFACE (portable ATS3).

The ATS3 port of the Scheme glue's project index (LSP_proj_fwd / LSP_proj_rev /
LSP_proj_indexed) + the `#staload`/`#include`/`#dynload` path scanner
(LSP_parse_staloads, the last regex use — now a pure char scan) + the reverse
closure (LSP_proj_rev_closure) used by the workspace/didChangeWatchedFiles cascade.

The module OWNS the three path graphs behind cells (xats_lsp_ref.hats).  The glue
drives it by absolute path string; the workspace directory WALK (scan_dir over the
filesystem) stays glue, calling proj_index_file per source file.  The per-path
SYMBOL cache (LSP_proj_symbols) is a separate, completion-coupled structure that
stays glue for now (Step 5 symbol surface).  Implementation: DATS/xats_lsp_proj.dats.

Paths are normalized absolute (the glue passes uri->path->norm); the module
re-normalizes (collapse ./..) defensively + resolves relative `#staload` refs
against the file's directory.  One stateful glue leaf: JS_path_is_prelude (drop
prelude targets) — same classification the rest of the server uses.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// parse `path`'s staloads from `text`, (re)wire its forward/reverse edges, mark it
// indexed; returns the normalized path ("" if empty/prelude/skipped).
fun proj_index_file(path: string, text: string): string
// drop a path from the graphs + the indexed set.
fun proj_remove_file(path: string): void
// the transitive set of files that (directly or indirectly) staload `path`,
// EXCLUDING `path` itself, as a newline-joined string ("" if none).  The glue's
// watched-files handler splits this, adds the file itself, and evicts each by stamp.
fun proj_rev_closure(path: string): string
//
// graph sizes for the scan metric line.
fun proj_fwd_count((*void*)): int
fun proj_rev_count((*void*)): int
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_proj.sats]
*)
