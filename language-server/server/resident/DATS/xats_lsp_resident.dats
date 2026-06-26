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
#implfun severity_error$make() =
  vscode_severity_error$make()
  where { #extern fun vscode_severity_error$make() : severity = $extnam() }
//
#implfun position_make(line, offs) : position =
  vscode_position_make(line, offs)
  where { #extern fun
    vscode_position_make(line: int, offs: int): position = $extnam() }
//
#implfun range_make(pbeg, pend): range =
  vscode_range_make(pbeg, pend)
  where { #extern fun
    vscode_range_make(pbeg: position, pend: position): range = $extnam() }
//
#implfun range_of_loctn(loc0) = let
    val pbeg0 = loc0.pbeg()
    val pend0 = loc0.pend()
    val pbeg1 = position_make(pbeg0.nrow(), pbeg0.ncol())
    val pend1 = position_make(pend0.nrow(), pend0.ncol())
  in range_make(pbeg1, pend1)
  end
//
#implfun diagnostic_make(severity, location, message, source) : diagnostic =
  vscode_diagnostic_make(severity, location, message, source)
  where { #extern fun
    vscode_diagnostic_make
    ( severity: severity, location: range
    , message: string, source: string): diagnostic = $extnam() }
//
#implfun diagnostics_push(ds, d) =
  vscode_diagnostics_push(ds, d)
  where { #extern fun
    vscode_diagnostics_push(ds: diagnostics, d: diagnostic): void = $extnam() }
#symload push with diagnostics_push
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
#implfun fwd_graph() =
  JS_fwd_graph()
  where { #extern fun JS_fwd_graph(): depgraph = $extnam() }
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
#implfun initialize(f, lv, g, h, e, af, ir, ic, iv, icl, idg, ind, ict, iq, pix, prm, prc, pfc, prv, iws, icp, pst, pdl) =
  vscode_initialize(f, lv, g, h, e, af, ir, ic, iv, icl, idg, ind, ict, iq, pix, prm, prc, pfc, prv, iws, icp, pst, pdl)
  where { #extern fun
    vscode_initialize
    ( f: text_validator_t, lv: live_validator_t, g: cache_pruner_t
    , h: reload_prelude_t, e: evict_stamp_t, af: add_flag_t
    , ir: () -> void, ic: (string) -> void, iv: (string) -> void, icl: () -> void
    , idg: () -> string, ind: () -> int, ict: (string, int) -> int
    , iq: (string, int, int, int, int, int) -> string
    , pix: (string, string) -> string, prm: (string) -> void, prc: (string) -> string
    , pfc: () -> int, prv: () -> int
    , iws: (string) -> string, icp: (string, int, int, string, int, int, int, int) -> string
    , pst: (string, string) -> void, pdl: (string) -> void): void = $extnam() }
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
// the ATS per-uri index API handed to the glue as eight closures (the harvest
// sinks accumulate into this module; the glue commits + serves requests, by uri).
val () = initialize
  ( text_validator, live_validator, cache_pruner, reload_prelude, evict_stamp, lsp_addflag
  , idx_reset, idx_commit, idx_evict, idx_clear, idx_diagnostics, idx_ndiags, idx_count, idx_query
  , proj_index_file, proj_remove_file, proj_rev_closure, proj_fwd_count, proj_rev_count
  , idx_workspace, idx_completion, idx_proj_store, idx_proj_delete)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_resident.dats]
*)
