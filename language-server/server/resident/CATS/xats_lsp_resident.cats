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
// ---- SEMANTIC TOKENS legend (advertised in onInitialize) ------------- //
//
// AST-based token classification the regex TextMate grammar cannot do: a name
// is resolved (by the typed AST) to a variable / function / data-constructor /
// type. The ATS3 harvest emits a token-TYPE INDEX into LSP_TOKEN_TYPES and a
// MODIFIER bitset into LSP_TOKEN_MODS; the indices/bit positions below MUST stay
// in sync with the #define'd TT_*/TM_* constants in the DATS.
//
//   types: namespace=0 type=1 typeParameter=2 parameter=3 variable=4
//          property=5 function=6 enumMember=7 keyword=8 string=9 number=10
//          operator=11 comment=12
//   mods : declaration=1<<0 definition=1<<1 readonly=1<<2 static=1<<3
//          defaultLibrary=1<<4
//
const LSP_TOKEN_TYPES = [
  'namespace', 'type', 'typeParameter', 'parameter', 'variable', 'property',
  'function', 'enumMember', 'keyword', 'string', 'number', 'operator', 'comment'
];
const LSP_TOKEN_MODS = [
  'declaration', 'definition', 'readonly', 'static', 'defaultLibrary'
];
// defaultLibrary bit: ORed in (in JS) when the entity's def-path is under
// $XATSHOME (a prelude / compiler-tree const). KEEP = index of 'defaultLibrary'.
const LSP_TOKEN_MOD_DEFAULTLIB = (1 << LSP_TOKEN_MODS.indexOf('defaultLibrary'));
function LSP_semantic_tokens_legend() {
  return { tokenTypes: LSP_TOKEN_TYPES, tokenModifiers: LSP_TOKEN_MODS };
}
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
//
////////////////////////////////////////////////////////////////////////.
// ---- WS-5 workspace symbols: a TEXTUAL project symbol index --------- //
//
// workspace/symbol must answer over the WHOLE project, including files never
// opened/type-checked. Rather than type-check everything (expensive), we extract
// TOP-LEVEL declaration names TEXTUALLY during the same one-pass project scan
// that builds the staload graph — cheap, resilient to non-compiling files, and
// decoupled from the typecheck pipeline. (Opened files still get AST-accurate
// document symbols; this index is the coarse project-wide name map for Cmd-T.)
//
// normPath -> [{ name, kind, line, char, endChar }]  (0-based, UTF-16 columns —
// computed directly off the JS string, so already LSP-correct).
const LSP_ws_symbols_by_file = new Map();
// top-level decl matcher: optional leading #/extern, a decl keyword, then a name.
const LSP_WS_SYM_RE =
  /(?:^|\n)[ \t]*(?:#?extern[ \t]+)?(#?(?:fun|fnx|fn|prfn|prfun|praxi|castfn|macdef|val[-+]?|prval|var|datatype|datavtype|dataprop|datasort|typedef|sexpdef|sortdef|abstype|abst@ype|abst0ype|absvtype|absprop|abstbox|abstflat|stacst))[ \t]+([A-Za-z_][A-Za-z0-9_$']*)/g;
function LSP_ws_kind(kw) {
  const k = kw.replace(/^#/, '');
  if (/^(fun|fnx|fn|prfn|prfun|praxi|castfn|macdef)$/.test(k)) return 12;  // Function
  if (/^(val[-+]?|prval)$/.test(k)) return 14;                             // Constant
  if (k === 'var') return 13;                                             // Variable
  if (/^(datatype|datavtype|dataprop|datasort)$/.test(k)) return 10;       // Enum
  if (/^(typedef|sexpdef|sortdef)$/.test(k)) return 11;                    // Interface
  if (/^(abstype|abst@ype|abst0ype|absvtype|absprop|abstbox|abstflat)$/.test(k)) return 5; // Class
  if (k === 'stacst') return 26;                                          // TypeParameter
  return 13;
}
function LSP_line_starts(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) starts.push(i + 1);
  return starts;
}
function LSP_off_to_pos(starts, off) {
  let lo = 0, hi = starts.length - 1, ans = 0;
  while (lo <= hi) { const mid = (lo + hi) >> 1; if (starts[mid] <= off) { ans = mid; lo = mid + 1; } else hi = mid - 1; }
  return { line: ans, character: off - starts[ans] };
}
function LSP_extract_ws_symbols(text) {
  const out = [];
  const starts = LSP_line_starts(text);
  LSP_WS_SYM_RE.lastIndex = 0;
  let m;
  while ((m = LSP_WS_SYM_RE.exec(text)) !== null) {
    const name = m[2];
    if (!name) continue;
    const nameStart = m.index + m[0].length - name.length;   // m[0] ends at the name
    const p = LSP_off_to_pos(starts, nameStart);
    out.push({ name: name, kind: LSP_ws_kind(m[1]),
               line: p.line, char: p.character, endChar: p.character + name.length });
  }
  return out;
}
// case-insensitive subsequence ("fuzzy") match, the conventional Cmd-T behavior.
function LSP_ws_fuzzy(q, name) {
  if (!q) return true;
  q = q.toLowerCase(); name = name.toLowerCase();
  let i = 0;
  for (let j = 0; j < name.length && i < q.length; j++) if (name[j] === q[i]) i++;
  return i === q.length;
}
function LSP_build_workspace_symbols(query) {
  const out = [];
  const CAP = 1000;                                  // bound a broad query
  for (const [n, syms] of LSP_ws_symbols_by_file) {
    const uri = LSP_path2uri(n);
    if (uri === "") continue;
    for (const s of syms) {
      if (!LSP_ws_fuzzy(query, s.name)) continue;
      out.push({
        name: s.name, kind: s.kind | 0,
        location: { uri: uri, range: LSP_jsrange(s.line, s.char, s.line, s.endChar) },
        containerName: ""
      });
      if (out.length >= CAP) return out;
    }
  }
  return out;
}
//
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
  // WS-5: (re)build this file's top-level symbol list for workspace/symbol.
  const syms = LSP_extract_ws_symbols(text);
  if (syms.length > 0) LSP_ws_symbols_by_file.set(n, syms);
  else LSP_ws_symbols_by_file.delete(n);
  LSP_proj_indexed.add(n);
  return n;
}
// a file was DELETED: drop its forward edges (its reverse edges — who staloads it
// — stay, harmlessly pointing at a now-missing file; they re-resolve if recreated).
function LSP_proj_remove_file(filePath) {
  const n = LSP_norm(filePath);
  if (n === "") return;
  LSP_proj_unlink(n);
  LSP_ws_symbols_by_file.delete(n);              // WS-5: drop its symbols too
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
// ---- UTF-16 column conversion (non-ASCII correctness) ---------------- //
//
// The harvest emits `character` = the BYTE column (ncol; primer §5: ncol counts
// UTF-8 bytes). LSP wants the UTF-16 code-unit column for the line. They are
// EQUAL only when the line's prefix is pure ASCII. For a line with a multi-byte
// UTF-8 glyph (é = 2 bytes / 1 unit, 😀 = 4 bytes / 2 units) the byte column is
// larger than the UTF-16 column, so ranges drift right of the real token. We
// convert per emitted (line, byteCol): take the source line's bytes [0,byteCol),
// decode as UTF-8, count UTF-16 code units (a codepoint >= U+10000 = 2 units).
//
// Efficiency: we never re-decode the whole file per position. We build a per-LINE
// byte->utf16 PREFIX (a Uint32Array, lazily, only for lines that contain a
// non-ASCII byte) and cache it, keyed by the source text identity; a pure-ASCII
// line takes the fast path (byteCol === utf16Col, no array built).
//
// Source of the lines: the text of the file currently being CHECKED (set in
// LSP_cur_text by the validator — the saved file's text or the unsaved buffer).
// Def TARGET ranges in OTHER files are converted best-effort by lazily reading
// that file's bytes from disk (cached); if unreadable, the byte column is left
// as-is (noted in the report).
//
const LSP_u16_dec = new TextDecoder('utf-8', { fatal: false });
//
// A converter over one source text: splits the BYTES into lines (on \n, keeping
// CR out of the count by treating it as an ordinary byte — the column model
// counts every byte incl. CR, matching the lexer which advances ncol per byte),
// and converts (line, byteCol) -> utf16Col. Lazily builds a per-line prefix only
// for non-ASCII lines; ASCII lines are byteCol-identical.
function LSP_u16_make(text) {
  // byte view of the whole text, then per-line byte slices (Buffer/Uint8Array).
  const bytes = Buffer.from(String(text == null ? "" : text), 'utf8');
  // line start byte offsets. A line ends at '\n' (0x0a); the lexer increments
  // nrow on '\n' and resets ncol to 0, so byte columns are RELATIVE to the byte
  // right after the previous '\n'. We therefore index lines by those starts.
  const starts = [0];
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] === 0x0a) starts.push(i + 1);
  }
  // per-line cache: index -> { ascii:true } | { ascii:false, pref:Uint32Array }
  //   pref[k] = number of UTF-16 code units in this line's bytes [0,k).
  const cache = new Map();
  function lineInfo(line) {
    let info = cache.get(line);
    if (info !== undefined) return info;
    const s = starts[line];
    if (s === undefined) { info = { ascii: true, len: 0 }; cache.set(line, info); return info; }
    const e = (line + 1 < starts.length) ? (starts[line + 1] - 1 /*drop the \n*/) : bytes.length;
    let nonAscii = false;
    for (let i = s; i < e; i++) { if (bytes[i] >= 0x80) { nonAscii = true; break; } }
    if (!nonAscii) { info = { ascii: true, len: e - s }; cache.set(line, info); return info; }
    // build the byte->utf16 prefix for this (non-ASCII) line.
    const n = e - s;
    const pref = new Uint32Array(n + 1);
    let units = 0, i = s, k = 0;
    while (i < e) {
      const b = bytes[i];
      let seq = 1, cp = 0;
      if (b < 0x80)        { seq = 1; cp = b; }
      else if (b < 0xE0)   { seq = 2; cp = b & 0x1f; }
      else if (b < 0xF0)   { seq = 3; cp = b & 0x0f; }
      else                 { seq = 4; cp = b & 0x07; }
      // assemble the codepoint (defensively clamp on truncated/invalid seq).
      let valid = (i + seq <= e);
      if (valid) {
        for (let j = 1; j < seq; j++) {
          const cb = bytes[i + j];
          if ((cb & 0xc0) !== 0x80) { valid = false; break; }
          cp = (cp << 6) | (cb & 0x3f);
        }
      }
      if (!valid) { seq = 1; cp = b; }   // treat a bad byte as 1 unit (replacement)
      const u = (cp >= 0x10000) ? 2 : 1; // astral plane -> surrogate pair
      // fill the prefix for the bytes this codepoint spans: each leading-byte
      // position maps to the units-so-far; continuation bytes share the start.
      for (let j = 0; j < seq && (k + j) <= n; j++) pref[k + j] = units;
      units += u;
      k += seq; i += seq;
    }
    pref[Math.min(k, n)] = units;
    // any trailing slots (shouldn't happen) get the final unit count.
    for (let j = k + 1; j <= n; j++) pref[j] = units;
    info = { ascii: false, len: n, pref: pref };
    cache.set(line, info);
    return info;
  }
  return {
    // byteCol -> utf16Col on `line`. ASCII fast path; else prefix lookup.
    conv: function (line, byteCol) {
      const c = byteCol | 0;
      if (c <= 0) return 0;
      const info = lineInfo(line | 0);
      if (info.ascii) return c;                 // pure ASCII: identical
      const pref = info.pref;
      if (c >= pref.length) return pref[pref.length - 1];
      return pref[c];
    }
  };
}
//
// escape hatch: ATS3_LSP_UTF16=0 disables conversion (emit raw byte columns).
// On by default; used for diagnosis + as a kill-switch if a workspace is known
// to be pure ASCII and wants to skip even the (cheap) line-start scan.
const LSP_u16_enabled = (process.env.ATS3_LSP_UTF16 !== '0');
//
// the converter for the file CURRENTLY being checked (its whole source text).
// Rebuilt per check (text changes); cheap (one pass to find line starts; per-line
// prefix only for non-ASCII lines, built lazily on first use of that line).
let LSP_cur_u16 = null;
function LSP_cur_b2u(line, byteCol) {
  return (LSP_u16_enabled && LSP_cur_u16) ? LSP_cur_u16.conv(line, byteCol) : (byteCol | 0);
}
//
// best-effort converter for OTHER files (def targets). Keyed by normalized path;
// lazily reads the file's bytes once and caches a converter. On any failure we
// return the byte column unchanged (best-effort, noted in the report).
const LSP_other_u16 = new Map();
function LSP_other_b2u(path, line, byteCol) {
  const c = byteCol | 0;
  if (!LSP_u16_enabled) return c;
  if (c <= 0) return 0;
  const n = LSP_norm(path);
  if (n === "") return c;
  let conv = LSP_other_u16.get(n);
  if (conv === undefined) {
    try { conv = LSP_u16_make(LSP_fs.readFileSync(n, 'utf8')); }
    catch (e) { conv = null; }            // unreadable -> leave byte col as-is
    LSP_other_u16.set(n, conv);
  }
  return conv ? conv.conv(line, byteCol) : c;
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
let LSP_cur_diags   = [];
let LSP_cur_hovers  = [];
let LSP_cur_defs    = [];
let LSP_cur_tokens  = [];
let LSP_cur_symbols = [];   // WS-5 document symbols (outline)
let LSP_cur_inlays  = [];   // WS-5 inlay hints (inferred val types)
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
// the (already-normalized) path of the file being checked, for the per-range
// "is this range in the current file?" test used to pick the right converter.
let LSP_cur_path_norm = null;
function LSP_def_in_current(defUri) {
  // a def whose uri is the document's own uri (LSP_path2uri remapped it) is in
  // the file being checked -> convert with LSP_cur_u16. Otherwise it lives in
  // another file -> best-effort convert from that file's bytes.
  return (LSP_cur_uri && defUri === LSP_cur_uri);
}
function LSP_diag_push(l0, c0, l1, c1, code, message) {
  // diagnostics are always in the file being checked -> current-file converter.
  LSP_cur_diags.push({
    l0: l0|0, c0: LSP_cur_b2u(l0, c0), l1: l1|0, c1: LSP_cur_b2u(l1, c1),
    code: String(code), message: LSP_friendly(message)
  });
}
function LSP_hover_push(l0, c0, l1, c1, typ, kind) {
  // The ATS-side faithful printer already emits resolved surface syntax; pass
  // it through verbatim (no head-name remap, which would only corrupt it).
  const t = String(typ);
  if (t === "") return;
  // hovers are always in the file being checked -> current-file converter.
  LSP_cur_hovers.push({
    l0: l0|0, c0: LSP_cur_b2u(l0, c0), l1: l1|0, c1: LSP_cur_b2u(l1, c1),
    type: t, kind: String(kind)
  });
}
function LSP_def_push(ul0, uc0, ul1, uc1, defpath,
                      dl0, dc0, dl1, dc1, entity, hastdef, tdpath,
                      tl0, tc0, tl1, tc1) {
  const defUri = LSP_path2uri(defpath);
  if (defUri === "") return;
  // useRange is ALWAYS in the file being checked -> current-file converter.
  // defRange may be in the current file (remapped uri) or another file: convert
  // with the current converter if in-current, else best-effort from defpath.
  let dc0u, dc1u;
  if (LSP_def_in_current(defUri)) {
    dc0u = LSP_cur_b2u(dl0, dc0); dc1u = LSP_cur_b2u(dl1, dc1);
  } else {
    dc0u = LSP_other_b2u(defpath, dl0, dc0); dc1u = LSP_other_b2u(defpath, dl1, dc1);
  }
  const d = {
    ul0: ul0|0, uc0: LSP_cur_b2u(ul0, uc0), ul1: ul1|0, uc1: LSP_cur_b2u(ul1, uc1),
    defUri: defUri,
    dl0: dl0|0, dc0: dc0u, dl1: dl1|0, dc1: dc1u,
    entity: String(entity)
  };
  if ((hastdef|0) === 1) {
    const tdUri = LSP_path2uri(tdpath);
    if (tdUri !== "") {
      d.typeDefUri = tdUri;
      // type-def target is in another file (a type-constant's declaration site);
      // best-effort convert from that file's bytes (or current if it remapped).
      d.tl0 = tl0|0; d.tl1 = tl1|0;
      if (LSP_def_in_current(tdUri)) {
        d.tc0 = LSP_cur_b2u(tl0, tc0); d.tc1 = LSP_cur_b2u(tl1, tc1);
      } else {
        d.tc0 = LSP_other_b2u(tdpath, tl0, tc0); d.tc1 = LSP_other_b2u(tdpath, tl1, tc1);
      }
    }
  }
  LSP_cur_defs.push(d);
}
//
// SEMANTIC TOKENS push. Called by the harvest traversal for each identifier-
// bearing node: its USE-/binding-site span (byte coords; converted to UTF-16
// columns here — semantic tokens are ALWAYS in the file being checked), the
// resolved token-type INDEX, the static modifier bitset, and the entity's
// def-path. If the def-path resolves under $XATSHOME we OR in `defaultLibrary`.
// Drops dummy / out-of-range spans defensively (the encoder requires l>=0,
// c>=0, and a non-empty single-line span).
function LSP_token_push(l0, c0, l1, c1, ttype, tmods, defpath) {
  if (l0 < 0 || c0 < 0) return;
  if ((l0|0) !== (l1|0)) return;          // tokens are single-line by construction
  const cu0 = LSP_cur_b2u(l0, c0);
  const cu1 = LSP_cur_b2u(l1, c1);
  const len = (cu1|0) - (cu0|0);
  if (len <= 0) return;                    // empty / inverted span -> skip
  let mods = tmods|0;
  if (defpath && JS_path_is_prelude(String(defpath))) mods |= LSP_TOKEN_MOD_DEFAULTLIB;
  LSP_cur_tokens.push({ line: l0|0, char: cu0|0, len: len|0, type: ttype|0, mods: mods });
}
//
// WS-5 DOCUMENT SYMBOL push. The name range is ALWAYS in the file being checked
// -> current-file UTF-16 converter. (l0,c0..l1,c1) byte coords; kind is an LSP
// SymbolKind index; container is "" for a top-level symbol.
function LSP_symbol_push(l0, c0, l1, c1, name, kind, container) {
  if (l0 < 0 || c0 < 0) return;
  const nm = String(name);
  if (nm === "") return;
  LSP_cur_symbols.push({
    l0: l0|0, c0: LSP_cur_b2u(l0, c0), l1: l1|0, c1: LSP_cur_b2u(l1, c1),
    name: nm, kind: kind|0, container: String(container || "")
  });
}
//
// WS-5 INLAY HINT push. The position is the END of an inferred binding's name,
// always in the file being checked -> current-file UTF-16 converter.
function LSP_inlay_push(line, col, label, kind) {
  if (line < 0 || col < 0) return;
  const lbl = String(label);
  if (lbl === "") return;
  LSP_cur_inlays.push({
    line: line|0, char: LSP_cur_b2u(line, col), label: lbl, kind: kind|0
  });
}
//
// dedup + sort + LSP delta-encode the accumulated tokens into the flat int
// array of 5-tuples [deltaLine, deltaStartChar, length, tokenType, tokenMods]
// (each tuple relative to the PREVIOUS token), per the LSP semantic-tokens spec.
// Sort by (line, startChar); on an exact (line,char,type,mods,len) duplicate keep
// one (the typed AST can revisit the same use site via overlapping wrapper
// nodes). On two tokens at the SAME (line,char) keep the SHORTER (innermost
// identifier) — never emit two tokens starting at the same position (the client
// would render overlapping ranges).
function LSP_encode_tokens(toks) {
  // dedup exact + collapse same-start (keep shortest).
  const byStart = new Map();               // "line:char" -> token (shortest len)
  for (const t of toks) {
    if (t.line < 0 || t.char < 0 || t.len <= 0) continue;
    const key = t.line + ':' + t.char;
    const cur = byStart.get(key);
    if (cur === undefined || t.len < cur.len) byStart.set(key, t);
  }
  const xs = Array.from(byStart.values());
  xs.sort((a, b) => (a.line - b.line) || (a.char - b.char));
  const data = [];
  let pLine = 0, pChar = 0;
  for (const t of xs) {
    const dLine = t.line - pLine;
    const dChar = (dLine === 0) ? (t.char - pChar) : t.char;
    data.push(dLine, dChar, t.len, t.type, t.mods);
    pLine = t.line; pChar = t.char;
  }
  return data;
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
// textDocument/semanticTokens/full -> the cached flat int array for `uri`.
// Returns { data } (empty array when the doc has not been checked / has no
// classifiable identifiers) — never null, so the client clears stale tokens.
function LSP_build_semantic_tokens(uri) {
  const idx = LSP_index.get(uri);
  const data = (idx && idx.semanticTokens) ? idx.semanticTokens : [];
  return { data: data };
}
//
////////////////////////////////////////////////////////////////////////.
// ---- WS-5: document symbols / references / highlight / inlays -------- //
//
function LSP_dedup_symbols(ss) {
  const seen = new Set(); const out = [];
  for (const s of ss) {
    if (s.l0 < 0 || s.c0 < 0) continue;
    const key = s.l0+":"+s.c0+":"+s.l1+":"+s.c1+":"+s.kind+":"+s.name+":"+s.container;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(s);
  }
  return out.sort((a, b) => (a.l0 - b.l0) || (a.c0 - b.c0));
}
function LSP_dedup_inlays(hs) {
  const seen = new Set(); const out = [];
  for (const h of hs) {
    if (h.line < 0 || h.char < 0) continue;
    const key = h.line+":"+h.char+":"+h.label+":"+h.kind;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(h);
  }
  return out.sort((a, b) => (a.line - b.line) || (a.char - b.char));
}
//
// textDocument/documentSymbol -> a hierarchical DocumentSymbol[]. v1 containers
// are mostly "" (flat); a non-empty container nests the symbol under the
// same-named parent. range == selectionRange (the name span).
function LSP_build_document_symbols(uri) {
  const idx = LSP_index.get(uri);
  if (!idx) return null;
  const syms = idx.symbols || [];
  const made = syms.map(s => ({
    name: s.name, kind: s.kind | 0,
    range:          LSP_jsrange(s.l0, s.c0, s.l1, s.c1),
    selectionRange: LSP_jsrange(s.l0, s.c0, s.l1, s.c1),
    children: []
  }));
  const byName = new Map();
  for (let i = 0; i < syms.length; i++) {
    if (!syms[i].container) byName.set(syms[i].name, made[i]);
  }
  const roots = [];
  for (let i = 0; i < syms.length; i++) {
    const c = syms[i].container;
    if (c && byName.has(c) && byName.get(c) !== made[i]) byName.get(c).children.push(made[i]);
    else roots.push(made[i]);
  }
  return roots;
}
//
// references / documentHighlight share a target: the def-group (defUri+defRange)
// the cursor resolves to — either via a use site under the cursor, or the
// binding site itself (when the binding lives in THIS file). All USE sites are
// harvested from the file being checked, so references are file-local (+ the
// declaration); project-wide aggregation is a follow-up.
function LSP_defkey(uri, r) {
  return uri + "@" + r.start.line + ":" + r.start.character + ":" +
         r.end.line + ":" + r.end.character;
}
function LSP_find_ref_target(uri, line, char) {
  const idx = LSP_index.get(uri);
  if (!idx) return null;
  const ds = idx.definitions || [];
  const pos = { line: line | 0, character: char | 0 };
  // (a) cursor on a use site -> that record's def group.
  const i = LSP_innermost(ds, d => d.useRange, pos);
  if (i >= 0) return { defUri: ds[i].defUri, defRange: ds[i].defRange };
  // (b) cursor on the binding site in THIS file -> its own def group.
  for (const d of ds) {
    if (d.defUri === uri && LSP_range_contains(d.defRange, pos))
      return { defUri: d.defUri, defRange: d.defRange };
  }
  return null;
}
function LSP_group_use_ranges(uri, target) {
  const idx = LSP_index.get(uri);
  const ds = (idx && idx.definitions) || [];
  const key = LSP_defkey(target.defUri, target.defRange);
  const out = []; const seen = new Set();
  for (const d of ds) {
    if (LSP_defkey(d.defUri, d.defRange) !== key) continue;
    const r = d.useRange;
    const k = r.start.line+":"+r.start.character+":"+r.end.line+":"+r.end.character;
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(r);
  }
  return out;
}
function LSP_build_references(uri, line, char, includeDecl) {
  const t = LSP_find_ref_target(uri, line, char);
  if (!t) return null;
  const locs = LSP_group_use_ranges(uri, t).map(r => ({ uri: uri, range: r }));
  if (includeDecl && t.defUri && t.defRange) locs.push({ uri: t.defUri, range: t.defRange });
  return locs;
}
// DocumentHighlightKind: Text=1, Read=2, Write=3.
function LSP_build_highlights(uri, line, char) {
  const t = LSP_find_ref_target(uri, line, char);
  if (!t) return null;
  const hl = LSP_group_use_ranges(uri, t).map(r => ({ range: r, kind: 2 }));
  if (t.defUri === uri && t.defRange) hl.push({ range: t.defRange, kind: 3 });
  return hl;
}
// textDocument/inlayHint over a range -> InlayHint[] (label + position + kind).
function LSP_build_inlays(uri, range) {
  const idx = LSP_index.get(uri);
  if (!idx) return [];
  const ins = idx.inlays || [];
  const out = [];
  for (const h of ins) {
    if (range && range.start && range.end) {
      const p = { line: h.line, character: h.char };
      if (!(LSP_pos_ge(p, range.start) && LSP_pos_le(p, range.end))) continue;
    }
    out.push({
      position: { line: h.line, character: h.char },
      label: h.label, kind: h.kind | 0,
      paddingLeft: false, paddingRight: false
    });
  }
  return out;
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
function vscode_initialize(validator, liveValidator, pruner, reloadPreludeFn, evictStampFn) {
  // shared driver: set up the per-check context (accumulators + the UTF-16
  // converter over `sourceText`), run `runCheck` (which invokes the ATS3 side
  // and populates the accumulators via diag/hover/def_push), then snapshot the
  // index + publish. `mode` is just a label for the metric line.
  function runValidation(uri, sourceText, mode, runCheck) {
    const t0 = Date.now();
    // reset the per-check accumulators + remap context.
    LSP_cur_diags = []; LSP_cur_hovers = []; LSP_cur_defs = []; LSP_cur_tokens = [];
    LSP_cur_symbols = []; LSP_cur_inlays = [];
    LSP_cur_uri = uri;
    LSP_cur_path = vscode_url_to_path(uri);
    LSP_cur_path_norm = LSP_norm(LSP_cur_path);
    // UTF-16 conversion: build a byte->utf16 converter over the SAME source text
    // we are checking (the saved file's text or the unsaved buffer), so emitted
    // byte columns convert to UTF-16 columns on the correct line. Other-file def
    // targets are converted lazily from their own bytes (LSP_other_b2u).
    LSP_cur_u16 = LSP_u16_make(sourceText);
    LSP_other_u16.clear();   // fresh per check (files may have changed on disk)
    // R2c: index this doc's own directives into the project graph (covers a file
    // opened before/outside the workspace scan, and refreshes its edges from the
    // live buffer). Cheap; keeps the project reverse graph complete + current.
    try { LSP_proj_index_file(LSP_cur_path, sourceText); } catch (e) {}
    let validatorError = null;
    try {
      runCheck();
    } catch (e) {
      // A fatal compiler abort (e.g. XATS000_cfail) on a file the front-end
      // cannot analyze -- typically a compiler-internal file that staloads the
      // ATS3 compiler itself (our own driver files, or srcgen2/ sources). The
      // resident process is NOT poisoned (subsequent files check fine); we
      // surface one Information diagnostic so the missing analysis is explained
      // rather than silent + a scary stack trace in the log.
      validatorError = e;
      LSP_log('could not analyze ' + LSP_cur_path + ' (compiler aborted: ' +
        String((e && e.message) ? e.message : e) + '); other files unaffected');
    }
    // snapshot harvested hover/def/token index for onHover/onDefinition/
    // semanticTokens. Tokens are delta-encoded once here (the request handler
    // just returns the cached { data }).
    LSP_index.set(uri, {
      hovers: LSP_dedup_hovers(LSP_cur_hovers),
      definitions: LSP_dedup_defs(LSP_cur_defs),
      semanticTokens: LSP_encode_tokens(LSP_cur_tokens),
      symbols: LSP_dedup_symbols(LSP_cur_symbols),
      inlays: LSP_dedup_inlays(LSP_cur_inlays)
    });
    const lspDiags = validatorError
      ? [ vscode_diagnostic_make(
            LSP_ls.DiagnosticSeverity.Information,
            vscode_range_make(vscode_position_make(0, 0), vscode_position_make(0, 1)),
            'ats3: could not analyze this file (the compiler aborted: ' +
              String((validatorError && validatorError.message) ? validatorError.message : validatorError) +
              '). This usually means the file staloads the ATS3 compiler itself; ordinary ATS3 files are unaffected.',
            'ats3') ]
      : LSP_current_lsp_diagnostics();
    LSP_connection.sendDiagnostics({ uri: uri, diagnostics: lspDiags });
    const dt = Date.now() - t0;
    const nstat = LSP_stat_count_reset();
    // structured stderr line the smoke harness parses for latency.
    try {
      process.stderr.write('[xats-lsp-metric] check uri=' + uri +
        ' mode=' + mode + ' ms=' + dt + ' diags=' + lspDiags.length +
        ' hovers=' + (LSP_index.get(uri).hovers.length) +
        ' defs=' + (LSP_index.get(uri).definitions.length) +
        ' tokens=' + ((LSP_index.get(uri).semanticTokens.length / 5) | 0) +
        ' stats=' + nstat + '\n');
    } catch (e) {}
    LSP_cur_uri = null; LSP_cur_path = null; LSP_cur_path_norm = null; LSP_cur_u16 = null;
  }

  // DISK path (didOpen / didSave): the ATS3 validator reads the saved file. The
  // source text for UTF-16 conversion is the document's current text (the saved
  // file's contents are reflected in the open doc's buffer at save time).
  function textValidator(textDocument) {
    const uri = textDocument.uri;
    const diagnostics = [];   // the `ds` handle handed to the ATS3 validator
    runValidation(uri, textDocument.getText(), 'disk', function () {
      validator(LSP_dependencies, diagnostics, uri);
    });
  }

  // LIVE path (didChange, debounced): the ATS3 live validator parses the UNSAVED
  // in-memory `text` (NOT the disk file). The same `text` is the source for the
  // UTF-16 converter, so byte columns from the buffer map to its UTF-16 columns.
  function liveValidate(uri, text) {
    const diagnostics = [];
    runValidation(uri, text, 'live', function () {
      liveValidator(LSP_dependencies, diagnostics, uri, text);
    });
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
        // WS-5: outline, find-all-references, occurrence highlight, inferred
        // type inlays. All served from the per-uri harvest index / def records.
        documentSymbolProvider: true,
        referencesProvider: true,
        documentHighlightProvider: true,
        inlayHintProvider: true,
        workspaceSymbolProvider: true,
        // AST-based semantic tokens (full-document). The legend names the
        // tokenTypes/tokenModifiers the harvested indices/bits map to.
        semanticTokensProvider: {
          legend: LSP_semantic_tokens_legend(),
          full: true,
          range: false,
        },
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
  // didChange: LIVE-ON-CHANGE (debounced). Warm checks are ~1-8 ms, so we now
  // validate as the user types — against the UNSAVED in-memory buffer — instead
  // of only on save. Steps per change:
  //   (1) prune immediately (evict the file + dependents from the caches) so the
  //       depgraph stays correct and the debounced live check re-translates the
  //       file's staload closure fresh — exactly the R1 didChange semantics;
  //   (2) (re)arm a per-uri ~300 ms debounce timer; when it fires, run
  //       liveValidate(uri, currentBufferText). The buffer text is taken from the
  //       TextDocuments store AT FIRE TIME (the latest edit), NOT from disk.
  // Rapid keystrokes coalesce: each change resets the timer, so only the final
  // (settled) buffer is checked. A doc closed/saved before the timer fires has
  // its pending check cancelled (close clears it; save runs its own validate).
  const LSP_debounce_ms =
    parseInt(process.env.ATS3_LSP_DEBOUNCE_MS || '300', 10);
  const LSP_change_timers = new Map();   // uri -> Timeout
  function LSP_cancel_change_timer(uri) {
    const t = LSP_change_timers.get(uri);
    if (t !== undefined) { clearTimeout(t); LSP_change_timers.delete(uri); }
  }
  function LSP_schedule_live(uri) {
    LSP_cancel_change_timer(uri);
    const timer = setTimeout(() => {
      LSP_change_timers.delete(uri);
      const doc = LSP_documents.get(uri);
      if (doc === undefined) return;          // closed before the timer fired
      // a $XATSHOME prelude file is handled by the save/reload path, not here.
      try { if (JS_path_is_prelude(vscode_url_to_path(uri))) return; } catch (e) {}
      try { liveValidate(uri, doc.getText()); }
      catch (e) { LSP_log('liveValidate threw: ' + (e && e.stack ? e.stack : e)); }
    }, LSP_debounce_ms);
    // do not keep the event loop alive solely for a pending debounce.
    if (typeof timer.unref === 'function') timer.unref();
    LSP_change_timers.set(uri, timer);
  }
  LSP_documents.onDidChangeContent(change => {
    const uri = change.document.uri;
    // (1) prune now (cheap): keep the cache + depgraph correct.
    try { pruner(LSP_dependencies, uri); }
    catch (e) { LSP_log('pruner threw: ' + (e && e.stack ? e.stack : e)); }
    // (2) schedule a debounced live check of the unsaved buffer.
    LSP_schedule_live(uri);
  });
  LSP_documents.onDidClose(change => {
    LSP_cancel_change_timer(change.document.uri);
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

  // WS-5: references + document highlight (derived from the cached def index).
  function referencesHandler(params) {
    try {
      const incl = !!(params.context && params.context.includeDeclaration);
      return LSP_build_references(params.textDocument.uri,
        params.position.line, params.position.character, incl);
    } catch (e) { LSP_log('onReferences threw: ' + e); return null; }
  }
  if (typeof LSP_connection.onReferences === 'function')
    LSP_connection.onReferences(referencesHandler);
  else LSP_connection.onRequest('textDocument/references', referencesHandler);

  function documentHighlightHandler(params) {
    try {
      return LSP_build_highlights(params.textDocument.uri,
        params.position.line, params.position.character);
    } catch (e) { LSP_log('onDocumentHighlight threw: ' + e); return null; }
  }
  if (typeof LSP_connection.onDocumentHighlight === 'function')
    LSP_connection.onDocumentHighlight(documentHighlightHandler);
  else LSP_connection.onRequest('textDocument/documentHighlight', documentHighlightHandler);

  // WS-5: document symbols (outline).
  function documentSymbolHandler(params) {
    try {
      return LSP_build_document_symbols(params.textDocument.uri);
    } catch (e) { LSP_log('onDocumentSymbol threw: ' + e); return null; }
  }
  if (typeof LSP_connection.onDocumentSymbol === 'function')
    LSP_connection.onDocumentSymbol(documentSymbolHandler);
  else LSP_connection.onRequest('textDocument/documentSymbol', documentSymbolHandler);

  // WS-5: inlay hints (inferred val types). Prefer the typed languages helper.
  function inlayHintHandler(params) {
    try {
      return LSP_build_inlays(params.textDocument.uri, params.range);
    } catch (e) { LSP_log('onInlayHint threw: ' + e); return []; }
  }
  if (LSP_connection.languages && LSP_connection.languages.inlayHint &&
      typeof LSP_connection.languages.inlayHint.on === 'function') {
    LSP_connection.languages.inlayHint.on(inlayHintHandler);
  } else {
    LSP_connection.onRequest('textDocument/inlayHint', inlayHintHandler);
  }

  // WS-5: workspace/symbol (fuzzy project-wide name search over the textual index).
  function workspaceSymbolHandler(params) {
    try { return LSP_build_workspace_symbols((params && params.query) || ""); }
    catch (e) { LSP_log('onWorkspaceSymbol threw: ' + e); return []; }
  }
  if (typeof LSP_connection.onWorkspaceSymbol === 'function')
    LSP_connection.onWorkspaceSymbol(workspaceSymbolHandler);
  else LSP_connection.onRequest('workspace/symbol', workspaceSymbolHandler);

  // textDocument/semanticTokens/full. Prefer the typed helper
  // (connection.languages.semanticTokens.on); fall back to the raw onRequest
  // for runtimes/builds without the languages feature. Both return { data }.
  function semanticTokensFull(params) {
    try {
      return LSP_build_semantic_tokens(params.textDocument.uri);
    } catch (e) { LSP_log('semanticTokens/full threw: ' + e); return { data: [] }; }
  }
  if (LSP_connection.languages && LSP_connection.languages.semanticTokens &&
      typeof LSP_connection.languages.semanticTokens.on === 'function') {
    LSP_connection.languages.semanticTokens.on(semanticTokensFull);
  } else {
    LSP_connection.onRequest('textDocument/semanticTokens/full', semanticTokensFull);
  }

  // TEST-ONLY introspection: report the per-uri index sizes + the MAX line that
  // any harvested hover / definition / semantic-token lands on. Used by the
  // include/source-filter smoke to assert no emitted row escapes the checked
  // file's own line range (Bug 1). Pure read-over of the cached index; no effect
  // on normal request handling.
  LSP_connection.onRequest('xats/indexStats', params => {
    try {
      const uri = (params && params.uri) || (params && params.textDocument && params.textDocument.uri);
      const idx = LSP_index.get(uri);
      if (!idx) return { found: false };
      const hs = idx.hovers || [];
      const ds = idx.definitions || [];
      const tk = idx.semanticTokens || [];   // flat delta-encoded 5-tuples
      let maxHoverLine = -1;
      for (const h of hs) {
        const e = h.range && h.range.end ? h.range.end.line : -1;
        if (e > maxHoverLine) maxHoverLine = e;
      }
      let maxDefUseLine = -1;
      for (const d of ds) {
        const e = d.useRange && d.useRange.end ? d.useRange.end.line : -1;
        if (e > maxDefUseLine) maxDefUseLine = e;
      }
      // decode the delta-encoded token lines to find the absolute max.
      let line = 0, maxTokenLine = -1;
      for (let i = 0; i + 4 < tk.length; i += 5) {
        line += tk[i];            // dLine is absolute-relative; tokens sorted
        if (line > maxTokenLine) maxTokenLine = line;
      }
      return {
        found: true,
        hovers: hs.length, defs: ds.length, tokens: (tk.length / 5) | 0,
        maxHoverLine: maxHoverLine, maxDefUseLine: maxDefUseLine, maxTokenLine: maxTokenLine
      };
    } catch (e) { LSP_log('xats/indexStats threw: ' + e); return { found: false, error: String(e) }; }
  });

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
      // a save supersedes any pending debounced live check for this doc.
      LSP_cancel_change_timer(uri);
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
