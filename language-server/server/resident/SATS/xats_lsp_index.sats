(* ****** ****** *)
(*
Per-uri LSP index: harvest accumulators + dedup + request builders — INTERFACE.

This is the ATS3 port of the Scheme glue's per-check accumulators (LSP_cur_*), the
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
//       7 semanticTokens/full, 8 indexStats.  a/b = position line/char (0..5);
// returns a serialized JSON value ("null" / "[]" / "{...}").
fun idx_query
  (uri: string, kind: int, a: int, b: int, c: int, d: int): string
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_index.sats]
*)
