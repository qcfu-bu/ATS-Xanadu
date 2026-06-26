(* ****** ****** *)
(*
RESIDENT LSP server — FFI surface (SATS).

This is the SATS half of the resident in-process LSP server (workstream R1).
It declares the abstract handle types and the FFI functions implemented in
CATS/xats_lsp_resident.cats. The design mirrors the author's reference LSP
(github.com/qcfu-bu/ats-lsp, cloned at /tmp/qcfu-ats-lsp):
  * the vscode-languageserver connection loop lives in JS (the .cats);
  * cache eviction is `delete env[key]` over the compiler's per-file
    topmap caches (env_reset), keyed by the file's canonical stamp;
  * a depset/depgraph (JS Set/Map) records "B staloads A" so editing A
    evicts A AND its transitive dependents.

Unlike the reference, the harvest (diagnostics + hover/def index) is OUR
existing traversal (server/DATS/xats_lsp_check.dats): instead of writing a
JSON bundle to a temp file, the resident server pushes harvested rows into a
per-uri in-memory index held in the .cats, which onHover/onDefinition read.
*)
(* ****** ****** *)
//
#include "./../HATS/libxatsopt_resident.hats"
//
(* ****** ****** *)
//
// uri (an opaque LSP document-uri string handle) and the url->fspath map.
//
#abstype url <= p0tr
#extern fun url_to_path(url) : string
//
(* ****** ****** *)
//
// LSP diagnostic severity (opaque enum handle).
//
#abstype severity <= p0tr
fun severity_error$make() : severity
//
(* ****** ****** *)
//
// LSP Position / Range (opaque {line,character} / {start,end} handles).
//
#abstype position <= p0tr
fun position_make(line: int, offs: int) : position
//
#abstype range <= p0tr
fun range_make(pbeg: position, pend: position) : range
fun range_of_loctn(loctn) : range
//
(* ****** ****** *)
//
// LSP Diagnostic + the per-validation diagnostics accumulator (opaque array).
//
#abstype diagnostic <= p0tr
fun diagnostic_make
  (severity: severity, location: range, message: string, source: string)
  : diagnostic
