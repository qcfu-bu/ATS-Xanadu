(* ****** ****** *)
(*
RESIDENT LSP server — main driver (DATS).  Workstream R1.

ONE resident artifact: a long-running ATS3->JS node program that bundles the
ATS3 compiler front-end and checks IN-PROCESS. The prelude is loaded ONCE at
startup; each check reuses the warm compiler.

This file:
  (1) implements the FFI surface declared in SATS/xats_lsp_resident.sats by
      forwarding to the same-named JS bodies in CATS/xats_lsp_resident.cats;
  (2) ports the reference's dependency-extraction pass (dependency30): walks a
      checked d3parsed, and for every `staload` edge adds "B depends on A" to the
      depgraph so editing A later evicts A AND B;
  (3) REUSES our harvest traversal + s2typ pretty-printer (copied from
      server/DATS/xats_lsp_check.dats) — at each `…errck` it classifies a
      diagnostic; at every typed d3exp/d3pat it emits a hover; at every
      D3Evar/D3Ecst/D3Econ use site it emits a definition. Instead of writing a
      JSON bundle, it pushes rows into the .cats's per-uri in-memory index;
  (4) defines text_validator (didOpen/didSave -> in-process check + harvest) and
      cache_pruner (didChange -> env_reset over the topmaps + dependents);
  (5) startup: the_fxtyenv_pvsload(), the_tr12env_pvsl00d(), the two flags, then
      initialize(validator, pruner) which starts the connection loop.

Primer anchors: §3 (front-end API), §4 (one-shot-state solved via eviction),
§5 (0-based internal coords via accessors), §6 (errck/codes/dedup), §7 (s2typ
pretty-print), §8 (def loc), §9 (traversal), §10.5 (compiler-linking build).
*)
(* ****** ****** *)
//
#include "./../HATS/libxatsopt_resident.hats"
//
#include "srcgen2/HATS/xatsopt_sats.hats"
#include "srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../SATS/xats_lsp_resident.sats"
//
// WS-6: topmap_strmize (enumerate the pervasive name topmaps) is not in the
// bundled headers; staload it directly (same SATS the compiler's *_myenv0 use).
#staload "srcgen2/SATS/xsymmap.sats"
//
// M6a: the Python-surface front-end's TYPECHECK-ONLY LSP entry (lex/parse/elab/
// lower -> trans2a/trsym2b/t2read0 -> trans23 -> tread3a). pyfront_d3parsed_of_
// fname/fpath return a d3parsed the SHARED harvest_d3parsed reads identically to
// the stock .sats/.dats path. (The relative path mirrors libxatsopt_resident.hats:
// DATS -> resident -> server -> language-server -> ATS-Xanadu -> frontend.)
#staload "./../../../../frontend/SATS/pyfront_lsp.sats"
//
// PORTABLE LSP MODULES (Stage 4b+ rearchitect): the JSON tree, path<->uri codec,
// byte->UTF-16 column conversion, and item dedup/sort, all in backend-agnostic
// ATS3.  Each is emitted as its own cz fragment (see chez-build-resident.sh) and
// linked here by deterministic .sats-stamp mangled names (validated: jget_1066 /
// json_serialize_960 match between fragment and this driver-context emit).
#staload "./../SATS/xats_lsp_json.sats"
#staload "./../SATS/xats_lsp_uri.sats"
#staload "./../SATS/xats_lsp_u16.sats"
#staload "./../SATS/xats_lsp_dedup.sats"
// Stage 3+4: the per-uri index — accumulators + dedup + request builders, in ATS.
// The harvest sinks (diag/hover/def/token/inlay_push) forward here; the glue drives
// commit/query/diagnostics by uri (the idx_* API, passed to initialize).
#staload "./../SATS/xats_lsp_index.sats"
// Stage 5: the project staload graph (fwd/rev path edges + the #staload scanner +
// the reverse closure for the watched-files cascade), in ATS.
#staload "./../SATS/xats_lsp_proj.sats"
//
// Stage 6a: the document store (editor text buffers + incremental range edits +
// completion-context extraction), in ATS.  Passed to the glue as 7 closures.
#staload "./../SATS/xats_lsp_doc.sats"
//
// Stage 6b: the per-check conversion layer (friendly/def_in_current/path2uri) is
// in ATS (called ATS->ATS by the index); the validate driver sets its per-check
// state via the conv_set_cur closure.
#staload "./../SATS/xats_lsp_conv.sats"
//
// Stage 4b+: the mutable-cell FFI floor (#include, NOT #staload, so cell_make/
// cell_get/cell_set emit by plain name) + unsafe casts for implementing the
// abstract depset/depgraph (<= p0tr) over cells.
#include "./../HATS/xats_lsp_ref.hats"
#staload UN = "srcgen1/prelude/SATS/unsafex.sats"
//
(* ****** ****** *)
(* ====================================================================== *)
(*                    FFI bindings (impl in the .cats)                     *)
(* ====================================================================== *)
//
#implfun url_to_path(uri) =
  vscode_url_to_path(uri)
  where { #extern fun vscode_url_to_path(uri: url) : string = $extnam() }
//
// (Stage 6 cleanup: severity/position/range/diagnostic makers removed — diagnostics
// are built as jval in xats_lsp_index and serialized to the wire directly.)
//
#implfun regex_make(pat) =
  vscode_regex_make(pat)
  where { #extern fun vscode_regex_make(pat: string): regex = $extnam() }
//
#implfun regex_test(re, input) =
  vscode_regex_test(re, input)
  where { #extern fun
    vscode_regex_test(re: regex, input: string): bool = $extnam() }
//
(* ---- dependency set / graph (ported to ATS; reps = cells over assoc-lists) ---- *)
//
// depset  = a set of files keyed by STAMP, value = the sym_t (so pop hands back a
//           real sym handle).  rep: a cell holding list(@(stamp, sym_t)).
// depgraph= STAMP -> (the file's own sym, the depset of its dependents).
//           rep: a cell holding list(@(stamp, @(sym_t, depset))).
// Both abstract types are <= p0tr; a cell is boxed, so the $UN casts are
// representation-safe.  Keys compared with stamp_cmp (=0 means equal).  This
// mirrors the former JS_depset_*/JS_depgraph_* glue exactly.
//
#typedef deplist = list(@(stamp, sym_t))
#typedef grafent = @(sym_t, depset)
#typedef graflist = list(@(stamp, grafent))
//
fun ds_cell(dp: depset): lspcell(deplist) = $UN.cast10{lspcell(deplist)}(dp)
fun dg_cell(dp: depgraph): lspcell(graflist) = $UN.cast10{lspcell(graflist)}(dp)
//
fun ds_has_st(xs: deplist, st: stamp): bool =
( case+ xs of
  | list_nil() => false
  | list_cons(p, r) => (if stamp_cmp(p.0, st) = 0 then true else ds_has_st(r, st)) )
//
fun dg_has_st(xs: graflist, st: stamp): bool =
( case+ xs of
  | list_nil() => false
  | list_cons(p, r) => (if stamp_cmp(p.0, st) = 0 then true else dg_has_st(r, st)) )
//
// returns the entry's depset; the nil branch is unreachable (callers guard).
fun dg_get_ds(xs: graflist, st: stamp): depset =
( case+ xs of
  | list_nil() => depset_make()
  | list_cons(p, r) => (if stamp_cmp(p.0, st) = 0 then (p.1).1 else dg_get_ds(r, st)) )
//
fun dg_del_st(xs: graflist, st: stamp): graflist =
( case+ xs of
  | list_nil() => list_nil()
  | list_cons(p, r) => (if stamp_cmp(p.0, st) = 0 then r else list_cons(p, dg_del_st(r, st))) )
//
#implfun depset_make() =
  $UN.cast10{depset}(cell_make{deplist}(list_nil()))
//
#implfun depset_add(dp, key) = let
  val c = ds_cell(dp)
  val st = key.stmp()
  val xs = cell_get{deplist}(c)
in
  if ds_has_st(xs, st) then () else cell_set{deplist}(c, list_cons(@(st, key), xs))
end
//
#implfun depset_pop(dp) = let
  val c = ds_cell(dp)
  val xs = cell_get{deplist}(c)
in
  case+ xs of
  | list_cons(p, r) => let val () = cell_set{deplist}(c, r) in p.1 end
  | list_nil() => the_symbl_nil
end
//
#implfun depset_is_empty(dp) =
( case+ cell_get{deplist}(ds_cell(dp)) of list_nil() => true | _ => false )
//
#implfun depset_has(dp, key) =
  ds_has_st(cell_get{deplist}(ds_cell(dp)), key.stmp())
//
// union = a NEW depset holding every member of both (deduped by stamp).
fun du_addall(out: depset, xs: deplist): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(p, r) => let val () = depset_add(out, p.1) in du_addall(out, r) end )
//
#implfun depset_union(dp1, dp2) = let
  val out = depset_make()
  val () = du_addall(out, cell_get{deplist}(ds_cell(dp1)))
  val () = du_addall(out, cell_get{deplist}(ds_cell(dp2)))
in out end
//
#implfun depgraph_add(dp, k, v) = let
  val c = dg_cell(dp)
  val st = k.stmp()
  val xs = cell_get{graflist}(c)
in
  if dg_has_st(xs, st) then depset_add(dg_get_ds(xs, st), v)
  else let
    val ds = depset_make()
    val () = depset_add(ds, v)
  in cell_set{graflist}(c, list_cons(@(st, @(k, ds)), xs)) end
end
//
#implfun depgraph_delete(dp, k) = let
  val c = dg_cell(dp)
in cell_set{graflist}(c, dg_del_st(cell_get{graflist}(c), k.stmp())) end
//
#implfun depgraph_has(dp, k) =
  dg_has_st(cell_get{graflist}(dg_cell(dp)), k.stmp())
//
#implfun depgraph_find(dp, k) = let
  val xs = cell_get{graflist}(dg_cell(dp))
  val st = k.stmp()
in if dg_has_st(xs, st) then dg_get_ds(xs, st) else depset_make() end
//
// Stage 6: the dependents + forward staload graphs are now driver-owned cells
// (reset together on a prelude reload).  Defined here (before fwd_graph) so the
// #implfun can reference cur_fwd (ATS top-level funs don't forward-reference).
fun depgraph_make((*void*)): depgraph = $UN.cast10{depgraph}(cell_make{graflist}(list_nil()))
val the_deps_c: lspcell(depgraph) = cell_make{depgraph}(depgraph_make())
val the_fwd_c: lspcell(depgraph) = cell_make{depgraph}(depgraph_make())
fun cur_deps((*void*)): depgraph = cell_get{depgraph}(the_deps_c)
fun cur_fwd((*void*)): depgraph = cell_get{depgraph}(the_fwd_c)
//
#implfun fwd_graph() = cur_fwd()
//
(* ---- THE cache-eviction primitive: delete env[key.stmp()] ---- *)
//
// topmap_insert (xsymmap_topmap.dats) stores each file under g0u2s(uint(
// key.stmp())) in a jshmap (a plain JS object). So evicting a file is exactly
// `delete env[ key.stmp() ]` — the JS-key coercion is identical on both sides.
//
#implfun env_reset{syn}(env, key) =
  JS_map_reset{syn}(env, key.stmp())
  where { #extern fun
    JS_map_reset{syn:tx}(env: topmap(syn), key: stamp): void = $extnam() }
//
// R2b: evict by raw stamp (JS hands us a bare uint; no sym_t to call .stmp() on).
// Deref the three live topmaps FRESH (xglobal_reset swaps them on a prelude
// reload) and delete env[stamp] from each. No-op when the stamp is absent.
// Reuses the SAME JS body (JS_map_reset) as env_reset — `delete env[stamp]`.
//
#implfun evict_stamp(stmp) = let
  #extern fun
  JS_map_reset{syn:tx}(env: topmap(syn), key: stamp): void = $extnam()
in
  JS_map_reset(the_d1parenv_pvstmap(), stmp);
  JS_map_reset(the_d2parenv_pvstmap(), stmp);
  JS_map_reset(the_d3parenv_pvstmap(), stmp)
end
//
(* ---- R2a: prelude snapshot + workspace-file signature map ---- *)
//
// snapshot the keys already present in a topmap (called per topmap right after
// the prelude loads): those stamps = the prelude / $XATSHOME files (immutable).
//
#implfun prelude_snapshot{syn}(env) =
  JS_prelude_snapshot{syn}(env)
  where { #extern fun
    JS_prelude_snapshot{syn:tx}(env: topmap(syn)): void = $extnam() }
//
#implfun prelude_freeze() =
  JS_prelude_freeze()
  where { #extern fun JS_prelude_freeze(): void = $extnam() }
//
// clear the snapshot Set before re-snapshotting on a prelude reload (the freshly
// reloaded prelude gets new file stamps; the old snapshot is stale).
//
#implfun prelude_snapshot_reset() =
  JS_prelude_snapshot_reset()
  where { #extern fun JS_prelude_snapshot_reset(): void = $extnam() }
//
// signature map keyed by the file's stamp (same key the topmaps use). path is
// the absolute on-disk filename (fnm1) used to stat it.
//
#implfun sig_record(key, path) =
  JS_sig_record(key.stmp(), path)
  where { #extern fun JS_sig_record(key: stamp, path: string): void = $extnam() }
//
#implfun sig_refresh(key) =
  JS_sig_refresh(key.stmp())
  where { #extern fun JS_sig_refresh(key: stamp): void = $extnam() }
//
#implfun sig_changed(key) =
  JS_sig_changed(key.stmp())
  where { #extern fun JS_sig_changed(key: stamp): bool = $extnam() }
//
(* ---- string-buffer FILR (capture a printed type; externs, like our checker) ---- *)
//
#extern fun LSP_strbuf_new((*0*)): FILR = $extnam()
#extern fun LSP_strbuf_get(fb: FILR): string = $extnam()
//
(* ---- harvest push primitives (per-uri index in the .cats) ---- *)
//
// Stage 3+4: these five sinks now accumulate into the ATS xats_lsp_index module
// (idx_*_push), which builds the jval rows + dedups + serves the requests.  The
// UTF-16/path/friendly conversion stays in the glue (called by the index module).
#implfun diag_push(l0, c0, l1, c1, code, message) =
  idx_diag_push(l0, c0, l1, c1, code, message)
//
#implfun hover_push(l0, c0, l1, c1, typ, kind) =
  idx_hover_push(l0, c0, l1, c1, typ, kind)
//
#implfun def_push
  ( ul0, uc0, ul1, uc1, defpath
  , dl0, dc0, dl1, dc1, entity, hastdef, tdpath
  , tl0, tc0, tl1, tc1) =
  idx_def_push
  ( ul0, uc0, ul1, uc1, defpath
  , dl0, dc0, dl1, dc1, entity, hastdef, tdpath
  , tl0, tc0, tl1, tc1)
//
#implfun token_push(l0, c0, l1, c1, ttype, tmods, defpath) =
  idx_token_push(l0, c0, l1, c1, ttype, tmods, defpath)
//
// WS-6: the prelude/global completion cache is filled by harvest_prelude_globals
// (below); its sinks now forward to the ATS xats_lsp_index cache (idx_prelude_*).
fun LSP_prelude_sym_reset((*void*)): void = idx_prelude_reset()
fun LSP_prelude_sym_push(name: string, kind: int, typ: string): void = idx_prelude_push(name, kind, typ)
fun LSP_prelude_sym_done((*void*)): void = lsp_log_prelude_index(idx_prelude_count())
  where { #extern fun lsp_log_prelude_index(n: int): void = $extnam() }
//
// Stage 5b: the symbol/scope/member harvest sinks now accumulate into the ATS
// xats_lsp_index module (idx_*), feeding documentSymbol / workspace / completion.
#implfun symbol_push(l0, c0, l1, c1, name, kind, container, typ) =
  idx_symbol_push(l0, c0, l1, c1, name, kind, container, typ)
//
#implfun inlay_push(line, col, label, kind) =
  idx_inlay_push(line, col, label, kind)
//
#implfun scope_push(l0, c0, l1, c1, name, typ) =
  idx_scope_push(l0, c0, l1, c1, name, typ)
//
#implfun member_push(l0, c0, l1, c1, name, typ) =
  idx_member_push(l0, c0, l1, c1, name, typ)
//
// Stage 6 cutover: `initialize`/`vscode_initialize` are gone — this driver owns the
// loop (serve_loop) + dispatch directly; see the server section below.
//
// lsp_addflag: add ONE compiler flag to the global flag table. The .cats calls
// this (via initialize's add_flag_t callback) for each flag in the workspace
// `.xats-lsp` file, BEFORE any file is checked, so `#if defq(...)` blocks resolve
// the way the project's real build does.
#implfun lsp_addflag(flag) = xatsopt_flag$pvsadd0(flag)
//
(* ****** ****** *)
(* ====================================================================== *)
(*       DEPENDENCY EXTRACTION  (ported from reference dependency30)       *)
(* ====================================================================== *)
//
// Walk a checked d3parsed; for every `staload`, record an edge "key0 depends
// on the staloaded file key1" by depgraph_add(dp, key1, key0). Editing key1
// later (didChange) then evicts key1 AND every key0 that staloaded it.
//
// R2a additions, in the SAME pass (no extra AST walk):
//   * FORWARD edge depgraph_add(fwd, key0, key1) — "key0 staloads key1" — so a
//     later check can walk key0's staload CLOSURE forward and stat each member.
//   * sig_record(key1, fnm1) — stamp the staloaded WORKSPACE file with its
//     {mtimeMs,size} signature (no-op for prelude files; they stay immutable).
//
// We descend into D3Cstaload's embedded sub-parse so transitive deps are
// captured: if A staloads B and B staloads C, the graph gets C->B and B->A,
// and evicting C unions in B then A. `depgraph_has` guards against re-walking
// an already-recorded file (cuts cycles + redundant work).
//
fun
dependency_d3ecl
(dp: depgraph, fwd: depgraph, d3cl: d3ecl, key0: sym_t): void =
  case+ d3cl.node() of
  | D3Clocal0(dcls1, dcls2) => let
      val () = dependency_d3eclist(dp, fwd, dcls1, key0)
      val () = dependency_d3eclist(dp, fwd, dcls2, key0)
    in end
  | D3Cinclude(_, _, _, _, dopt) => dependency_d3eclistopt(dp, fwd, dopt, key0)
  | D3Cstaload(_stadyn, _tok, _src, fopt, s3opt) =>
    ( case+ fopt of
      | optn_cons(fpath) => let
          val key1 = fpath.fnm2()
          // forward edge (key0 staloads key1) + workspace-file signature.
          val () = depgraph_add(fwd, key0, key1)
          val () = sig_record(key1, fpath.fnm1())
          val () =
            if depgraph_has(dp, key1) then ()
            else dependency_s3taloadopt(dp, fwd, s3opt, key1)
          val () = depgraph_add(dp, key1, key0)
        in end
      | optn_nil() => () )
  | _ => ()
//
and
dependency_d3eclist
(dp: depgraph, fwd: depgraph, dcls: d3eclist, key0: sym_t): void =
  case+ dcls of
  | list_nil() => ()
  | list_cons(d, ds) =>
    (dependency_d3ecl(dp, fwd, d, key0); dependency_d3eclist(dp, fwd, ds, key0))
//
and
dependency_d3eclistopt
(dp: depgraph, fwd: depgraph, dopt: d3eclistopt, key0: sym_t): void =
  case+ dopt of
  | optn_nil() => ()
  | optn_cons(dcls) => dependency_d3eclist(dp, fwd, dcls, key0)
//
and
dependency_s3taloadopt
(dp: depgraph, fwd: depgraph, s3opt: s3taloadopt, key0: sym_t): void =
  case+ s3opt of
  | S3TALOADdpar(_stadyn, dpar) =>
      dependency_d3eclistopt(dp, fwd, d3parsed_get_parsed(dpar), key0)
  | S3TALOADnone(_s2opt) => ()
//
(* ****** ****** *)
//
// is this resolved path a .dats? (vs .sats). Reference uses a regex; we reuse
// our existing suffix check shape for clarity but via the JS regex FFI to match
// the reference (the dispatch is identical).
//
fun
fpath_is_dats(fp: string): bool = let
  val re = regex_make(".*[.]dats$")
in regex_test(re, fp)
end
//
// M6a: Python-surface suffixes. `.*[.]dats$` requires a literal `.` before `dats`,
// so `foo.pdats` does NOT match fpath_is_dats (verified). We still test these
// BEFORE the .dats/.sats predicates in the validators for clarity + safety.
fun
fpath_is_pdats(fp: string): bool = let
  val re = regex_make(".*[.]pdats$")
in regex_test(re, fp)
end
//
fun
fpath_is_psats(fp: string): bool = let
  val re = regex_make(".*[.]psats$")
in regex_test(re, fp)
end
//
(* ****** ****** *)
//
// IN-MEMORY (unsaved-buffer) PARSE — the live-on-change path.
//
// d0parsed_from_atext (parsing.sats) parses in-memory text but stamps EVERY
// loctn with LCSRCnone0() (no source path), so harvested diagnostics/defs would
// not map back to the real uri, and relative #staloads would not resolve (the
// drpth stack is pushed from the source's lcsrc, see trans01.dats:84). We need
// the in-memory parse to behave exactly like a file parse for an identity given
// EXTERNALLY (the document's real on-disk path), without reading the stale disk
// file. So we replicate atext_tokenize / trans00_from_atext (lexing0.dats:131,
// parsing.dats:69) but lctnize with LCSRCsome1(path) instead of LCSRCnone0():
//   * every token's loctn carries LCSRCsome1(realPath) -> loc_fpath != "" ->
//     diagnostics/defs map back to the real uri;
//   * the d0parsed's source field is LCSRCsome1(realPath) -> d1parsed_of_trans01
//     pushes fpath_dpart(realPath) onto the drpth stack -> relative #staloads
//     resolve from the file's own directory (same as a real file parse).
// Then d3parsed_of_trans03(d0parsed_of_pread00(...)) runs the full front-end on
// the BUFFER (the warm compiler reuses the cached prelude + unchanged deps).
//
fun
atext_tokenize_named
(text: strn, path: strn): list_vt(token) = let
  val buf = lxbf1_make_strn(text)
  val lcs = LCSRCsome1(path)
in
  lexing_preping_all
  ( lexing_lctnize_all
    (lcs, lxbf1_lexing_tnodelst(buf)) )
end
//
fun
d0parsed_from_atext_named
(stadyn: sint, text: strn, path: strn): d0parsed = let
  val tks = atext_tokenize_named(text, path)
  val buf = tokbuf_make_llist(tks)
  var err: sint = 0
  val res = optn_cons(fp_d0eclsq1(stadyn, buf, err))
  val () = tokbuf_free(buf)
in
  // nerror=-1 (unknown), source=LCSRCsome1(path): identity is the REAL file.
  d0parsed_make_args(stadyn, (-1), LCSRCsome1(path), res)
end
//
(* ****** ****** *)
(* ====================================================================== *)
(*   HARVEST: s2typ pretty-printer + traversal                            *)
(*   The traversal lives in the SHARED HATS/xats_lsp_harvest.hats (single *)
(*   source of truth, also #include'd by the one-shot checker). Here we   *)
(*   only provide the leaf type renderer + the typrint helpers it needs,  *)
(*   then #include the shared harvest below.                              *)
(* ====================================================================== *)
//
(* ---- leaf head-name renderer (type-mismatch messages) ---- *)
//
fun
typ_to_strn
(t2p: s2typ): string = typ_aux(t2p, 4) where {
  fun
  typ_aux
  (t2p: s2typ, fuel: int): string =
  if (fuel <= 0) then typ_to_strn_dbg(t2p) else
  (
  case+ s2typ_get_node(t2p) of
  | T2Pcst(s2c) => symbl_get_name(s2cst_get_name(s2c))
  | T2Papps(head, _) => typ_aux(head, fuel-1)
  | T2Ptext(nm, _) => nm
  | T2Pxtv(xv) => typ_aux(x2t2p_get_styp(xv), fuel-1)
  | _ => typ_to_strn_dbg(t2p)
  )
}
//
and
typ_to_strn_dbg
(t2p: s2typ): string = let
  val fb = LSP_strbuf_new()
  val () = s2typ_fprint(t2p, fb)
in
  LSP_strbuf_get(fb)
end
//
(* ---- source-syntax s2typ pretty-printer (hover) ---- *)
//
// FAITHFUL printer lives in the SHARED include (single source of truth, reused
// by the one-shot checker and the round-trip harness). It needs three FFI/leaf
// helpers (int label / xtv stamp / sort -> string), implemented here + .cats.
//
#extern fun
TYPRINT_int2str(n: int): string = $extnam()
#extern fun
TYPRINT_stamp2str(s: stamp): string = $extnam()
//
// surface sort name via the strbuf + sort2_fprint (used by the Exact mode of
// the shared printer; on the hover path it never fires, but keep it sound).
fun
TYPRINT_sort2str
(srt: sort2): string = let
  val fb = LSP_strbuf_new()
  val () = sort2_fprint(srt, fb)
in
  LSP_strbuf_get(fb)
end
//
#include "./../../HATS/xats_lsp_typrint.hats"
//
(* ---- loctn helpers, source filter, classifiers, hover/def/token emission,
   and the d2/d3-family WALK all live in the SHARED harvest (single source of
   truth, also #include'd by server/DATS/xats_lsp_check.dats). It calls the
   four sinks diag_push/hover_push/def_push/token_push, implemented above via
   #implfun -> LSP_* (tokens active), and the typ_to_strn / typ_pretty / typr_funq
   helpers provided just above. ---- *)
//
#include "./../../HATS/xats_lsp_harvest.hats"
//
(* ****** ****** *)
(* ====================================================================== *)
(*            VALIDATOR + PRUNER + STARTUP  (the resident core)            *)
(* ====================================================================== *)
//
// evict_cascade: the shared eviction worklist (used by both the didChange pruner
// and the R2a precheck). Seeded with a depset of files to evict; for each popped
// file, env_reset it out of all three topmaps, pull its dependents from the
// (reverse) depgraph, union them in, and delete its graph entry — so editing a
// file evicts it AND every file that staloaded it. The prelude + untouched files
// stay cached -> the recheck is warm. Bounded: each file is processed once
// (depgraph_delete drops the visited entry, and depgraph_find of a leaf is empty).
//
fun
evict_cascade(dp: depgraph, seed: depset): void = let
    fun loop(work: depset): void =
      if ~depset_is_empty(work) then let
        val key = depset_pop(work)
        val () = env_reset(the_d1parenv_pvstmap(), key)
        val () = env_reset(the_d2parenv_pvstmap(), key)
        val () = env_reset(the_d3parenv_pvstmap(), key)
        val deps1 = depgraph_find(dp, key)
        val deps2 = depset_union(work, deps1)
        val () = depgraph_delete(dp, key)
      in loop(deps2)
      end
  in loop(seed)
  end
//
// R2a PRECHECK (the content-validated cache core). BEFORE each validate, walk the
// target's transitive-staload closure (forward graph) and re-stat each WORKSPACE
// member; any whose on-disk {mtimeMs,size} drifted (an out-of-band edit — another
// editor, git pull/checkout, codegen, formatter) is evicted via evict_cascade,
// which also cascades to its dependents. Prelude/$XATSHOME files are NEVER statted
// here: sig_changed returns false for them because sig_record never admitted them
// to the signature map (gated by the $XATSHOME path-prefix exclusion). Cost:
// O(|closure|) statSync (~µs each); the closure is small (the target's deps), so
// this is negligible against a warm check. (R2 Layer A.)
//
fun
precheck(dp: depgraph, fwd: depgraph, key0: sym_t): void = let
    val seen  = depset_make()   // forward-closure files already visited
    val dirty = depset_make()   // changed files to evict (+ cascade)
    // BFS the forward closure: key0 (the target itself — d3parsed_of_fil would
    // otherwise serve key0's STALE cached parse if it was edited out-of-band, so
    // the headline single-file case needs key0 statted too) plus its transitive
    // staloads.
    fun walk(work: depset): void =
      if ~depset_is_empty(work) then let
        val k = depset_pop(work)
      in
        if depset_has(seen, k) then walk(work)
        else let
          val () = depset_add(seen, k)
          // changed on disk? (no-op/false for prelude + unknown files)
          val () = if sig_changed(k) then depset_add(dirty, k)
          // descend into k's own forward staloads (transitive closure).
          val nbrs = depgraph_find(fwd, k)
          val work1 = depset_union(work, nbrs)
        in walk(work1) end
      end
    val work0 = depset_make()
    val () = depset_add(work0, key0)
  in
    let val () = walk(work0) in
      if ~depset_is_empty(dirty) then evict_cascade(dp, dirty)
    end
  end
//
// text_validator: invoked on didOpen/didSave. Resolve the file path from the
// uri, PRECHECK its staload closure for out-of-band drift (R2a), run the
// front-end IN-PROCESS (d3parsed_of_fil{dats,sats}; the warm compiler reuses the
// cached prelude + unchanged deps), record dependency edges (both directions)
// from the checked parse + stamp each workspace dep's signature, and harvest
// diagnostics + hover/def index from the SAME d3parsed. No subprocess, no temp
// JSON.
//
// harvest_with_deps: the resident's post-check work, factored out so the disk
// path (text_validator) and the in-memory path (live_validator) run an identical
// dependency-extraction + signature-stamping + harvest from a checked d3parsed.
// The dependency/signature extraction is resident-specific; the source-filtered
// AST harvest itself is the SHARED harvest_d3parsed (HATS/xats_lsp_harvest.hats),
// which we delegate to — so the resident and the one-shot checker walk + filter
// IDENTICALLY (the include-leak source filter can never drift between them again).
//
(* ====================================================================== *)
(*   STALOAD-AWARE COMPLETION                                              *)
(*   Index the names a file's #staload/#include closure brings into scope  *)
(*   (the staloaded API — e.g. xatsopt_flag$pvsadd0), so completion offers *)
(*   them, not just the file's own decls + the pervasive prelude. Each     *)
(*   staloaded file is descended ONCE per session (deduped by its STAMP);  *)
(*   the index persists in the .cats and is cleared on a prelude reload.   *)
(*   The .cats's LSP_staload_seen returns true for ALL stamps when the      *)
(*   feature is off (ATS3_LSP_STALOAD_COMPLETE=0) -> no descent, no cost.   *)
(* ====================================================================== *)
//
// Stage 5b: the staloaded-API index now lives in the ATS xats_lsp_index module
// (idx_staload_*); the per-session file dedup (by stamp) + the kill-switch are there.
fun LSP_staload_seen(s: sint): bool = idx_staload_seen(s)
fun LSP_staload_mark(s: sint): void = idx_staload_mark(s)
fun LSP_staload_sym_push(name: string, kind: int, typ: string): void = idx_staload_push(name, kind, typ)
//
fun
stld_emit_dcons(cs: d2conlst, kind: int): void =
( case+ cs of
  | list_nil() => ()
  | list_cons(c, rest) =>
    ( LSP_staload_sym_push
        (symbl_get_name(d2con_get_name(c)), kind, typ_pretty(d2con_get_styp(c)))
    ; stld_emit_dcons(rest, kind) ) )
//
fun
stld_emit_scst1(s2c: s2cst, kind: int): void =
  LSP_staload_sym_push
    (symbl_get_name(s2cst_get_name(s2c)), kind, typr_sort2name(s2cst_get_sort(s2c)))
fun
stld_emit_scsts(cs: s2cstlst, kind: int): void =
( case+ cs of
  | list_nil() => ()
  | list_cons(c, rest) => (stld_emit_scst1(c, kind); stld_emit_scsts(rest, kind)) )
//
// a SATS `fun`/`val` declaration group (D2Cdynconst) -> each d2cst's name.
fun
stld_emit_d2cstdcls(cs: d2cstdclist): void =
( case+ cs of
  | list_nil() => ()
  | list_cons(c, rest) => let
      val dc = d2cstdcl_get_dpid(c)
    in
      LSP_staload_sym_push(symbl_get_name(d2cst_get_name(dc)),
        (if typr_funq(d2cst_get_styp(dc)) then 12(*Function*) else 14(*Constant*)),
        typ_pretty(d2cst_get_styp(dc)));
      stld_emit_d2cstdcls(rest)
    end )
//
// walk a STALOADED file's (d2 interface) decls -> emit each name.
fun
stld_index_d2ecl(dcl: d2ecl): void =
( case+ dcl.node() of
  | D2Cerrck(_, d1) => stld_index_d2ecl(d1)
  | D2Cstatic(_, d1) => stld_index_d2ecl(d1)
  | D2Cextern(_, d1) => stld_index_d2ecl(d1)
  | D2Clocal0(da, db) => (stld_index_d2eclist(da); stld_index_d2eclist(db))
  | D2Cdynconst(_, _, dcdcls) => stld_emit_d2cstdcls(dcdcls)
  | D2Cdatatype(_, s2cs) => stld_emit_scsts(s2cs, 10(*Enum*))
  | D2Csexpdef(s2c, _) => stld_emit_scst1(s2c, 11(*Interface*))
  | D2Cstacst0(s2c, _) => stld_emit_scst1(s2c, 26(*TypeParam*))
  | D2Cabstype(s2c, _) => stld_emit_scst1(s2c, 5(*Class*))
  | D2Cexcptcon(_, d2cs) => stld_emit_dcons(d2cs, 22(*EnumMember*))
  | D2Cnone2(d2cl) => stld_index_d2ecl(d2cl)
  | _ => () )
and
stld_index_d2eclist(xs: d2eclist): void =
( case+ xs of list_nil() => () | list_cons(x, xs) => (stld_index_d2ecl(x); stld_index_d2eclist(xs)) )
and
stld_index_d2eclistopt(xo: d2eclistopt): void =
( case+ xo of optn_nil() => () | optn_cons(xs) => stld_index_d2eclist(xs) )
//
// THE STALOADED API = every file the compiler has PARSED+CHECKED is cached in
// the_d3parenv (topmap stamp -> d3parsed).  A file's #staload sub-parses come back
// S3TALOADnone (cached, not embedded), so we enumerate the cache directly (like
// the prelude/global index enumerates the_dexpenv) and walk each cached file's
// decls.  Deduped by the topmap STAMP key (a sint) so each file is walked once;
// the cache grows monotonically (prelude + compiler + checked user files), so
// after the first compiler-linking check the whole API is indexed and later
// checks add only newly-cached files.  This over-includes slightly (names from
// cached files the current file doesn't staload) — harmless for completion.
//
#typedef d2kxs_t = @(sint, list(d2parsed))
//
fun
stld_index_dpars(xs: list(d2parsed)): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(dp, rest) =>
    (stld_index_d2eclistopt(d2parsed_get_parsed(dp)); stld_index_dpars(rest)) )
//
fun
stld_strm(kxss: strm_vt(d2kxs_t)): void =
( case+ !kxss of
  | ~strmcon_vt_nil() => ()
  | ~strmcon_vt_cons(kxs1, rest) =>
    ( if LSP_staload_seen(kxs1.0) then ()
      else (LSP_staload_mark(kxs1.0); stld_index_dpars(kxs1.1))
    ; stld_strm(rest) ) )
//
// enumerate the d2 cache (the staloaded SATS interfaces — fun/val/type decls);
// the d3 cache (the_d3parenv) holds only checked .dats (already document/project
// symbols), so the SATS API lives in d2.
fun
harvest_staload_syms((*void*)): void =
  stld_strm(topmap_strmize(the_d2parenv_pvstmap()))
//
(* ****** ****** *)
//
fun
harvest_with_deps
(dp: depgraph, fwd: depgraph, key: sym_t, path: strn, dpar: d3parsed): void = let
    val parsed = d3parsed_get_parsed(dpar)
    // record "this file depends on each staloaded file" (reverse edge, for the
    // pruner) + "this file staloads each" (forward edge, for the precheck) + each
    // workspace dep's {mtimeMs,size} signature. One pass, both graphs.
    val () = dependency_d3eclistopt(dp, fwd, parsed, key)
    // also stamp THIS file's own signature so a later check of a dependent can
    // detect an out-of-band edit to it (the dependency pass only stamps deps).
    val () = sig_record(key, path)
    // SHARED harvest: set the top-path source filter from d3parsed_get_source,
    // walk (diagnostics + hovers + defs + semantic tokens), reset the filter.
    val () = harvest_d3parsed(dpar)
    // staload-aware completion: index the staloaded API from the global d3 cache
    // (deduped per cached-file stamp; cheap after the first compiler-linking check).
    val () = harvest_staload_syms()
  in (*nothing*) end
//
#implfun text_validator(dp, ds, uri) = let
    val path = url_to_path(uri)
    val key = path.fpath().fnm2()
    val fwd = fwd_graph()
    // R2a: catch on-disk drift in this file's staload closure BEFORE serving from
    // cache; evict any stale dep (+ cascade) so the check below re-translates it.
    val () = precheck(dp, fwd, key)
    val dpar =
      // M6: Python-surface dispatch — .pdats/.psats run the pyfront typecheck
      // pipeline (which reads the file itself); else the stock .dats/.sats path.
      if fpath_is_pdats(path)
      then pyfront_d3parsed_of_fname(1(*dyn*), path)
      else if fpath_is_psats(path)
      then pyfront_d3parsed_of_fname(0(*sta*), path)
      else if fpath_is_dats(path)
      then d3parsed_of_fildats(path)
      else d3parsed_of_filsats(path)
    val () = harvest_with_deps(dp, fwd, key, path, dpar)
  in
    // `ds` is unused as a sink here (the .cats holds the per-uri index that the
    // diag_push calls populated); kept in the signature for parity with the
    // reference's validator shape. Touch it to avoid an unused warning.
    let val _ = ds in () end
  end
//
// live_validator: invoked on didChange (debounced ~300 ms in the .cats). Checks
// the UNSAVED in-memory buffer `text` for `uri`, NOT the stale disk file. We
// parse `text` in-memory with the source identity = the document's REAL path
// (d0parsed_from_atext_named) so diagnostics/loctns map to the real uri and
// relative #staloads resolve from the file's directory, then run the full
// front-end on the buffer (d3parsed_of_trans03) and harvest exactly as the disk
// path does. The didChange pruner has already evicted this file (+ dependents),
// so the cache won't serve a stale parse of THIS file; d3parsed_of_trans03 takes
// the freshly-parsed d0parsed directly (the top buffer is never cache-served),
// while its staloaded deps still resolve from the cache/disk (the warm path).
//
#implfun live_validator(dp, ds, uri, text) = let
    val path = url_to_path(uri)
    val key = path.fpath().fnm2()
    val fwd = fwd_graph()
    // R2a: validate the closure's on-disk drift (the buffer's DEPS still come from
    // disk; the target buffer itself is the in-memory `text`, never disk).
    val () = precheck(dp, fwd, key)
    val dpar =
      // M6: Python-surface dispatch — .pdats/.psats run the pyfront typecheck
      // pipeline DIRECTLY on the in-memory buffer `text` (source identity = the
      // document's REAL path, so spans/diagnostics map back to the uri); else the
      // stock in-memory parse + trans03 path.
      if fpath_is_pdats(path)
      then pyfront_d3parsed_of_fpath(1(*dyn*), LCSRCsome1(path), text)
      else if fpath_is_psats(path)
      then pyfront_d3parsed_of_fpath(0(*sta*), LCSRCsome1(path), text)
      else let
        val stadyn = if fpath_is_dats(path) then 1(*dyn*) else 0(*sta*)
        val dpar0 = d0parsed_from_atext_named(stadyn, text, path)
      in d3parsed_of_trans03(d0parsed_of_pread00(dpar0)) end
    val () = harvest_with_deps(dp, fwd, key, path, dpar)
  in
    let val _ = ds in () end
  end
//
// cache_pruner: invoked on didChange. Evict the edited file AND its transitive
// dependents from the_d{1,2,3}parenv so the next validate re-translates them.
//
#implfun cache_pruner(dp, uri) = let
    val path = url_to_path(uri)
    val key = path.fpath().fnm2()
    val deps0 = depset_make()
    val () = depset_add(deps0, key)
  in evict_cascade(dp, deps0)
  end
//
(* ****** ****** *)
//
// prelude_pvsload: the EXACT prelude-load + flag sequence the resident server
// runs at startup. Factored out so reload_prelude (below) replays it BYTE-FOR-
// BYTE after an xglobal_reset() — i.e. the fresh process and the in-process
// reload load the prelude identically. the_ntime gates each loader: at startup
// the gate is 0 -> loads; xglobal_reset() re-arms it to 0 -> loads AGAIN.
//
// WS-6: PRELUDE/GLOBAL symbol index, sourced from the LOADED pervasive NAME envs.
// f0_pvsload (xglobal.dats) parses each prelude file ONCE, merges the declared
// names into the_dexpenv/the_sexpenv (pvsmrgw -> their topmaps), then discards the
// AST. So the names ARE retained — in the_dexpenv_pvstmap() : topmap(d2itm) and
// the_sexpenv_pvstmap() : topmap(s2itm) — which we enumerate via topmap_strmize.
// REUSES the parse the loader already did (no second parse), NO regex, NO compiler
// change. the_dexpenv holds only pervasive names (user decls go to per-file
// scopes), so it is prelude-only — no pollution. Runs at startup AND on each
// reload (both call prelude_pvsload).
//
#typedef dkxs_t = @(sint, list(d2itm))
#typedef skxs_t = @(sint, list(s2itm))
//
fun
prelude_push_d2itm(itm: d2itm): void =
(
case+ itm of
| D2ITMcst(cs) =>
  ( case+ cs of
    | list_cons(c, _) =>
      LSP_prelude_sym_push(symbl_get_name(d2cst_get_name(c)),
        (if typr_funq(d2cst_get_styp(c)) then 12(*Function*) else 14(*Constant*)),
        typ_pretty(d2cst_get_styp(c)))
    | list_nil() => () )
| D2ITMcon(cs) =>
  ( case+ cs of
    | list_cons(c, _) =>
      LSP_prelude_sym_push(symbl_get_name(d2con_get_name(c)), 22(*EnumMember*),
        typ_pretty(d2con_get_styp(c)))
    | list_nil() => () )
| D2ITMvar(v) =>
  LSP_prelude_sym_push(symbl_get_name(d2var_get_name(v)), 13(*Variable*),
    typ_pretty(d2var_get_styp(v)))
| D2ITMsym(sym, _) =>
  LSP_prelude_sym_push(symbl_get_name(sym), 12(*Function: overload set*), "")
)
//
fun
prelude_push_s2itm(itm: s2itm): void =
(
case+ itm of
| S2ITMcst(cs) =>
  ( case+ cs of
    | list_cons(c, _) =>
      LSP_prelude_sym_push(symbl_get_name(s2cst_get_name(c)), 11(*Interface*),
        typr_sort2name(s2cst_get_sort(c)))   // the type's SORT (e.g. `(t@ype) -> type`)
    | list_nil() => () )
| S2ITMvar(_) => ()
| S2ITMenv(_) => ()
)
//
fun
prelude_push_d2itms(xs: list(d2itm)): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (prelude_push_d2itm(x); prelude_push_d2itms(xs)) )
fun
prelude_push_s2itms(xs: list(s2itm)): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (prelude_push_s2itm(x); prelude_push_s2itms(xs)) )
//
fun
prelude_strm_dexp(kxss: strm_vt(dkxs_t)): void =
( case+ !kxss of
  | ~strmcon_vt_nil() => ()
  | ~strmcon_vt_cons(kxs1, kxss) =>
    (prelude_push_d2itms(kxs1.1); prelude_strm_dexp(kxss)) )
fun
prelude_strm_sexp(kxss: strm_vt(skxs_t)): void =
( case+ !kxss of
  | ~strmcon_vt_nil() => ()
  | ~strmcon_vt_cons(kxs1, kxss) =>
    (prelude_push_s2itms(kxs1.1); prelude_strm_sexp(kxss)) )
//
fun
harvest_prelude_globals((*void*)): void = let
  val () = LSP_prelude_sym_reset()
  val () = prelude_strm_dexp(topmap_strmize(the_dexpenv_pvstmap()))
  val () = prelude_strm_sexp(topmap_strmize(the_sexpenv_pvstmap()))
in LSP_prelude_sym_done()
end
//
fun
prelude_pvsload((*void*)): void = let
  val _ = the_fxtyenv_pvsload()
  val _ = the_tr12env_pvsl00d()
  val () = xatsopt_flag$pvsadd0("--_XATSOPT_")
  val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATSOPT_")
  // WS-6: (re)build the prelude/global completion index from the loaded env.
  val () = harvest_prelude_globals()
in (*nothing*) end
//
// prelude_take_snapshot: record the prelude / $XATSHOME file stamps now cached in
// the three topmaps (the R2a secondary guard). Shared by startup and reload: on a
// reload the Set is cleared first because the freshly reloaded prelude has new
// stamps. Re-freezes after.
//
fun
prelude_take_snapshot((*void*)): void = let
  val () = prelude_snapshot_reset()
  val () = prelude_snapshot(the_d1parenv_pvstmap())
  val () = prelude_snapshot(the_d2parenv_pvstmap())
  val () = prelude_snapshot(the_d3parenv_pvstmap())
in prelude_freeze()
end
//
// reload_prelude: the in-process prelude reload (replaces the restart of the
// resident model's prelude edge-case). xglobal_reset() (compiler API, in scope
// via xglobal.sats / libxatsopt.hats — the server already calls the_*_pvsl* from
// the same header) clears the accumulating global envs (the_fxtyenv / the_sexpenv
// / the_dexpenv / the_d2cstmap), the per-file caches (the_d{1,2,3}parenv) and
// re-arms the the_ntime prelude-load gates. We then replay the SAME prelude-load
// + flag sequence as startup so the EDITED prelude is reloaded fresh from disk.
// (The loaders read from DISK, hence the .cats triggers this on didSave — the
// change must be saved before reload_prelude runs.)
//
#implfun reload_prelude((*void*)) = let
  val () = xglobal_reset()
  // the staloaded-API cache is stamp-keyed -> stale after the reset (new stamps).
  val () = idx_staload_reset()
  val () = prelude_pvsload()
in prelude_take_snapshot()
end
//
(* ****** ****** *)
(* ====================================================================== *)
(* Stage 6: the LSP server — message loop + dispatch + validation, IN ATS. *)
(* The Scheme glue is now just the floor (transport + filesystem + the      *)
(* compiler-coupled stamp/topmap leaves + the FS workspace scan); this       *)
(* driver owns the loop, every handler, runValidation and dispatch, calling  *)
(* the ATS modules (json/conv/doc/index/proj) + its own validators directly. *)
(* ====================================================================== *)
//
// ---- floor leaves (implemented in SCM/xats_lsp_resident.scm) ----
#extern fun int2str(n: sint): string = $extnam()
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
#extern fun str_slice(s: string, a: sint, b: sint): string = $extnam()
#extern fun lsp_msg_read(timeout_ms: sint): @(sint, string) = $extnam()
#extern fun lsp_msg_write(s: string): void = $extnam()
#extern fun lsp_log(s: string): void = $extnam()
#extern fun lsp_now_ms((*void*)): sint = $extnam()
#extern fun lsp_exit((*void*)): void = $extnam()
#extern fun lsp_guard(thunk: () -> void): sint = $extnam()      // run thunk; 1 if it threw, else 0
#extern fun lsp_getenv(name: string): string = $extnam()
#extern fun lsp_fs_read(path: string): string = $extnam()
#extern fun lsp_fs_exists(path: string): bool = $extnam()
#extern fun lsp_boot(pidx: (string, string) -> string, pfc: () -> int, prc: () -> int, pip: (string) -> bool): void = $extnam()
#extern fun JS_path2stamp(path: string): @(sint, stamp) = $extnam()  // (found 0/1, stamp)
#extern fun JS_sig_forget(npath: string, isDelete: sint): void = $extnam()
#extern fun JS_sig_reset((*void*)): void = $extnam()
#extern fun JS_stat_count((*void*)): sint = $extnam()
#extern fun JS_proj_scan(rootsJoined: string): void = $extnam()
#extern fun JS_proj_worklist((*void*)): string = $extnam()
//
(* ---- the open-set (the depgraph cells live up near fwd_graph) ---- *)
//
val the_openset: lspcell(list(string)) = cell_make{list(string)}(list_nil())
fun oset_has(uri: string): bool = let
  fun go(xs: list(string)): bool =
    (case+ xs of list_nil() => false | list_cons(x, r) => (if strn_eq(x, uri) then true else go(r)))
in go(cell_get{list(string)}(the_openset)) end
fun oset_add(uri: string): void =
  (if oset_has(uri) then () else cell_set{list(string)}(the_openset, list_cons(uri, cell_get{list(string)}(the_openset))))
fun oset_del(uri: string): void = let
  fun go(xs: list(string)): list(string) =
    (case+ xs of list_nil() => list_nil() | list_cons(x, r) => (if strn_eq(x, uri) then go(r) else list_cons(x, go(r))))
in cell_set{list(string)}(the_openset, go(cell_get{list(string)}(the_openset))) end
fun oset_clear((*void*)): void = cell_set{list(string)}(the_openset, list_nil())
//
val the_has_refresh: lspcell(sint) = cell_make{sint}(0)
val the_pending_roots: lspcell(string) = cell_make{string}("")
val the_reqid: lspcell(sint) = cell_make{sint}(100000)
//
(* ---- small string helpers (parse ints, split on newline) ---- *)
//
fun str2int(s: string): sint = let
  val n = str_len(s)
  fun loop(i: sint, acc: sint): sint =
    if (i >= n) then acc
    else let val c = str_char_code(s, i) in
      (if (if (c >= 48) then (c <= 57) else false) then loop(i+1, acc*10 + (c-48)) else acc) end
in loop(0, 0) end
//
fun split_nl(s: string): list(string) = let
  val n = str_len(s)
  fun go(i: sint, start: sint, acc: list(string)): list(string) =
    if (i >= n) then list_reverse(list_cons(str_slice(s, start, n), acc))
    else if (str_char_code(s, i) = 10) then go(i+1, i+1, list_cons(str_slice(s, start, i), acc))
    else go(i+1, start, acc)
in go(0, 0, list_nil()) end
// split + drop empties (for newline-joined path/uri sets).
fun split_nl_ne(s: string): list(string) = let
  fun keep(xs: list(string)): list(string) =
    (case+ xs of list_nil() => list_nil()
     | list_cons(x, r) => (if strn_eq(x, "") then keep(r) else list_cons(x, keep(r))))
in keep(split_nl(s)) end
fun list_len(xs: list(string)): sint = (case+ xs of list_nil() => 0 | list_cons(_, r) => 1 + list_len(r))
fun list_mem(xs: list(string), y: string): bool =
  (case+ xs of list_nil() => false | list_cons(x, r) => (if strn_eq(x, y) then true else list_mem(r, y)))
fun nth_s(xs: list(string), i: sint): string =
  (case+ xs of list_nil() => "" | list_cons(x, r) => (if (i <= 0) then x else nth_s(r, i-1)))
//
(* ---- the config knobs (read once at load) ---- *)
val the_debounce_ms: sint =
  let val v = lsp_getenv("ATS3_LSP_DEBOUNCE_MS") in (if strn_eq(v, "") then 150 else str2int(v)) end
val the_bg_cap: sint =
  let val v = lsp_getenv("ATS3_BG_INDEX_CAP") in (if strn_eq(v, "") then 400 else str2int(v)) end
//
(* ---- JSON-RPC framing helpers (results from idx_* are already serialized) ---- *)
//
fun jpr(k: string, v: jval): @(string, jval) = @(k, v)
fun respond(idv: jval, result: jval): void =
  lsp_msg_write(json_serialize(JVobj(
    list_cons(jpr("jsonrpc", JVstr "2.0"),
    list_cons(jpr("id", idv),
    list_cons(jpr("result", result), list_nil()))))))
fun respond_raw(idv: jval, rs: string): void =
  lsp_msg_write(strn_append("{\"jsonrpc\":\"2.0\",\"id\":",
    strn_append(json_serialize(idv),
    strn_append(",\"result\":", strn_append(rs, "}")))))
fun publish_raw(uri: string, diagsStr: string): void =
  lsp_msg_write(strn_append("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":",
    strn_append(json_serialize(JVstr uri),
    strn_append(",\"diagnostics\":", strn_append(diagsStr, "}}")))))
fun send_sem_refresh((*void*)): void = let
  val id = cell_get{sint}(the_reqid) + 1
  val () = cell_set{sint}(the_reqid, id)
in
  lsp_msg_write(strn_append("{\"jsonrpc\":\"2.0\",\"id\":",
    strn_append(int2str(id), ",\"method\":\"workspace/semanticTokens/refresh\",\"params\":null}")))
end
//
fun mkpos00(l: sint, c: sint): jval =
  JVobj(list_cons(jpr("line", JVint l), list_cons(jpr("character", JVint c), list_nil())))
fun abort_diag_str((*void*)): string = let
  val rng = JVobj(list_cons(jpr("start", mkpos00(0, 0)), list_cons(jpr("end", mkpos00(0, 1)), list_nil{jpair}())))
  val df = list_cons(jpr("source", JVstr "ats3"), list_nil{jpair}())
  val df = list_cons(jpr("message", JVstr "ats3: could not analyze this file (the compiler aborted). This usually means the file staloads the ATS3 compiler itself; ordinary ATS3 files are unaffected."), df)
  val df = list_cons(jpr("range", rng), df)
  val df = list_cons(jpr("severity", JVint 2), df)
in json_serialize(JVarr(list_cons(JVobj(df), list_nil{jval}()))) end
//
fun metric_line
  (uri: string, mode: string, ms: sint, nd: sint, nh: sint, ndf: sint, nt: sint, nstat: sint): string = let
  val s = strn_append("[xats-lsp-metric] check uri=", uri)
  val s = strn_append(s, " mode=") val s = strn_append(s, mode)
  val s = strn_append(s, " ms=") val s = strn_append(s, int2str(ms))
  val s = strn_append(s, " diags=") val s = strn_append(s, int2str(nd))
  val s = strn_append(s, " hovers=") val s = strn_append(s, int2str(nh))
  val s = strn_append(s, " defs=") val s = strn_append(s, int2str(ndf))
  val s = strn_append(s, " tokens=") val s = strn_append(s, int2str(nt))
  val s = strn_append(s, " stats=") val s = strn_append(s, int2str(nstat))
  val s = strn_append(s, " staloadsyms=0 staloadfiles=0\n")
in s end
//
(* ---- capabilities (the initialize reply) ---- *)
fun jstrs(xs: list(string)): list(jval) =
  (case+ xs of list_nil() => list_nil() | list_cons(x, r) => list_cons(JVstr x, jstrs(r)))
fun tok_types((*void*)): list(string) =
  list_cons("namespace", list_cons("type", list_cons("typeParameter", list_cons("parameter",
  list_cons("variable", list_cons("property", list_cons("function", list_cons("enumMember",
  list_cons("keyword", list_cons("string", list_cons("number", list_cons("operator",
  list_cons("comment", list_nil())))))))))))))
fun tok_mods((*void*)): list(string) =
  list_cons("declaration", list_cons("definition", list_cons("readonly",
  list_cons("static", list_cons("defaultLibrary", list_nil())))))
fun capabilities((*void*)): jval = let
  val tdsync = JVobj(list_cons(jpr("openClose", JVbool true),
                     list_cons(jpr("change", JVint 2),
                     list_cons(jpr("save", JVobj(list_cons(jpr("includeText", JVbool false), list_nil()))), list_nil()))))
  val complp = JVobj(list_cons(jpr("triggerCharacters", JVarr(list_cons(JVstr ".", list_nil()))),
                     list_cons(jpr("resolveProvider", JVbool false), list_nil())))
  val legend = JVobj(list_cons(jpr("tokenTypes", JVarr(jstrs(tok_types()))),
                     list_cons(jpr("tokenModifiers", JVarr(jstrs(tok_mods()))), list_nil())))
  val semp = JVobj(list_cons(jpr("legend", legend),
                   list_cons(jpr("full", JVbool true), list_cons(jpr("range", JVbool false), list_nil()))))
  // build the field list innermost-first (each `val fs` is flat: one close paren).
  val fs = list_cons(jpr("semanticTokensProvider", semp), list_nil{jpair}())
  val fs = list_cons(jpr("completionProvider", complp), fs)
  val fs = list_cons(jpr("workspaceSymbolProvider", JVbool true), fs)
  val fs = list_cons(jpr("inlayHintProvider", JVbool true), fs)
  val fs = list_cons(jpr("documentHighlightProvider", JVbool true), fs)
  val fs = list_cons(jpr("referencesProvider", JVbool true), fs)
  val fs = list_cons(jpr("documentSymbolProvider", JVbool true), fs)
  val fs = list_cons(jpr("typeDefinitionProvider", JVbool true), fs)
  val fs = list_cons(jpr("definitionProvider", JVbool true), fs)
  val fs = list_cons(jpr("hoverProvider", JVbool true), fs)
  val fs = list_cons(jpr("textDocumentSync", tdsync), fs)
  val caps = JVobj(fs)
  val sinfo = JVobj(list_cons(jpr("name", JVstr "xats-lsp-resident"), list_cons(jpr("version", JVstr "0.1.0"), list_nil{jpair}())))
in
  JVobj(list_cons(jpr("capabilities", caps), list_cons(jpr("serverInfo", sinfo), list_nil{jpair}())))
end
//
(* ---- per-check validate + publish ---- *)
fun run_validation(uri: string, sourceText: string, mode: string, isLive: sint): void = let
  val t0 = lsp_now_ms()
  val () = idx_reset()
  val curPath = lsp_uri2path(uri)
  val () = conv_set_cur(uri, curPath, sourceText)
  val normpath = proj_index_file(curPath, sourceText)
  val ds = $UN.cast10{diagnostics}(uri)            // unused sink (idx owns diagnostics)
  val u = $UN.cast10{url}(uri)
  val verr =
    if (isLive = 1)
      then lsp_guard(lam () => live_validator(cur_deps(), ds, u, sourceText))
      else lsp_guard(lam () => text_validator(cur_deps(), ds, u))
  val () = idx_commit(uri)
  val () = oset_add(uri)
  val () = idx_proj_delete(normpath)
  val diagsStr = (if (verr = 1) then abort_diag_str() else idx_diagnostics())
  val () = publish_raw(uri, diagsStr)
  val () = (if (cell_get{sint}(the_has_refresh) = 1) then send_sem_refresh() else ())
  val ms = lsp_now_ms() - t0
  val nd = (if (verr = 1) then 1 else idx_ndiags())
  val () = lsp_log(metric_line(uri, mode, ms, nd, idx_count(uri, 0), idx_count(uri, 1), idx_count(uri, 2), JS_stat_count()))
  val () = conv_set_cur("", "", "")
in () end
//
(* ---- request param helpers ---- *)
fun p_uri(m: jval): string = jas_str(jget3(m, "params", "textDocument", "uri"), "")
fun p_line(m: jval): sint = jas_int(jget3(m, "params", "position", "line"), 0)
fun p_char(m: jval): sint = jas_int(jget3(m, "params", "position", "character"), 0)
//
(* ---- completion: doc-derived word + idx_completion (both ATS) ---- *)
fun do_completion(m: jval): string = let
  val uri = p_uri(m) val line = p_line(m) val ch = p_char(m)
in
  if (doc_has(uri) = false) then "{\"isIncomplete\":false,\"items\":[]}"
  else let
    val parts = split_nl(doc_complete_ctx(uri, line, ch))   // "word\nisMember\ndotCol\nwcol"
    val word = nth_s(parts, 0)
    val isM = str2int(nth_s(parts, 1))
    val dotCol = str2int(nth_s(parts, 2))
    val wcol = str2int(nth_s(parts, 3))
  in idx_completion(uri, line, ch, word, isM, line, dotCol, wcol) end
end
//
fun on_inlay(idv: jval, m: jval): void = let
  val rng = jget2(m, "params", "range")
in
  if jis_obj(rng)
    then respond_raw(idv, idx_query(p_uri(m), 6,
           jas_int(jget2(rng, "start", "line"), 0), jas_int(jget2(rng, "start", "character"), 0),
           jas_int(jget2(rng, "end", "line"), 0), jas_int(jget2(rng, "end", "character"), 0)))
    else respond_raw(idv, idx_query(p_uri(m), 5, 0, 0, 0, 0))
end
//
(* ---- .xats-lsp project flags ---- *)
fun str_starts(s: string, pre: string): bool = let
  val np = str_len(pre) val ns = str_len(s)
  fun chk(i: sint): bool =
    if (i >= np) then true
    else if (i >= ns) then false
    else if (str_char_code(s, i) = str_char_code(pre, i)) then chk(i+1) else false
in chk(0) end
// trim ASCII spaces/tabs/CR from both ends.
fun is_ws(c: sint): bool =
  if (c = 32) then true else if (c = 9) then true else if (c = 13) then true else false
fun str_trim(s: string): string = let
  val n = str_len(s)
  fun lead(i: sint): sint = if (i >= n) then i else if is_ws(str_char_code(s, i)) then lead(i+1) else i
  fun trail(i: sint): sint = if (i <= 0) then 0 else if is_ws(str_char_code(s, i-1)) then trail(i-1) else i
  val a = lead(0) val b = trail(n)
in if (a >= b) then "" else str_slice(s, a, b) end
fun load_flags_lines(xs: list(string)): void =
  (case+ xs of
   | list_nil() => ()
   | list_cons(line, r) => let
       val s = str_trim(line)
       val skip = (if strn_eq(s, "") then true else (str_char_code(s, 0) = 35))   // '#'
     in
       (if skip then () else lsp_addflag(if str_starts(s, "--") then s else strn_append("--", s)));
       load_flags_lines(r)
     end)
fun load_flags(root: string): void = let
  val text = lsp_fs_read(strn_append(root, "/.xats-lsp"))
in
  if strn_eq(text, "") then () else load_flags_lines(split_nl(text))
end
fun load_flags_all(roots: list(string)): void =
  (case+ roots of list_nil() => () | list_cons(r, rest) => (load_flags(r); load_flags_all(rest)))
//
(* ---- workspace roots from the initialize params ---- *)
fun roots_from_wf(xs: list(jval), acc: string): string =
  (case+ xs of
   | list_nil() => acc
   | list_cons(x, r) => let
       val u = jas_str(jget(x, "uri"), "")
       val p = (if strn_eq(u, "") then "" else lsp_norm(lsp_uri2path(u)))
     in roots_from_wf(r, (if strn_eq(p, "") then acc else strn_append(acc, strn_append(p, "\n")))) end)
fun ws_roots(params: jval): string = let
  val fromWf = roots_from_wf(jas_arr(jget(params, "workspaceFolders")), "")
in
  if (strn_eq(fromWf, "") = false) then fromWf
  else let
    val ru = jget(params, "rootUri")
  in
    (case+ ru of
     | JVstr s => strn_append(lsp_norm(lsp_uri2path(s)), "\n")
     | _ => let val rp = jget(params, "rootPath") in
         (case+ rp of JVstr s => strn_append(lsp_norm(s), "\n") | _ => "") end)
  end
end
//
fun on_initialize(idv: jval, m: jval): void = let
  val params = jget(m, "params")
  val st = jget3(params, "capabilities", "workspace", "semanticTokens")
  val hasRef = (if jis_obj(st) then (case+ jget(st, "refreshSupport") of JVnull() => 0 | _ => 1) else 0)
  val () = cell_set{sint}(the_has_refresh, hasRef)
  val roots = ws_roots(params)
  val () = cell_set{string}(the_pending_roots, roots)
  val () = load_flags_all(split_nl_ne(roots))
in respond(idv, capabilities()) end
//
(* ---- background project indexer (symbols-only; no publish) ---- *)
// process one worklist path; returns the new `done` count (helper so bg_loop's
// case+ branch stays a single expression — a multi-line if as a case RHS errcks).
fun bg_one(p: string, done: sint): sint =
  if strn_eq(p, "") then done
  else let val uri = lsp_path2uri(p) in
    if (if oset_has(uri) then true else JS_path_is_prelude(p)) then done
    else if (lsp_fs_exists(p) = false) then done
    else let
      val () = idx_reset()
      val () = conv_set_cur(uri, p, lsp_fs_read(p))
      val _ = lsp_guard(lam () => text_validator(cur_deps(), $UN.cast10{diagnostics}(uri), $UN.cast10{url}(uri)))
      val () = idx_proj_store(p, uri)
      val () = conv_set_cur("", "", "")
    in done + 1 end
  end
fun bg_loop(paths: list(string), done: sint): sint =
  (case+ paths of
   | list_nil() => done
   | list_cons(p, rest) => (if (done >= the_bg_cap) then done else bg_loop(rest, bg_one(p, done))))
fun bg_index((*void*)): void =
  if (the_bg_cap <= 0) then ()
  else let
    val done = bg_loop(split_nl_ne(JS_proj_worklist()), 0)
  in lsp_log(strn_append("[xats-lsp-resident] bg-index: ", strn_append(int2str(done), " file(s) indexed\n"))) end
//
fun on_initialized((*void*)): void = let
  val roots = cell_get{string}(the_pending_roots)
in
  if strn_eq(roots, "") then ()
  else let
    val () = cell_set{string}(the_pending_roots, "")
    val _ = lsp_guard(lam () => JS_proj_scan(roots))
    val _ = lsp_guard(lam () => bg_index())
  in () end
end
//
(* ---- prelude reload (a $XATSHOME file was saved) ---- *)
fun reval_open_docs(xs: list(string)): void =
  (case+ xs of
   | list_nil() => ()
   | list_cons(uri, r) => ((if doc_has(uri) then run_validation(uri, doc_text(uri), "disk", 0) else ()); reval_open_docs(r)))
fun reload_and_revalidate(savedUri: string): void = let
  val () = lsp_log(strn_append("[xats-lsp-resident] reload_prelude: ", strn_append(savedUri, "\n")))
  val _ = lsp_guard(lam () => let
    val () = reload_prelude()
    val () = idx_clear()
    val () = oset_clear()
    val () = cell_set{depgraph}(the_deps_c, depgraph_make())
    val () = cell_set{depgraph}(the_fwd_c, depgraph_make())
    val () = JS_sig_reset()
  // re-validate every OPEN doc (the doc store, NOT the just-cleared open-set).
  in reval_open_docs(split_nl_ne(doc_uris())) end)
in () end
//
(* ---- watched files (Created=1 Changed=2 Deleted=3) ---- *)
fun evict_affected(paths: list(string), n: sint): sint =
  (case+ paths of
   | list_nil() => n
   | list_cons(p, rest) => let val r = JS_path2stamp(p) in
       (if (r.0 = 1) then let val _ = lsp_guard(lam () => evict_stamp(r.1)) in evict_affected(rest, n+1) end
        else evict_affected(rest, n)) end)
fun docs_affected(uris: list(string), affected: list(string)): list(string) =
  (case+ uris of
   | list_nil() => list_nil()
   | list_cons(uri, r) => let val dp = lsp_norm(lsp_uri2path(uri)) in
       (if (if strn_eq(dp, "") then false else list_mem(affected, dp))
          then list_cons(uri, docs_affected(r, affected))
          else docs_affected(r, affected)) end)
fun watched_kind(ct: sint): string =
  if (ct = 1) then "create" else if (ct = 3) then "delete" else "change"
fun on_watched(uri: string, ct: sint): void = let
  val npath = lsp_norm(lsp_uri2path(uri))
in
  if (if strn_eq(npath, "") then true else JS_path_is_prelude(npath)) then ()
  else let
    val () = (if (ct = 3) then proj_remove_file(npath)
              else let val _ = proj_index_file(npath, lsp_fs_read(npath)) in () end)
    val affected = list_cons(npath, split_nl_ne(proj_rev_closure(npath)))
    val evicted = evict_affected(affected, 0)
    val () = JS_sig_forget(npath, (if (ct = 3) then 1 else 0))
    val toReval = docs_affected(cell_get{list(string)}(the_openset), affected)
    val ml = strn_append("[xats-lsp-resident] watched ", watched_kind(ct))
    val ml = strn_append(ml, " ") val ml = strn_append(ml, npath)
    val ml = strn_append(ml, " -> affected=") val ml = strn_append(ml, int2str(list_len(affected)))
    val ml = strn_append(ml, " evicted=") val ml = strn_append(ml, int2str(evicted))
    val ml = strn_append(ml, " revalidated=") val ml = strn_append(ml, int2str(list_len(toReval)))
    val ml = strn_append(ml, "\n")
    val () = lsp_log(ml)
  in reval_open_docs(toReval) end
end
fun on_watched_all(m: jval): void = let
  fun go(xs: list(jval)): void =
    (case+ xs of list_nil() => ()
     | list_cons(c, r) => (on_watched(jas_str(jget(c, "uri"), ""), jas_int(jget(c, "type"), 0)); go(r)))
in go(jas_arr(jget2(m, "params", "changes"))) end
//
(* ---- notification handlers ---- *)
fun on_didopen(m: jval): void = let
  val uri = jas_str(jget3(m, "params", "textDocument", "uri"), "")
  val text = jas_str(jget3(m, "params", "textDocument", "text"), "")
  val ver = jas_int(jget3(m, "params", "textDocument", "version"), 0)
  val () = doc_set(uri, text, ver)
in run_validation(uri, text, "disk", 0) end
fun on_didsave(m: jval): void = let
  val uri = jas_str(jget3(m, "params", "textDocument", "uri"), "")
  val fpath = lsp_uri2path(uri)
in
  if JS_path_is_prelude(fpath) then reload_and_revalidate(uri)
  else (if doc_has(uri) then run_validation(uri, doc_text(uri), "disk", 0) else ())
end
fun on_didclose(m: jval): void = let
  val uri = jas_str(jget3(m, "params", "textDocument", "uri"), "")
  val () = doc_del(uri)
  val () = oset_del(uri)
  val () = idx_evict(uri)
in publish_raw(uri, "[]") end
//
fun handle_notification(method: string, m: jval): void =
  if strn_eq(method, "initialized") then on_initialized()
  else if strn_eq(method, "exit") then lsp_exit()
  else if strn_eq(method, "textDocument/didOpen") then on_didopen(m)
  else if strn_eq(method, "textDocument/didSave") then on_didsave(m)
  else if strn_eq(method, "textDocument/didClose") then on_didclose(m)
  else if strn_eq(method, "workspace/didChangeWatchedFiles") then on_watched_all(m)
  else ()
//
(* ---- request router ---- *)
fun incl_decl(m: jval): sint = (if jas_bool(jget3(m, "params", "context", "includeDeclaration")) then 1 else 0)
fun stats_uri(m: jval): string =
  let val u = jas_str(jget2(m, "params", "uri"), "") in
    (if strn_eq(u, "") then jas_str(jget3(m, "params", "textDocument", "uri"), "") else u) end
fun handle_request(idv: jval, method: string, m: jval): void =
  if strn_eq(method, "initialize") then on_initialize(idv, m)
  else if strn_eq(method, "shutdown") then respond(idv, JVnull())
  else if strn_eq(method, "textDocument/hover") then respond_raw(idv, idx_query(p_uri(m), 0, p_line(m), p_char(m), 0, 0))
  else if strn_eq(method, "textDocument/definition") then respond_raw(idv, idx_query(p_uri(m), 1, p_line(m), p_char(m), 0, 0))
  else if strn_eq(method, "textDocument/typeDefinition") then respond_raw(idv, idx_query(p_uri(m), 2, p_line(m), p_char(m), 0, 0))
  else if strn_eq(method, "textDocument/references") then respond_raw(idv, idx_query(p_uri(m), 3, p_line(m), p_char(m), incl_decl(m), 0))
  else if strn_eq(method, "textDocument/documentHighlight") then respond_raw(idv, idx_query(p_uri(m), 4, p_line(m), p_char(m), 0, 0))
  else if strn_eq(method, "textDocument/documentSymbol") then respond_raw(idv, idx_query(p_uri(m), 9, 0, 0, 0, 0))
  else if strn_eq(method, "textDocument/inlayHint") then on_inlay(idv, m)
  else if strn_eq(method, "workspace/symbol") then respond_raw(idv, idx_workspace(jas_str(jget2(m, "params", "query"), "")))
  else if strn_eq(method, "textDocument/completion") then respond_raw(idv, do_completion(m))
  else if strn_eq(method, "textDocument/semanticTokens/full") then respond_raw(idv, idx_query(p_uri(m), 7, 0, 0, 0, 0))
  else if strn_eq(method, "xats/indexStats") then respond_raw(idv, idx_query(stats_uri(m), 8, 0, 0, 0, 0))
  else respond(idv, JVnull())
//
fun on_message(frame: string): void = let
  val m = json_parse(frame)
  val method = jas_str(jget(m, "method"), "")
  val idv = jget(m, "id")
in
  if strn_eq(method, "") then ()                 // a response to our own request -> ignore
  else (case+ idv of JVnull() => handle_notification(method, m) | _ => handle_request(idv, method, m))
end
//
(* ---- didChange (debounced): apply edit + prune now; validate on timeout ---- *)
fun apply_change(frame: string): string = let
  val m = json_parse(frame)
  val uri = jas_str(jget3(m, "params", "textDocument", "uri"), "")
in
  if (doc_has(uri) = false) then ""
  else let
    fun apply_one(text: string, ch: jval): string = let
      val rng = jget(ch, "range")
    in
      if jis_obj(rng)
        then doc_apply_range(text,
               jas_int(jget2(rng, "start", "line"), 0), jas_int(jget2(rng, "start", "character"), 0),
               jas_int(jget2(rng, "end", "line"), 0), jas_int(jget2(rng, "end", "character"), 0),
               jas_str(jget(ch, "text"), ""))
        else jas_str(jget(ch, "text"), text)
    end
    fun apply_all(text: string, xs: list(jval)): string =
      (case+ xs of list_nil() => text | list_cons(c, r) => apply_all(apply_one(text, c), r))
    val text1 = apply_all(doc_text(uri), jas_arr(jget2(m, "params", "contentChanges")))
    val ver = jas_int(jget3(m, "params", "textDocument", "version"), 0)
    val () = doc_set(uri, text1, ver)
    val _ = lsp_guard(lam () => cache_pruner(cur_deps(), $UN.cast10{url}(uri)))
  in uri end
end
fun validate_live(uri: string): void =
  if JS_path_is_prelude(lsp_uri2path(uri)) then ()
  else let val _ = lsp_guard(lam () => (if doc_has(uri) then run_validation(uri, doc_text(uri), "live", 1) else ())) in () end
//
(* ---- the message loop + debounce (lsp_msg_read provides the timeout) ---- *)
fun msg_kind(frame: string): sint = let
  val method = jas_str(jget(json_parse(frame), "method"), "")
in
  if strn_eq(method, "textDocument/didChange") then 1
  else if strn_eq(method, "textDocument/didSave") then 2
  else if strn_eq(method, "textDocument/didClose") then 3 else 0
end
fun msg_uri(frame: string): string = jas_str(jget3(json_parse(frame), "params", "textDocument", "uri"), "")
fun on_message_guarded(frame: string): void = let val _ = lsp_guard(lam () => on_message(frame)) in () end
fun serve_loop(pending: string): void = let
  val rd = lsp_msg_read(if strn_eq(pending, "") then (0 - 1) else the_debounce_ms)
  val kind = rd.0
in
  if (kind = 2) then ()                           // EOF
  else if (kind = 1) then                          // debounce timeout
    (if strn_eq(pending, "") then serve_loop("") else let val () = validate_live(pending) in serve_loop("") end)
  else let
    val frame = rd.1
    val mk = msg_kind(frame)
  in
    if (mk = 1) then let val u = apply_change(frame) in serve_loop(u) end
    else if (mk = 2) then let
      val u = msg_uri(frame)
      val () = on_message_guarded(frame)
    in serve_loop(if strn_eq(pending, u) then "" else pending) end
    else if (mk = 3) then let
      val u = msg_uri(frame)
      val () = on_message_guarded(frame)
    in serve_loop(if strn_eq(pending, u) then "" else pending) end
    else let val () = on_message_guarded(frame) in serve_loop(pending) end
  end
end
//
(* ****** ****** *)
//
// initialize the xatsopt environment ONCE (loads the prelude), set the flags,
// then bootstrap the vscode-languageserver connection loop. These run on load.
//
val () = prelude_pvsload()
//
// R2a PRELUDE SNAPSHOT: right after the prelude loads (above) and BEFORE any user
// file is checked, record the set of file stamps already cached in each of the
// three topmaps. That set = the prelude / $XATSHOME files; they are IMMUTABLE for
// the session — never statted, never evicted (the C1/restart path is out of scope
// here). freeze() seals the set. Any file NOT in it is a workspace file subject
// to mtime validation. This also correctly excludes a workspace rooted at the
// ATS-Xanadu repo: its prelude files are already in the snapshot.
//
val () = prelude_take_snapshot()
//
// Stage 6 cutover: the dispatch + validation loop is now THIS driver (above).
// Bind the two closures the floor's FS workspace-scan still needs (proj_index_file
// + the prelude classifier), announce readiness, then run the message loop over
// the floor's lsp_msg_read/lsp_msg_write.  These run on load.
val () = lsp_boot(proj_index_file, proj_fwd_count, proj_rev_count, JS_path_is_prelude)
val () = lsp_log("[xats-lsp-resident] listening on stdio (resident, in-process)\n")
val () = serve_loop("")
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_resident.dats]
*)
