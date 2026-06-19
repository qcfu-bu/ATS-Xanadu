////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//        RESIDENT LSP server  —  JS glue (.cats)  (workstream R1)     //.
//        companion for DATS/xats_lsp_resident.dats                    //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// This is the JS half of the FFI idiom (primer §10.1). Every ATS3
//   `#extern fun NAME(...) = $extnam()`  in xats_lsp_resident.dats
// is implemented here by a same-named JS function. build.sh cat-links this
// file BEFORE the transpiled DATS, so its `require(...)` consts exist when the
// DATS top-level vals run (require is not hoisted).
//
// It owns:
//   (1) the vscode-languageserver connection loop (createConnection,
//       TextDocuments, onDidOpen/onDidSave -> validate, onDidChangeContent ->
//       prune, onHover/onDefinition/onTypeDefinition -> per-uri index lookup);
//       ported from the reference src/CATS/lsp_bootstrap.js;
//   (2) the cache-eviction primitive JS_map_reset = delete env[key], plus the
//       depset (Set) / depgraph (Map) ported from the reference;
//   (3) the HARVEST accumulators: diag_push / hover_push / def_push populate a
//       per-uri index (so onHover/onDefinition answer from it), with the dedup
//       (Decision D6) + s2typ friendly-name mapping reused from our checker's
//       .cats (server/CATS/xats_lsp_check.cats).
//
////////////////////////////////////////////////////////////////////////.
//
const LSP_ls   = require('vscode-languageserver/node');
const LSP_text = require('vscode-languageserver-textdocument');
const LSP_url  = require('url');
const LSP_path = require('node:path');
//
////////////////////////////////////////////////////////////////////////.
// ---- url <-> path, severity, position, range, diagnostic (reference) -- //
//
function vscode_url_to_path(uri) {
  try { return LSP_url.fileURLToPath(uri); }
  catch (e) {
    // tolerate bare paths / non-file uris
    return String(uri).replace(/^file:\/\//, '');
  }
}
function vscode_severity_error$make() { return LSP_ls.DiagnosticSeverity.Error; }
function vscode_position_make(line, offs) { return { line: line, character: offs }; }
function vscode_range_make(pbeg, pend) { return { start: pbeg, end: pend }; }
function vscode_diagnostic_make(severity, range, message, source) {
  return { severity: severity, range: range, message: message, source: source };
}
function vscode_diagnostics_push(diagnostics, d) { diagnostics.push(d); }
//
function vscode_regex_make(pattern) { return new RegExp(pattern); }
function vscode_regex_test(re, input) { return re.test(input); }
//
////////////////////////////////////////////////////////////////////////.
// ---- depset (Set) / depgraph (Map) — ported from the reference ------- //
//
function JS_depset_make() { return new Set(); }
function JS_depset_add(dp, k) { dp.add(k); }
function JS_depset_pop(dp) {
  const [elem] = dp;
  dp.delete(elem);
  return elem;
}
function JS_depset_is_empty(dp) { return (dp.size <= 0); }
function JS_depset_has(dp, k) { return dp.has(k); }
function JS_depset_union(dp1, dp2) {
  // Set.prototype.union landed in node 22; fall back for older runtimes.
  if (typeof dp1.union === 'function') { return dp1.union(dp2); }
  const out = new Set(dp1);
  for (const x of dp2) { out.add(x); }
  return out;
}
// depgraph: Map<stamp, [sym_t, Set<sym_t>]>. k is the dependency's stamp
// (number), k0 its sym_t, v the dependent's sym_t. Editing the dependency (k)
// later yields its dependents (the Set) so they get evicted too.
function JS_depgraph_add(dp, k, k0, v) {
  const edges = dp.get(k);
  if (edges === undefined) { dp.set(k, [k0, new Set([v])]); }
  else { edges[1].add(v); }
}
function JS_depgraph_delete(dp, k) { dp.delete(k); }
function JS_depgraph_has(dp, k) { return (dp.get(k) !== undefined); }
function JS_depgraph_find(dp, k) {
  const edges = dp.get(k);
  return (edges === undefined) ? new Set() : edges[1];
}
//
// R2a FORWARD graph: "key0 staloads key1" edges (the reverse of LSP_dependencies).
// Same Map<stamp,[sym_t,Set<sym_t>]> shape; populated in the SAME dependency pass.
// The precheck walks a target's forward closure (its transitive staloads) and
// re-stats each WORKSPACE member, so it only ever touches the small dep set —
// never the ~100 prelude files (those aren't in any workspace closure edge here,
// and even if walked, sig_changed skips prelude stamps).
const LSP_fwd = new Map();
function JS_fwd_graph() { return LSP_fwd; }
//
////////////////////////////////////////////////////////////////////////.
// ---- THE cache-eviction primitive: delete env[key] ------------------- //
//
// the_d{1,2,3}parenv are jshmaps (plain JS objects) keyed by the file's stamp
// (topmap_insert -> g0u2s(uint(key.stmp())) in xsymmap_topmap.dats). The ATS3
// side hands us key.stmp() (the same number), so `delete env[stamp]` evicts
// exactly that file. This is the make-or-break primitive (primer §4).
function JS_map_reset(env, key) {
  if (env[key] !== undefined) { delete env[key]; }
}
//
////////////////////////////////////////////////////////////////////////.
// ---- R2a: content-validated cache (out-of-band-edit invalidation) ---- //
//
// The R1 cache evicts on editor events (didChange) only. Out-of-band edits
// (another editor, git pull/checkout, codegen, formatters) fire NO event, so
// the_d?parenv keeps a STALE entry -> wrong diagnostics. R2a closes this by
// stamping every cached WORKSPACE file with a {mtimeMs,size} signature and, on
// every check, re-statting the target's staload closure to catch on-disk drift
// BEFORE serving from cache. (LSP-ARCHITECTURE-AND-PLAN.md, R2 Layer A.)
//
const LSP_fs = require('node:fs');
//
// (1) PRELUDE / $XATSHOME EXCLUSION. The prelude + compiler tree under $XATSHOME
// are loaded once at startup and treated as IMMUTABLE for the session — never
// stat, never evict (that's the C1/restart path + ats3.reloadPrelude, out of
// scope here). A file is "immutable" iff its resolved path lives under $XATSHOME;
// any other file is a WORKSPACE file subject to mtime validation.
//
// Why a PATH prefix and not a topmap snapshot: the prelude is bootstrapped via
// the global-env loaders (the_fxtyenv_pvsload / the_tr12env_pvsl00d), which merge
// definitions into the_sexpenv/the_dexpenv but do NOT populate the per-file
// the_d{1,2,3}parenv caches — those fill in lazily the first time a USER file
// staloads a prelude file. So a startup topmap snapshot is empty and useless as a
// discriminator; the $XATSHOME path prefix is the reliable, eager test. (This is
// exactly the "resolves under $XATSHOME" detection the architecture doc's
// prelude edge-case section calls for.) The topmap snapshot is retained below as
// a belt-and-suspenders SECONDARY guard (it captures any prelude file already in
// the caches), but the path prefix is the primary mechanism.
//
function LSP_norm(p) {
  // resolve to an absolute, symlink-free path for a stable prefix compare.
  let s = String(p || "");
  if (s === "") return "";
  try { return LSP_fs.realpathSync(s); }
  catch (e) { /* file may not exist (deleted / not-yet-created) -> fall through */ }
  // STABLE fallback for a non-existent file: realpath the longest EXISTING
  // ancestor directory (symlink-canonical), then rejoin the trailing segments.
  // Without this, a path normalizes differently before vs after deletion (e.g.
  // /var/... realpaths to /private/var/... while it exists but resolve() yields
  // /var/... once it's gone), which would break the path-keyed project index on
  // watched DELETE events.
  try {
    let abs = LSP_path.resolve(s);
    const tail = [];
    let dir = abs;
    for (;;) {
      try { const real = LSP_fs.realpathSync(dir); return tail.length ? LSP_path.join(real, ...tail) : real; }
      catch (e2) {
        const parent = LSP_path.dirname(dir);
        if (parent === dir) return abs;            // reached root; nothing exists
        tail.unshift(LSP_path.basename(dir));
        dir = parent;
      }
    }
  } catch (e3) { return s; }
}
// $XATSHOME (prelude/compiler tree root), normalized once. Trailing sep so a
// sibling like "<home>x/..." does not match "<home>/...".
const LSP_xatshome = (function () {
  const h = LSP_norm(process.env.XATSHOME || "");
  return h === "" ? "" : (h.endsWith(LSP_path.sep) ? h : (h + LSP_path.sep));
})();
function JS_path_is_prelude(path) {
  if (LSP_xatshome === "") return false;       // no XATSHOME -> nothing excluded
  const s = LSP_norm(path);
  return s !== "" && (s + LSP_path.sep).startsWith(LSP_xatshome);
}
//
// secondary guard: file STAMPS already cached at startup (usually empty; see note
// above). prelude_snapshot(topmap) unions one topmap's keys; prelude_freeze seals.
let LSP_prelude_stamps = new Set();
let LSP_prelude_frozen = false;
function JS_prelude_snapshot(env) {
  for (const k of Object.keys(env)) { LSP_prelude_stamps.add(String(k)); }
}
// clear the snapshot Set before re-snapshotting after an in-process prelude
// reload: the freshly reloaded prelude files get NEW stamps, so the old snapshot
// is stale. Also un-freeze so JS_prelude_freeze can re-seal + re-log.
function JS_prelude_snapshot_reset() {
  LSP_prelude_stamps = new Set();
  LSP_prelude_frozen = false;
}
function JS_prelude_freeze() {
  LSP_prelude_frozen = true;
  try {
    process.stderr.write('[xats-lsp-resident] prelude immutable: XATSHOME=' +
      (LSP_xatshome || '(unset)') + ' + ' + LSP_prelude_stamps.size +
      ' snapshot stamp(s)\n');
  } catch (e) {}
}
function JS_is_prelude(stamp) { return LSP_prelude_stamps.has(String(stamp)); }
//
// (2) SIGNATURE MAP: stamp -> {path, mtimeMs, size} for every cached WORKSPACE
// file. Recorded when a workspace file is validated/cached. Prelude/$XATSHOME
// files never enter this map (gated in JS_sig_record), so they are never
// re-statted and never reported as changed.
const LSP_signatures = new Map();
//
// R2b PATH -> STAMP index. The signature map is stamp -> {path,...}; the watched-
// files cascade needs the reverse (it discovers AFFECTED files by PATH, via the
// project index, then must evict each by its compiler STAMP). We fill it for free
// here: every time a workspace file is validated/cached, sig_record knows both its
// stamp and its absolute path. Keyed by the normalized absolute path. A file that
// has never been checked has no entry -> evicting it is a correct no-op (it was
// never cached). Cleared together with LSP_signatures on a prelude reload.
const LSP_path2stamp = new Map();
function JS_path2stamp_lookup(path) {     // -> stamp string | undefined
  const n = LSP_norm(path);
  return (n === "") ? undefined : LSP_path2stamp.get(n);
}
// metric: how many statSync calls the last pre-check made (kept tiny: only the
// target's small workspace closure, never the ~100 prelude files).
let LSP_stat_count = 0;
function LSP_stat_count_reset() { const n = LSP_stat_count; LSP_stat_count = 0; return n; }
//
function LSP_stat_sig(path) {
  // {mtimeMs,size}, or null if the file is gone / unreadable. ~µs.
  try {
    LSP_stat_count++;
    const st = LSP_fs.statSync(path);
    return { mtimeMs: st.mtimeMs, size: st.size };
  } catch (e) { return null; }
}
// is this cached file immutable (prelude/$XATSHOME or a startup-snapshot stamp)?
function LSP_immutable(stamp, path) {
  if (LSP_prelude_stamps.has(String(stamp))) return true;
  return JS_path_is_prelude(path);
}
// record/refresh the signature for a workspace file. Prelude files are skipped
// (immutable): they never enter the signature map, so they are never re-statted.
function JS_sig_record(stamp, path) {
  const key = String(stamp);
  if (!path) return;
  if (LSP_immutable(key, path)) return;                 // prelude/$XATSHOME: skip
  const sig = LSP_stat_sig(path);
  if (sig === null) return;
  LSP_signatures.set(key, { path: path, mtimeMs: sig.mtimeMs, size: sig.size });
  // R2b: maintain the reverse path->stamp index (normalized absolute path).
  const n = LSP_norm(path);
  if (n !== "") LSP_path2stamp.set(n, key);
}
function JS_sig_refresh(stamp) {
  const rec = LSP_signatures.get(String(stamp));
  if (rec === undefined) return;
  const sig = LSP_stat_sig(rec.path);
  if (sig === null) return;
  rec.mtimeMs = sig.mtimeMs; rec.size = sig.size;
}
// 1 iff this stamp is a known workspace file whose ON-DISK signature now differs
// from the recorded one (out-of-band edit). 0 for prelude/unknown/unchanged.
// Re-stats the file (the whole point of R2a); cheap because the closure is small.
function JS_sig_changed(stamp) {
  const key = String(stamp);
  const rec = LSP_signatures.get(key);
  if (rec === undefined) return 0;                      // prelude or not-yet-cached
  const sig = LSP_stat_sig(rec.path);
  if (sig === null) return 1;                           // vanished/unreadable -> evict
  return (sig.mtimeMs !== rec.mtimeMs || sig.size !== rec.size) ? 1 : 0;
}
//
////////////////////////////////////////////////////////////////////////.
// ---- R2c: whole-project staload index (complete cascade) ------------- //
//
// The checked-files depgraph (LSP_dependencies / LSP_fwd) only covers files the
// server actually TYPE-CHECKED, so a dependent that has never been opened is
// invisible to its cascade. R2c builds a SEPARATE, whole-project dependency graph
// by cheaply scanning every workspace *.{sats,hats,dats} and parsing ONLY its
// `#staload`/`#include`/`#staload _ =`/`#dynload` directives (regex — NOT a
// type-check). Edges are keyed by NORMALIZED ABSOLUTE PATH (not stamp), because
// an unopened file has no compiler stamp yet. The reverse graph then gives the
// COMPLETE set of dependents for the R2b cascade: editing A invalidates every
// transitive dependent of A, opened or not.
//
//   LSP_proj_fwd : path -> Set(paths it staloads)        (forward edges)
//   LSP_proj_rev : path -> Set(paths that staload it)    (reverse edges)
//
const LSP_proj_fwd = new Map();
const LSP_proj_rev = new Map();
// indexed files (avoid re-scanning) + a cap so a huge workspace cannot block
// startup. SCAN_CAP bounds how many files the initial scan visits; if hit we log
// and stop (incremental watch events still index any file they touch on demand).
let LSP_proj_indexed = new Set();
const LSP_PROJ_SCAN_CAP =
  parseInt(process.env.ATS3_PROJ_SCAN_CAP || '4000', 10);
const LSP_PROJ_SRC_RE = /\.(sats|hats|dats)$/i;
// directive matcher: #staload "P" | #staload _ = "P" | #include "P" | #dynload "P".
// We grab the first quoted string after the directive keyword; that is the path.
const LSP_STALOAD_RE =
  /#(?:staload|include|dynload)\b[^"\n]*"([^"]+)"/g;
//
// parse a file's directive targets -> array of normalized absolute paths it
// references (resolved relative to the file's own directory). Skips $XATSHOME
// targets (immutable prelude/compiler tree) — they are never invalidatable.
function LSP_parse_staloads(filePath, text) {
  const out = [];
  const dir = LSP_path.dirname(filePath);
  let m;
  LSP_STALOAD_RE.lastIndex = 0;
  while ((m = LSP_STALOAD_RE.exec(text)) !== null) {
    let ref = m[1];
    if (!ref) continue;
    let abs;
    try { abs = LSP_path.isAbsolute(ref) ? ref : LSP_path.resolve(dir, ref); }
    catch (e) { continue; }
    const n = LSP_norm(abs);
    if (n === "") continue;
    if (JS_path_is_prelude(n)) continue;        // prelude target: not tracked
    out.push(n);
  }
  return out;
}
// remove all edges that originate at `from` (used before re-indexing a file so a
// removed #staload drops its stale edge).
function LSP_proj_unlink(from) {
  const olds = LSP_proj_fwd.get(from);
  if (olds) {
    for (const to of olds) {
      const back = LSP_proj_rev.get(to);
      if (back) { back.delete(from); if (back.size === 0) LSP_proj_rev.delete(to); }
    }
  }
  LSP_proj_fwd.delete(from);
}
// index ONE file: (re)read its directives and (re)build its forward+reverse edges.
// `text` optional (else read from disk). Returns the normalized path indexed, or
// "" on failure. Idempotent: safe to call repeatedly on watch events.
function LSP_proj_index_file(filePath, text) {
  const n = LSP_norm(filePath);
  if (n === "") return "";
  if (JS_path_is_prelude(n)) return "";          // never index the prelude tree
  if (text === undefined || text === null) {
    try { text = LSP_fs.readFileSync(n, 'utf8'); }
    catch (e) { return ""; }
  }
  LSP_proj_unlink(n);                            // drop stale edges first
  const targets = LSP_parse_staloads(n, text);
  if (targets.length > 0) {
    const fset = new Set();
    for (const to of targets) {
      fset.add(to);
      let back = LSP_proj_rev.get(to);
      if (!back) { back = new Set(); LSP_proj_rev.set(to, back); }
      back.add(n);
    }
    LSP_proj_fwd.set(n, fset);
  }
  LSP_proj_indexed.add(n);
  return n;
}
// a file was DELETED: drop its forward edges (its reverse edges — who staloads it
// — stay, harmlessly pointing at a now-missing file; they re-resolve if recreated).
function LSP_proj_remove_file(filePath) {
  const n = LSP_norm(filePath);
  if (n === "") return;
  LSP_proj_unlink(n);
  LSP_proj_indexed.delete(n);
}
// TRANSITIVE reverse closure of `path` over the PROJECT graph: every file that
// staloads it, directly or transitively (the complete dependent set, opened or
// not). Excludes `path` itself. Bounded (visited set).
function LSP_proj_rev_closure(path) {
  const start = LSP_norm(path);
  const out = new Set();
  if (start === "") return out;
  const stack = [start];
  const seen = new Set([start]);
  while (stack.length > 0) {
    const cur = stack.pop();
    const deps = LSP_proj_rev.get(cur);
    if (!deps) continue;
    for (const d of deps) {
      if (seen.has(d)) continue;
      seen.add(d); out.add(d); stack.push(d);
    }
  }
  return out;
}
// scan a directory tree for *.{sats,hats,dats} and index each. Bounded by
// LSP_PROJ_SCAN_CAP; skips the $XATSHOME subtree and dot-dirs / node_modules.
// Synchronous but cheap (one readFileSync + a regex per source file); the cap
// keeps a pathological workspace from blocking startup. Returns #files indexed.
function LSP_proj_scan_dir(root) {
  let count = 0, capped = false;
  const stack = [LSP_norm(root)];
  while (stack.length > 0) {
    if (count >= LSP_PROJ_SCAN_CAP) { capped = true; break; }
    const dir = stack.pop();
    if (dir === "" || JS_path_is_prelude(dir)) continue;
    let ents;
    try { ents = LSP_fs.readdirSync(dir, { withFileTypes: true }); }
    catch (e) { continue; }
    for (const ent of ents) {
      const name = ent.name;
      if (name.startsWith('.')) continue;          // .git, dotfiles
      if (name === 'node_modules') continue;
      const full = LSP_path.join(dir, name);
      if (ent.isDirectory()) {
        if (!JS_path_is_prelude(full)) stack.push(full);
      } else if (ent.isFile() && LSP_PROJ_SRC_RE.test(name)) {
        if (count >= LSP_PROJ_SCAN_CAP) { capped = true; break; }
        if (LSP_proj_index_file(full) !== "") count++;
      }
    }
  }
  return { count: count, capped: capped };
}
// scan a list of workspace folder fs-paths (from initialize params). Logs a
// summary (and a warning if the cap was hit).
function LSP_proj_scan_workspace(roots) {
  let total = 0, capped = false;
  for (const r of roots) {
    if (!r) continue;
    const res = LSP_proj_scan_dir(r);
    total += res.count; capped = capped || res.capped;
  }
  LSP_log('project index: scanned ' + total + ' source file(s), ' +
          LSP_proj_fwd.size + ' with staload edge(s), ' +
          LSP_proj_rev.size + ' staloaded target(s)' +
          (capped ? ' [CAPPED at ' + LSP_PROJ_SCAN_CAP + ' — large workspace; ' +
                    'unscanned files index lazily on watch events]' : ''));
  try {
    process.stderr.write('[xats-lsp-resident] project-index: files=' + total +
      ' fwd=' + LSP_proj_fwd.size + ' rev=' + LSP_proj_rev.size +
      (capped ? ' capped=1' : '') + '\n');
  } catch (e) {}
}
// extract workspace-folder fs-paths from initialize params (workspaceFolders or
// the single rootUri / rootPath fallback).
function LSP_workspace_roots(params) {
  const roots = [];
  const seen = new Set();
  function addUri(u) {
    if (!u) return;
    const p = LSP_norm(vscode_url_to_path(u));
    if (p !== "" && !seen.has(p)) { seen.add(p); roots.push(p); }
  }
  if (params && Array.isArray(params.workspaceFolders)) {
    for (const wf of params.workspaceFolders) { if (wf && wf.uri) addUri(wf.uri); }
  }
  if (roots.length === 0 && params) {
    if (params.rootUri) addUri(params.rootUri);
    else if (params.rootPath) {
      const p = LSP_norm(params.rootPath);
      if (p !== "" && !seen.has(p)) { seen.add(p); roots.push(p); }
    }
  }
  return roots;
}
//
////////////////////////////////////////////////////////////////////////.
// ---- string-buffer FILR (capture a printed type as a JS string) ------ //
//
function LSP_strbuf_new() {
  return { buf: "", write: function (s) { this.buf += s; } };
}
function LSP_strbuf_get(fb) { return fb.buf; }
//
// integer-label / xtv-stamp -> string (for the faithful s2typ printer).
function TYPRINT_int2str(n)   { return String(n|0); }
function TYPRINT_stamp2str(s) { return String(s); }
//
////////////////////////////////////////////////////////////////////////.
// ---- friendly type-name map (grounded in prelude/basics0.sats heads) - //
//
// Used ONLY for the leaf head-name renderer in type-MISMATCH messages (the
// faithful s2typ printer resolves int widths etc. on the ATS side already, so
// hover strings pass through unchanged). Keys are real head names.
const LSP_TYPENAME = {
  "gint_type": "int", "bool_type": "bool", "char_type": "char",
  "gflt_type": "double", "xats_void_t": "void", "string_i0_tx": "string",
  "the_s2exp_strn0": "string", "the_s2exp_sint0": "int",
  "the_s2exp_uint0": "uint", "the_s2exp_slint0": "lint",
  "the_s2exp_ulint0": "ulint", "the_s2exp_sllint0": "llint",
  "the_s2exp_ullint0": "ullint", "the_s2exp_sflt0": "float",
  "the_s2exp_dflt0": "double", "the_s2exp_list0": "list",
  "the_s2exp_optn0": "optn", "the_s2exp_lazy0": "lazy",
  "the_s2exp_p1": "ptr", "the_s2exp_p2": "p2tr",
  "the_s2exp_bool0": "bool", "the_s2exp_char0": "char",
  "the_s2exp_void": "void", "strn": "string",
  "xats_sint_t": "int", "xats_uint_t": "uint",
  "xats_slint_t": "lint", "xats_ulint_t": "ulint",
  "xats_ssize_t": "ssize", "xats_usize_t": "usize",
  "xats_sllint_t": "llint", "xats_ullint_t": "ullint",
  "xats_strn_t": "string", "xats_bool_t": "bool",
  "xats_char_t": "char", "xats_dflt_t": "double",
  "p1tr_tbox": "ptr", "p2tr_tbox": "p2tr",
  "list_t0_i0_tx": "list", "list_vt_i0_vx": "list_vt",
  "optn_t0_i0_tx": "optn", "optn_vt_i0_vx": "optn_vt",
  "lazy_t0_tx": "lazy", "lazy_vt_vx": "lazy_vt"
};
function LSP_friendly(msg) {
  return String(msg).replace(/`([A-Za-z_][A-Za-z0-9_$]*)`/g, function (m, nm) {
    return LSP_TYPENAME.hasOwnProperty(nm) ? ("`" + LSP_TYPENAME[nm] + "`") : m;
  });
}
function LSP_typestr(s) {
  return String(s).replace(/[A-Za-z_][A-Za-z0-9_$]*/g, function (nm) {
    return LSP_TYPENAME.hasOwnProperty(nm) ? LSP_TYPENAME[nm] : nm;
  });
}
//
////////////////////////////////////////////////////////////////////////.
// ---- HARVEST accumulators -> a per-uri in-memory index --------------- //
//
// During one in-process validation, the ATS3 traversal calls diag_push /
// hover_push / def_push. They append to these "current" arrays; when the
// validation finishes, vscode_initialize's textValidator snapshots them into
// LSP_index[uri] (deduped + LSP-shaped) for onHover/onDefinition to read.
//
let LSP_cur_diags  = [];
let LSP_cur_hovers = [];
let LSP_cur_defs   = [];
// uri -> { hovers:[{range,type,kind}], definitions:[{useRange,defUri,defRange,
//          entity,[typeDefUri,typeDefRange]}] }
const LSP_index = new Map();
//
// the path the validator is currently checking + the uri it maps to, so we can
// remap in-file def locations (labelled with the real on-disk path) back to the
// document uri (they are identical here since we read the saved file, but a
// def-path may be the canonical absolute path while uri is percent-encoded).
let LSP_cur_path = null;
let LSP_cur_uri  = null;
//
function LSP_diag_push(l0, c0, l1, c1, code, message) {
  LSP_cur_diags.push({
    l0: l0|0, c0: c0|0, l1: l1|0, c1: c1|0,
    code: String(code), message: LSP_friendly(message)
  });
}
function LSP_hover_push(l0, c0, l1, c1, typ, kind) {
  // The ATS-side faithful printer already emits resolved surface syntax; pass
  // it through verbatim (no head-name remap, which would only corrupt it).
  const t = String(typ);
  if (t === "") return;
  LSP_cur_hovers.push({
    l0: l0|0, c0: c0|0, l1: l1|0, c1: c1|0, type: t, kind: String(kind)
  });
}
function LSP_def_push(ul0, uc0, ul1, uc1, defpath,
                      dl0, dc0, dl1, dc1, entity, hastdef, tdpath,
                      tl0, tc0, tl1, tc1) {
  const defUri = LSP_path2uri(defpath);
  if (defUri === "") return;
  const d = {
    ul0: ul0|0, uc0: uc0|0, ul1: ul1|0, uc1: uc1|0,
    defUri: defUri,
    dl0: dl0|0, dc0: dc0|0, dl1: dl1|0, dc1: dc1|0,
    entity: String(entity)
  };
  if ((hastdef|0) === 1) {
    const tdUri = LSP_path2uri(tdpath);
    if (tdUri !== "") {
      d.typeDefUri = tdUri;
      d.tl0 = tl0|0; d.tc0 = tc0|0; d.tl1 = tl1|0; d.tc1 = tc1|0;
    }
  }
  LSP_cur_defs.push(d);
}
//
// path -> file:// uri (reused from xats_lsp_check.cats). When the def path is
// the very file under check, remap to the document's own uri so within-file
// go-to-def lands in the open document.
function LSP_path2uri(p) {
  let s = String(p || "");
  if (s === "") return "";
  if (s.startsWith("file://")) return s;
  if (!s.startsWith("/")) {
    try { s = LSP_path.resolve(s); } catch (e) { /* keep raw */ }
  }
  // remap the current source path back to the document uri (identity remap).
  if (LSP_cur_path && LSP_cur_uri) {
    try { if (LSP_path.resolve(s) === LSP_path.resolve(LSP_cur_path)) return LSP_cur_uri; }
    catch (e) {}
  }
  const enc = s.split('/').map(encodeURIComponent).join('/');
  return "file://" + enc;
}
//
////////////////////////////////////////////////////////////////////////.
// ---- dedup (Decision D6) + LSP shaping (reused) ---------------------- //
//
function LSP_posLE(la, ca, lb, cb) { return (la < lb) || (la === lb && ca <= cb); }
function LSP_rank(code) {
  switch (code) {
    case "type-mismatch": return 5;
    case "unbound-identifier": return 5;
    case "unresolved-template": return 4;
    case "pattern-error": return 3;
    case "unknown": return 2;
    case "decl-error": return 1;
    default: return 2;
  }
}
function LSP_dedup_diags(diags) {
  let xs = diags.filter(d => d.l0 >= 0 && d.c0 >= 0);
  const best = new Map();
  for (const d of xs) {
    const key = d.l0 + ":" + d.c0;
    const cur = best.get(key);
    if (cur === undefined) { best.set(key, d); continue; }
    const dEnd = d.l1 * 1000000 + d.c1;
    const cEnd = cur.l1 * 1000000 + cur.c1;
    if (dEnd < cEnd) best.set(key, d);
    else if (dEnd === cEnd && LSP_rank(d.code) > LSP_rank(cur.code)) best.set(key, d);
  }
  xs = Array.from(best.values());
  function overlap(a, b) {
    return LSP_posLE(a.l0, a.c0, b.l1, b.c1) && LSP_posLE(b.l0, b.c0, a.l1, a.c1);
  }
  const kept = xs.filter(function (d) {
    for (const e of xs) {
      if (e === d) continue;
      const inside = LSP_posLE(d.l0, d.c0, e.l0, e.c0) && LSP_posLE(e.l1, e.c1, d.l1, d.c1);
      const strictly = inside &&
        !(e.l0 === d.l0 && e.c0 === d.c0 && e.l1 === d.l1 && e.c1 === d.c1);
      if (strictly) return false;
      if (d.code === "decl-error" && e.code !== "decl-error" &&
          overlap(d, e) && LSP_rank(e.code) > LSP_rank(d.code)) return false;
    }
    return true;
  });
  return kept.sort((a, b) =>
    (a.l0 - b.l0) || (a.c0 - b.c0) || (a.l1 - b.l1) || (a.c1 - b.c1));
}
function LSP_jsrange(l0, c0, l1, c1) {
  return { start: { line: l0, character: c0 }, end: { line: l1, character: c1 } };
}
function LSP_dedup_hovers(hs) {
  const seen = new Set(); const out = [];
  for (const h of hs) {
    if (h.l0 < 0 || h.c0 < 0) continue;
    if (h.l1 < h.l0 || (h.l1 === h.l0 && h.c1 < h.c0)) continue;
    const key = h.l0+":"+h.c0+":"+h.l1+":"+h.c1+":"+h.kind+":"+h.type;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ range: LSP_jsrange(h.l0, h.c0, h.l1, h.c1), type: h.type, kind: h.kind });
  }
  return out;
}
function LSP_dedup_defs(ds) {
  const seen = new Set(); const out = [];
  for (const d of ds) {
    if (d.ul0 < 0 || d.uc0 < 0) continue;
    if (d.dl0 < 0 || d.dc0 < 0) continue;
    const key = d.ul0+":"+d.uc0+":"+d.ul1+":"+d.uc1+":"+d.defUri+":"+
                d.dl0+":"+d.dc0+":"+d.dl1+":"+d.dc1+":"+d.entity;
    if (seen.has(key)) continue;
    seen.add(key);
    const o = {
      useRange: LSP_jsrange(d.ul0, d.uc0, d.ul1, d.uc1),
      defUri: d.defUri,
      defRange: LSP_jsrange(d.dl0, d.dc0, d.dl1, d.dc1),
      entity: d.entity
    };
    if (d.typeDefUri) {
      o.typeDefUri = d.typeDefUri;
      o.typeDefRange = LSP_jsrange(d.tl0, d.tc0, d.tl1, d.tc1);
    }
    out.push(o);
  }
  return out;
}
//
// build the LSP Diagnostic[] from the current diag accumulator (deduped).
function LSP_current_lsp_diagnostics() {
  return LSP_dedup_diags(LSP_cur_diags).map(d => ({
    range: LSP_jsrange(d.l0, d.c0, d.l1, d.c1),
    severity: 1, code: d.code, message: d.message, source: "ats3"
  }));
}
//
////////////////////////////////////////////////////////////////////////.
// ---- hover / definition lookup over the per-uri index ---------------- //
//
function LSP_pos_ge(a, b) { return (a.line !== b.line) ? a.line > b.line : a.character >= b.character; }
function LSP_pos_le(a, b) { return (a.line !== b.line) ? a.line < b.line : a.character <= b.character; }
function LSP_range_contains(r, pos) {
  if (!r || !r.start || !r.end) return false;
  return LSP_pos_ge(pos, r.start) && LSP_pos_le(pos, r.end);
}
function LSP_range_span(r) {
  return (r.end.line - r.start.line) * 1000000 + (r.end.character - r.start.character);
}
function LSP_innermost(entries, rangeOf, pos) {
  let bestIdx = -1, bestSpan = Infinity;
  for (let i = 0; i < entries.length; i++) {
    const r = rangeOf(entries[i]);
    if (!LSP_range_contains(r, pos)) continue;
    const span = LSP_range_span(r);
    if (span < bestSpan) { bestSpan = span; bestIdx = i; }
  }
  return bestIdx;
}
function LSP_build_hover(uri, line, char) {
  const idx = LSP_index.get(uri);
  if (!idx) return null;
  const hs = idx.hovers || [];
  const pos = { line: line|0, character: char|0 };
  const i = LSP_innermost(hs, h => h.range, pos);
  if (i < 0) return null;
  const h = hs[i];
  return { contents: { kind: 'markdown', value: '```ats\n' + h.type + '\n```' }, range: h.range };
}
function LSP_build_definition(uri, line, char) {
  const idx = LSP_index.get(uri);
  if (!idx) return null;
  const ds = idx.definitions || [];
  const pos = { line: line|0, character: char|0 };
  const i = LSP_innermost(ds, d => d.useRange, pos);
  if (i < 0) return null;
  const d = ds[i];
  if (!d.defUri || !d.defRange) return null;
  return { uri: d.defUri, range: d.defRange };
}
function LSP_build_type_definition(uri, line, char) {
  const idx = LSP_index.get(uri);
  if (!idx) return null;
  const ds = idx.definitions || [];
  const pos = { line: line|0, character: char|0 };
  const i = LSP_innermost(ds, d => d.useRange, pos);
  if (i < 0) return null;
  const d = ds[i];
  if (!d.typeDefUri || !d.typeDefRange) return null;
  return { uri: d.typeDefUri, range: d.typeDefRange };
}
//
////////////////////////////////////////////////////////////////////////.
// ---- the connection loop (ported from reference vscode_initialize) --- //
//
const LSP_connection = LSP_ls.createConnection(LSP_ls.ProposedFeatures.all);
const LSP_documents  = new LSP_ls.TextDocuments(LSP_text.TextDocument);
//
let LSP_hasConfigurationCapability = false;
let LSP_hasWorkspaceFolderCapability = false;
let LSP_dependencies = new Map();
// R2c: workspace roots captured at onInitialize, scanned at onInitialized.
let LSP_pending_roots = [];
//
function LSP_log(msg) {
  try { LSP_connection.console.log('[xats-lsp-resident] ' + String(msg)); } catch (e) {}
}
//
function vscode_initialize(validator, pruner, reloadPreludeFn, evictStampFn) {
  // run one in-process validation for a document, snapshot the index, publish.
  function textValidator(textDocument) {
    const uri = textDocument.uri;
    const t0 = Date.now();
    // reset the per-check accumulators + remap context.
    LSP_cur_diags = []; LSP_cur_hovers = []; LSP_cur_defs = [];
    LSP_cur_uri = uri;
    LSP_cur_path = vscode_url_to_path(uri);
    // R2c: index this doc's own directives into the project graph (covers a file
    // opened before/outside the workspace scan, and refreshes its edges from the
    // live buffer). Cheap; keeps the project reverse graph complete + current.
    try { LSP_proj_index_file(LSP_cur_path, textDocument.getText()); } catch (e) {}
    const diagnostics = [];   // the `ds` handle handed to the ATS3 validator
    try {
      validator(LSP_dependencies, diagnostics, uri);
    } catch (e) {
      LSP_log('validator threw: ' + (e && e.stack ? e.stack : e));
    }
    // snapshot harvested hover/def index for onHover/onDefinition.
    LSP_index.set(uri, {
      hovers: LSP_dedup_hovers(LSP_cur_hovers),
      definitions: LSP_dedup_defs(LSP_cur_defs)
    });
    const lspDiags = LSP_current_lsp_diagnostics();
    LSP_connection.sendDiagnostics({ uri: uri, diagnostics: lspDiags });
    const dt = Date.now() - t0;
    const nstat = LSP_stat_count_reset();
    // structured stderr line the smoke harness parses for latency.
    try {
      process.stderr.write('[xats-lsp-metric] check uri=' + uri +
        ' ms=' + dt + ' diags=' + lspDiags.length +
        ' hovers=' + (LSP_index.get(uri).hovers.length) +
        ' defs=' + (LSP_index.get(uri).definitions.length) +
        ' stats=' + nstat + '\n');
    } catch (e) {}
    LSP_cur_uri = null; LSP_cur_path = null;
  }

  // ---- prelude reload orchestration (the "workspace IS the prelude" case) ---
  //
  // On didSave of a file resolving UNDER $XATSHOME (reusing the R2a path-prefix
  // detection JS_path_is_prelude), the normal validate/prune is WRONG: that file
  // is in the global prelude envs (load-once), and env_reset cannot evict it. The
  // only correct refresh is to reload the prelude IN-PROCESS:
  //   (1) reloadPreludeFn() -> xglobal_reset() + replay the startup prelude-load +
  //       flag sequence + re-take the prelude snapshot (all on the ATS side), so
  //       the EDITED prelude is reloaded fresh from disk;
  //   (2) clear the server-side caches built against the OLD prelude — the per-uri
  //       hover/def index, the reverse + forward depgraphs, and the workspace
  //       signature map — so nothing stale survives the reload;
  //   (3) re-validate EVERY open document, republishing fresh diagnostics and
  //       rebuilding their indices against the reloaded prelude.
  // Triggered on didSave (not didChange) because the loaders read from DISK.
  function reloadPreludeAndRevalidate(savedUri) {
    LSP_log('reload_prelude: $XATSHOME file saved (' + savedUri +
            ') -> reloading prelude in-process + re-validating all open docs');
    try { process.stderr.write('[xats-lsp-resident] reload_prelude: ' + savedUri + '\n'); } catch (e) {}
    // (1) reset + reload the prelude (ATS side).
    try {
      reloadPreludeFn();
    } catch (e) {
      LSP_log('reload_prelude threw: ' + (e && e.stack ? e.stack : e));
      return;
    }
    // (2) clear server-side caches built against the OLD prelude. The freshly
    //     reloaded prelude files get NEW stamps, so the old stamp-keyed maps
    //     (signatures, path->stamp) are stale and must be dropped. The PROJECT
    //     index is path-keyed (stamp-independent) and stays valid across a
    //     reload, so we keep it — only the stamp bindings reset.
    LSP_index.clear();
    LSP_dependencies.clear();
    LSP_fwd.clear();
    LSP_signatures.clear();
    LSP_path2stamp.clear();
    // (3) re-validate every open document against the reloaded prelude.
    const docs = LSP_documents.all();
    LSP_log('reload_prelude: re-validating ' + docs.length + ' open doc(s)');
    for (const doc of docs) { textValidator(doc); }
  }

  // ---- R2b: workspace/didChangeWatchedFiles (eager eviction + cascade) -----
  //
  // The client already declares file watchers (clientOptions.synchronize.
  // fileEvents for **/*.{sats,hats,dats}), so it sends this notification on every
  // in-workspace external edit / create / delete WITHOUT server registration.
  // This is the eager trigger that complements R2a's lazy mtime pre-check: it
  // evicts NOW, the moment the change lands, rather than waiting for the next
  // check to stat the closure.
  //
  // FileChangeType: 1=Created, 2=Changed, 3=Deleted.
  function handleWatchedFileChange(uri, changeType) {
    const fpath = vscode_url_to_path(uri);
    const npath = LSP_norm(fpath);
    if (npath === "") return;
    // skip the prelude / $XATSHOME tree: those files are immutable for the
    // session (the reloadPrelude path handles compiler-dev edits to them).
    if (JS_path_is_prelude(npath)) return;

    // (1) keep the PROJECT index current for the changed file's own edges, so
    //     the cascade below reflects the new directive set.
    if (changeType === 3 /*Deleted*/) {
      LSP_proj_remove_file(npath);
    } else {
      LSP_proj_index_file(npath);                 // Created or Changed: re-parse
    }

    // (2) compute the COMPLETE set of affected files: the changed file itself
    //     plus its transitive PROJECT-reverse closure (every dependent, opened
    //     or not). The project index is what makes this complete vs the
    //     checked-files depgraph.
    const affected = LSP_proj_rev_closure(npath);
    affected.add(npath);

    // (3) eagerly EVICT each affected file from the compiler caches by its stamp
    //     (path->stamp index). Also drop the changed file's R2a signature so the
    //     next check re-stats it fresh. Never-checked files have no stamp -> the
    //     eviction is a harmless no-op (they were never cached).
    let evicted = 0;
    for (const p of affected) {
      const st = LSP_path2stamp.get(p);
      if (st !== undefined) {
        try { evictStampFn(parseInt(st, 10) >>> 0); evicted++; } catch (e) {}
      }
    }
    // drop the changed file's own signature + path->stamp so a later check
    // re-stats it (and, if deleted, does not think a stale cache is current).
    {
      const st = LSP_path2stamp.get(npath);
      if (st !== undefined) { LSP_signatures.delete(st); }
      if (changeType === 3) { LSP_path2stamp.delete(npath); }
    }

    // (4) re-validate every AFFECTED OPEN document so its diagnostics refresh
    //     immediately (no need to wait for the user to touch it). An open doc is
    //     affected iff it is in `affected` (the changed file or a dependent).
    let revalidated = 0;
    for (const doc of LSP_documents.all()) {
      const dp = LSP_norm(vscode_url_to_path(doc.uri));
      if (dp !== "" && affected.has(dp)) { textValidator(doc); revalidated++; }
    }
    try {
      process.stderr.write('[xats-lsp-resident] watched ' +
        (changeType === 1 ? 'create' : changeType === 3 ? 'delete' : 'change') +
        ' ' + npath + ' -> affected=' + affected.size +
        ' evicted=' + evicted + ' revalidated=' + revalidated + '\n');
    } catch (e) {}
  }

  // Prefer the typed helper; fall back to the raw notification name. Both deliver
  // { changes: [{uri, type}, ...] }.
  function onWatchedFiles(change) {
    try {
      const changes = (change && change.changes) || [];
      for (const c of changes) { handleWatchedFileChange(c.uri, c.type); }
    } catch (e) {
      LSP_log('didChangeWatchedFiles threw: ' + (e && e.stack ? e.stack : e));
    }
  }
  if (typeof LSP_connection.onDidChangeWatchedFiles === 'function') {
    LSP_connection.onDidChangeWatchedFiles(onWatchedFiles);
  } else {
    LSP_connection.onNotification('workspace/didChangeWatchedFiles', onWatchedFiles);
  }

  LSP_connection.onInitialize((params) => {
    const capabilities = params.capabilities;
    LSP_hasConfigurationCapability = !!(
      capabilities.workspace && !!capabilities.workspace.configuration);
    LSP_hasWorkspaceFolderCapability = !!(
      capabilities.workspace && !!capabilities.workspace.workspaceFolders);
    // R2c: stash the workspace roots; scan AFTER we reply (onInitialized) so a
    // big workspace's scan does not delay the initialize handshake.
    LSP_pending_roots = LSP_workspace_roots(params);
    return {
      capabilities: {
        // Object form (not a bare sync-kind) so the client also sends
        // textDocument/didSave -- the resident server validates on open/save,
        // and a bare TextDocumentSyncKind would suppress save notifications.
        textDocumentSync: {
          openClose: true,
          change: LSP_ls.TextDocumentSyncKind.Incremental,
          save: { includeText: false },
        },
        hoverProvider: true,
        definitionProvider: true,
        typeDefinitionProvider: true,
      },
      serverInfo: { name: 'xats-lsp-resident', version: '0.1.0' }
    };
  });

  LSP_connection.onInitialized(() => {
    if (LSP_hasConfigurationCapability) {
      LSP_connection.client.register(LSP_ls.DidChangeConfigurationNotification.type, undefined);
    }
    // R2c: build the whole-project staload index now (after the handshake).
    // Deferred via setImmediate so it never blocks the connection from going
    // live; a capped, bounded synchronous scan then runs off the event loop.
    if (LSP_pending_roots && LSP_pending_roots.length > 0) {
      const roots = LSP_pending_roots; LSP_pending_roots = [];
      setImmediate(() => {
        try { LSP_proj_scan_workspace(roots); }
        catch (e) { LSP_log('project scan threw: ' + (e && e.stack ? e.stack : e)); }
      });
    }
  });

  LSP_documents.onDidOpen(change => { textValidator(change.document); });
  // NOTE: didSave is handled by a RAW connection.onDidSaveTextDocument handler
  // registered AFTER LSP_documents.listen (below), NOT by LSP_documents.onDidSave.
  // Reason: TextDocuments.onDidSave only fires for OPENED docs, but a $XATSHOME
  // prelude file is typically saved WITHOUT being open in the editor; we must
  // still catch that save to trigger the in-process prelude reload. The raw
  // handler dispatches: $XATSHOME -> reload prelude; otherwise -> validate the
  // (opened) doc exactly as before.
  // didChange: prune only (evict the file + dependents). Cheap; the warm
  // recheck happens on the next save/open.
  LSP_documents.onDidChangeContent(change => {
    try { pruner(LSP_dependencies, change.document.uri); }
    catch (e) { LSP_log('pruner threw: ' + (e && e.stack ? e.stack : e)); }
  });
  LSP_documents.onDidClose(change => {
    LSP_index.delete(change.document.uri);
    LSP_connection.sendDiagnostics({ uri: change.document.uri, diagnostics: [] });
  });

  LSP_connection.onHover(params => {
    try {
      return LSP_build_hover(params.textDocument.uri, params.position.line, params.position.character);
    } catch (e) { LSP_log('onHover threw: ' + e); return null; }
  });
  LSP_connection.onDefinition(params => {
    try {
      return LSP_build_definition(params.textDocument.uri, params.position.line, params.position.character);
    } catch (e) { LSP_log('onDefinition threw: ' + e); return null; }
  });
  if (typeof LSP_connection.onTypeDefinition === 'function') {
    LSP_connection.onTypeDefinition(params => {
      try {
        return LSP_build_type_definition(params.textDocument.uri, params.position.line, params.position.character);
      } catch (e) { LSP_log('onTypeDefinition threw: ' + e); return null; }
    });
  }

  LSP_documents.listen(LSP_connection);

  // RAW didSave handler — registered AFTER LSP_documents.listen so it REPLACES
  // the TextDocuments-internal onDidSaveTextDocument (vscode-jsonrpc keeps one
  // handler per notification method). This is deliberate: TextDocuments only
  // dispatches saves for OPENED docs, but a $XATSHOME prelude file is usually
  // saved while NOT open in the editor, and we must still catch it. The handler
  // dispatches:
  //   * path under $XATSHOME  -> reloadPreludeAndRevalidate (in-process reload);
  //   * otherwise             -> validate the opened doc (the normal R1 path).
  LSP_connection.onDidSaveTextDocument(params => {
    try {
      const uri = params.textDocument.uri;
      const fpath = vscode_url_to_path(uri);
      if (JS_path_is_prelude(fpath)) {
        reloadPreludeAndRevalidate(uri);
        return;
      }
      // normal save: re-validate the opened doc (R1 + R2a), as before.
      const doc = LSP_documents.get(uri);
      if (doc !== undefined) { textValidator(doc); }
    } catch (e) {
      LSP_log('onDidSaveTextDocument threw: ' + (e && e.stack ? e.stack : e));
    }
  });

  LSP_connection.listen();
  try { process.stderr.write('[xats-lsp-resident] listening on stdio (resident, in-process)\n'); } catch (e) {}
}
//
////////////////////////////////////////////////////////////////////////.
// end of [language-server/server/resident/CATS/xats_lsp_resident.cats]
////////////////////////////////////////////////////////////////////////.