//
#abstype diagnostics <= p0tr
fun diagnostics_push(ds: diagnostics, d: diagnostic) : void
#symload push with diagnostics_push
//
(* ****** ****** *)
//
// regex (used to dispatch .dats vs .sats on the resolved path).
//
#abstype regex <= p0tr
fun regex_make(pat: string) : regex
fun regex_test(re: regex, input: string): bool
//
(* ****** ****** *)
//
// dependency set / graph (JS Set / Map). depgraph maps a file's stamp to
// (its sym_t, the Set of dependent files' sym_t). depset is the worklist of
// files to evict. Ported verbatim from the reference lsp_bootstrap.{sats,js}.
//
#abstype depset <= p0tr
fun depset_make(): depset
fun depset_add(depset, sym_t): void
fun depset_pop(depset): sym_t
fun depset_is_empty(depset): bool
fun depset_has(depset, sym_t): bool
fun depset_union(depset, depset): depset
//
#abstype depgraph <= p0tr
fun depgraph_add(depgraph, sym_t, sym_t): void
fun depgraph_delete(depgraph, sym_t): void
fun depgraph_has(depgraph, sym_t): bool
fun depgraph_find(depgraph, sym_t): depset
//
// the FORWARD staload graph ("key0 staloads key1"); the reverse of the
// dependents graph handed to the validator/pruner. Held in the .cats (like
// LSP_dependencies) and fetched here so the precheck can walk a target's
// transitive-staload closure. Same depgraph type; populated in the same pass.
fun fwd_graph(): depgraph
//
(* ****** ****** *)
//
// THE cache-eviction primitive (the make-or-break part). The compiler caches
// each translated file in the_d{1,2,3}parenv (xglobal.sats), which are plain
// JS objects (jshmap) keyed by the file's canonical stamp (fnm2().stmp());
// see srcgen2/DATS/xsymmap_topmap.dats (topmap_insert keys by key.stmp()).
// env_reset(env, sym) ≈ delete env[sym.stmp()] evicts exactly that file so a
// subsequent d3parsed_of_fil re-translates it (prelude + unchanged deps stay
// cached -> warm + fast).
//
fun env_reset{syn:tx}(topmap(syn), sym_t): void
//
// R2b — evict a file from all three per-file caches BY ITS STAMP (a bare uint).
// Used by the workspace/didChangeWatchedFiles cascade, which is driven from JS
// over the PROJECT index (keyed by path); JS maps each affected path -> stamp
// (the path->stamp index built alongside the signature map) and calls this to do
// the actual eviction. Kept on the ATS side because it must deref the live
// the_d{1,2,3}parenv_pvstmap() topmaps FRESH each time (xglobal_reset swaps in
// new topmap objects on a prelude reload — a cached JS object handle would go
// stale). A stamp with no cached entry is a harmless no-op (never-checked file).
//
fun evict_stamp(stamp): void
//
(* ****** ****** *)
//
// R2a — content-validated cache (out-of-band-edit invalidation).
//
// PRELUDE SNAPSHOT: right after the prelude loads (before any user file is
// checked) we record the set of file stamps already cached in the_d{1,2,3}parenv.
// That set = the prelude / $XATSHOME files; they are IMMUTABLE for the session
// (never stat, never evict). prelude_snapshot(env) records one topmap's keys;
// prelude_freeze() seals the set (called once after the snapshot is complete).
//
fun prelude_snapshot{syn:tx}(topmap(syn)): void
fun prelude_freeze(): void
// clear the snapshot Set before re-snapshotting after a prelude reload.
fun prelude_snapshot_reset(): void
//
// SIGNATURE MAP: stamp -> {path, mtimeMs, size} for each cached WORKSPACE file.
//   sig_record(key, path): stat `path` now and record its signature under `key`
//                          (no-op for prelude files — they stay immutable).
//   sig_refresh(key)     : re-stat and update the recorded signature.
//   sig_changed(key)     : true iff `key` is a known workspace file whose on-disk
//                          signature drifted (out-of-band edit). Re-stats; cheap.
//
fun sig_record(sym_t, string): void
fun sig_refresh(sym_t): void
fun sig_changed(sym_t): bool
//
(* ****** ****** *)
//
// HARVEST push primitives. The traversal pushes rows into the .cats's per-uri
// index. diag rows feed the LSP Diagnostic[] (built in JS, dedup per D6); hover
// and def rows feed the onHover/onDefinition lookups. These replace the JSON
// bundle of the spawn model — same data, in-memory, no temp file.
//
fun diag_push
  ( l0: int, c0: int, l1: int, c1: int
  , code: string, message: string) : void
//
fun hover_push
  ( l0: int, c0: int, l1: int, c1: int
  , typ: string, kind: string) : void
//
fun def_push
  ( ul0: int, uc0: int, ul1: int, uc1: int
  , defpath: string
  , dl0: int, dc0: int, dl1: int, dc1: int
  , entity: string
  , hastdef: int
  , tdpath: string
  , tl0: int, tc0: int, tl1: int, tc1: int) : void
//
// SEMANTIC TOKENS push primitive. The harvest traversal emits one row per
// identifier-bearing node: the node's USE-SITE loctn (l0,c0..l1,c1 in 0-based
// byte coords — JS converts to UTF-16), the resolved token TYPE INDEX into the
// legend, the static MODIFIER bitset, and the entity's DEF-PATH string (so JS
// can OR in `defaultLibrary` when the def resolves under $XATSHOME). The .cats
// accumulates these, sorts + delta-encodes them into the LSP flat int array,
// and serves them from textDocument/semanticTokens/full.
//
fun token_push
  ( l0: int, c0: int, l1: int, c1: int
  , ttype: int, tmods: int, defpath: string) : void
//
// WS-5 DOCUMENT SYMBOL push: one row per top-level declaration name — the name's
// 0-based byte range, the LSP SymbolKind index, and a container name ("" for a
// top-level symbol). The .cats accumulates + shapes these for
// textDocument/documentSymbol.
//
fun symbol_push
  ( l0: int, c0: int, l1: int, c1: int
  , name: string, kind: int, container: string, typ: string) : void
