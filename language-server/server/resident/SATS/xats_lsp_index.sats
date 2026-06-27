(* ****** ****** *)
(*
Per-uri LSP index: harvest accumulators + dedup + request builders — INTERFACE.

This is the ATS3 port of the Scheme glue's per-check accumulators (the LSP_cur_* set), the
per-uri index (LSP_index), the diag/hover/def/inlay dedups + token delta-encoder,
and the request builders for hover / definition / typeDefinition / references /
documentHighlight / inlayHint / semanticTokens / indexStats + the published
diagnostics array.  Everything here is pure jval + list + sint work (portable);
the byte->UTF-16 column conversion, path->uri, friendly-name remap and prelude
classification stay as six STATEFUL glue leaves (the per-check current-document
u16 converter, the other-file converter cache, the cur-uri remap — they belong to
the validate lifecycle, which is still glue / Step 6) — see DATS for the externs.

OWNERSHIP: this module owns the five accumulators (diags/hovers/defs/tokens/inlays)
AND the uri -> snapshot map, all behind cells (xats_lsp_ref.hats).  The glue holds
NO index object — it drives this module by uri string only:
  idx_reset()            : clear the accumulators before a check
  idx_*_push(...)        : harvest sinks (the driver forwards diag_push etc. here)
  idx_commit(uri)        : dedup the accumulators -> store the snapshot under uri
  idx_diagnostics()      : the published Diagnostic[] for the just-finished check
  idx_ndiags()           : its length (for the metric line)
  idx_count(uri, which)  : 0=hovers 1=defs 2=tokens, from the stored snapshot
  idx_query(uri,k,a,b,c,d): one multiplexed builder (k selects the request) -> JSON
  idx_evict(uri)         : drop a uri (didClose)
  idx_clear()            : drop everything (prelude reload)
The symbol/scope/member rows + completion/workspace builders stay glue-side (they
are coupled to the prelude/staload symbol indices = Step 5), so this module does
NOT own those three accumulators.  Implementation: DATS/xats_lsp_index.dats.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
// ---- harvest sinks (the driver's diag_push/... forward here) ----
//
fun idx_diag_push
  ( l0: int, c0: int, l1: int, c1: int
  , code: string, message: string) : void
//
fun idx_hover_push
  ( l0: int, c0: int, l1: int, c1: int
  , typ: string, kind: string) : void
//
fun idx_def_push
  ( ul0: int, uc0: int, ul1: int, uc1: int
  , defpath: string
  , dl0: int, dc0: int, dl1: int, dc1: int
  , entity: string
  , hastdef: int
  , tdpath: string
  , tl0: int, tc0: int, tl1: int, tc1: int) : void
//
fun idx_token_push
  ( l0: int, c0: int, l1: int, c1: int
  , ttype: int, tmods: int, defpath: string) : void
//
fun idx_inlay_push
  ( line: int, col: int, label: string, kind: int) : void
//
// WS-5/WS-6 sinks: document symbols + scope binders + receiver members.  These
// feed documentSymbol / workspaceSymbol / completion (all ATS now).
fun idx_symbol_push
  ( l0: int, c0: int, l1: int, c1: int
  , name: string, kind: int, container: string, typ: string) : void
fun idx_scope_push
  ( l0: int, c0: int, l1: int, c1: int, name: string, typ: string) : void
fun idx_member_push
  ( l0: int, c0: int, l1: int, c1: int, name: string, typ: string) : void
//
// ---- completion symbol caches (filled by the driver's prelude/staload harvest) ----
// prelude pervasives (indexed once at startup) + the staloaded-API closure (indexed
// once per staloaded file, deduped by file STAMP).  Names are NOT deduped at push
// (the completion query's per-request `seen` set handles it) to keep the build O(n).
fun idx_prelude_reset((*void*)): void
fun idx_prelude_push(name: string, kind: int, typ: string): void
fun idx_prelude_done((*void*)): void
fun idx_prelude_count((*void*)): int   // for the startup metric line
fun idx_staload_seen(stamp: int): bool
fun idx_staload_mark(stamp: int): void
fun idx_staload_push(name: string, kind: int, typ: string): void
fun idx_staload_reset((*void*)): void
// project symbol cache: bg-indexed (unopened) files' symbols, path-keyed.
// idx_proj_store snapshots the CURRENT symbol accumulator under `path`/`uri`.
fun idx_proj_store(path: string, uri: string): void
fun idx_proj_delete(path: string): void
//
(* ****** ****** *)
//
// ---- lifecycle + builders (driven by the glue, by uri string) ----
//
fun idx_reset((*void*)): void
fun idx_commit(uri: string): void
fun idx_evict(uri: string): void
fun idx_clear((*void*)): void
//
fun idx_diagnostics((*void*)): string
fun idx_ndiags((*void*)): int
fun idx_count(uri: string, which: int): int
//
// kind: 0 hover, 1 definition, 2 typeDefinition, 3 references (c=includeDecl),
//       4 documentHighlight, 5 inlayHint (all), 6 inlayHint (range a/b/c/d),
//       7 semanticTokens/full, 8 indexStats, 9 documentSymbol.  a/b = position
//       line/char.  Returns a serialized JSON value ("null" / "[]" / "{...}").
fun idx_query
  (uri: string, kind: int, a: int, b: int, c: int, d: int): string
// workspace/symbol (fuzzy-filtered across the index + project cache).
fun idx_workspace(query: string): string
// completion: the glue supplies the doc-store-derived partial word + member-mode
// state (isMember 0/1, the dot position, and the replacement column wcol).
fun idx_completion
  ( uri: string, line: int, char: int, word: string
  , isMember: int, dotLine: int, dotCol: int, wcol: int): string
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_index.sats]
*)
