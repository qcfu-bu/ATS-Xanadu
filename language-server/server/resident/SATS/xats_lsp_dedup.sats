(* ****** ****** *)
(*
Dedup + position-sort for harvested LSP items — INTERFACE (portable ATS3).

Mirrors the Scheme glue's LSP_dedup_* (hovers/defs/symbols/inlays/scopes/members):
drop items with a negative start position, keep the FIRST occurrence per dedup key,
then stable-sort by a field spec.  Items are `jval` objects (JVobj) using the
position-field convention l0/c0 = start line/col, l1/c1 = end line/col (matching
the Scheme vector indices 0..3); type-specific fields add to the dedup key.

The diagnostics dedup (overlap suppression + severity rank) is special and lives
with the diagnostics builder, not here.  Implementation: DATS/xats_lsp_dedup.dats.
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
#staload "./xats_lsp_json.sats"
//
(* ****** ****** *)
//
// a sort spec is a list of (field-name, ascending?) compared left to right.
#typedef sortspec = list(@(string, bool))
//
// filter (l0>=0, c0>=0) -> dedup keeping first per key (join of `keyfields`) ->
// stable sort by `spec`.
fun
jdedup_sort
  (items: list(jval), keyfields: list(string), spec: sortspec): list(jval)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_dedup.sats]
*)