//
// WS-5 INLAY HINT push: one row per inferred val-binding — the 0-based byte
// position (end of the bound name), the label ("\: <type>"), and the
// InlayHintKind (1 = Type). Served from textDocument/inlayHint.
//
fun inlay_push
  ( line: int, col: int, label: string, kind: int) : void
//
// WS-6 Stage 2 SCOPE push: one row per local binder (fun/lambda param, let-val) —
// the 0-based byte VISIBILITY range (its enclosing body), the binder name, and its
// inferred type. Feeds scope-aware completion (locals ranked above globals).
//
fun scope_push
  ( l0: int, c0: int, l1: int, c1: int
  , name: string, typ: string) : void
//
// WS-6 Stage 3 MEMBER push: one row per record field of a receiver's type — the
// 0-based byte range of the RECEIVER expression, the field name, and its type.
// Feeds `recv.field` member completion.
//
fun member_push
  ( l0: int, c0: int, l1: int, c1: int
  , name: string, typ: string) : void
//
(* ****** ****** *)
//
// the resident bootstrap entry: register the in-process validator + pruner
// callbacks with the vscode-languageserver connection loop, then listen.
//   validator(deps, diags, uri): check `uri` in-process -> push diags + index.
//   liveval(deps, diags, uri, text): check the in-memory `text` (the unsaved
//      editor buffer) for `uri` in-process -> push diags + index (live-on-change).
//   pruner(deps, uri)          : evict `uri` + dependents from the caches.
//
#typedef text_validator_t = (depgraph, diagnostics, url) -> void
// live_validator_t (P4 live-on-change): validate the UNSAVED in-memory buffer.
// Same shape as text_validator_t but with the editor's current text passed in
// (the .cats hands us textDocument.getText()); we parse THAT text in-memory with
// the source identity set to the document's real path, so diagnostics/loctns map
// back to the real uri and relative #staloads resolve from the file's directory.
#typedef live_validator_t = (depgraph, diagnostics, url, string) -> void
#typedef cache_pruner_t = (depgraph, url) -> void
// reload_prelude_t: the in-process prelude reload, registered alongside the
// validator/pruner. The .cats calls it on didSave of a $XATSHOME file.
#typedef reload_prelude_t = () -> void
// evict_stamp_t (R2b): evict ONE file (by its bare-uint stamp) from the three
// per-file caches. The .cats's workspace/didChangeWatchedFiles handler calls it
// for every file in the changed file's transitive project-reverse closure.
#typedef evict_stamp_t = (stamp) -> void
// add_flag_t: set ONE compiler flag (e.g. "--_XATS2JS_") in the global flag
// table (xatsopt_flag$pvsadd0). The .cats reads the workspace `.xats-lsp` file at
// initialize and calls this for each configured flag, so `#if defq(...)` blocks
// resolve the way the project's real build does (no spurious LSP diagnostics on
// build-flag-gated declarations).
#typedef add_flag_t = (string) -> void
fun initialize
  ( text_validator_t, live_validator_t
  , cache_pruner_t, reload_prelude_t, evict_stamp_t, add_flag_t) : void
// lsp_addflag: the flag-setter callback impl (passed to initialize).
fun lsp_addflag(string): void
//
// the resident callbacks themselves (declared here, #implfun'd in the DATS,
// then passed to initialize). The reference declares these in server.sats.
//
fun text_validator(depgraph, diagnostics, url): void
// live_validator: the in-memory (unsaved-buffer) validate path.
fun live_validator(depgraph, diagnostics, url, string): void
fun cache_pruner(depgraph, url): void
//
(* ****** ****** *)
//
// reload_prelude: the in-process prelude reload for the "workspace IS the
// prelude / $XATSHOME" edge case. Calls the compiler's xglobal_reset() (clears
// the global envs + per-file caches + d2cstmap, re-arms the the_ntime gates) and
// then replays the startup prelude-load + flag sequence so the EDITED prelude is
// reloaded fresh from disk. The .cats invokes this on didSave of a file resolving
// under $XATSHOME, then clears its own caches and re-validates every open doc.
//
fun reload_prelude(): void
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_resident.sats]
*)
