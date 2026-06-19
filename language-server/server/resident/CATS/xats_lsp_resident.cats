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
// ---- string-buffer FILR (capture a printed type as a JS string) ------ //
//
function LSP_strbuf_new() {
  return { buf: "", write: function (s) { this.buf += s; } };
}
function LSP_strbuf_get(fb) { return fb.buf; }
//
////////////////////////////////////////////////////////////////////////.
// ---- friendly type-name map (reused from xats_lsp_check.cats) -------- //
//
const LSP_TYPENAME = {
  "gint_type": "int", "bool_type": "bool", "char_type": "char",
  "the_s2exp_strn0": "string", "the_s2exp_sint0": "int",
  "the_s2exp_bool0": "bool", "the_s2exp_char0": "char",
  "the_s2exp_void0": "void", "strn": "string", "gflt_type": "float",
  "xats_sint_t": "int", "xats_strn_t": "string", "xats_bool_t": "bool",
  "void_type": "void", "string_type": "string", "string_i0_tx": "string",
  "xats_void_t": "void", "xats_char_t": "char", "xats_dflt_t": "float",
  "list_t0_i0_tx": "list", "list_vt_i0_vx": "list_vt",
  "optn_t0_i0_tx": "optn", "optn_vt_i0_vx": "optn_vt",
  "lazy_t0_vx": "lazy", "lazy_vt_vx": "lazy_vt"
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
  const t = LSP_typestr(typ);
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
//
function LSP_log(msg) {
  try { LSP_connection.console.log('[xats-lsp-resident] ' + String(msg)); } catch (e) {}
}
//
function vscode_initialize(validator, pruner) {
  // run one in-process validation for a document, snapshot the index, publish.
  function textValidator(textDocument) {
    const uri = textDocument.uri;
    const t0 = Date.now();
    // reset the per-check accumulators + remap context.
    LSP_cur_diags = []; LSP_cur_hovers = []; LSP_cur_defs = [];
    LSP_cur_uri = uri;
    LSP_cur_path = vscode_url_to_path(uri);
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
    // structured stderr line the smoke harness parses for latency.
    try {
      process.stderr.write('[xats-lsp-metric] check uri=' + uri +
        ' ms=' + dt + ' diags=' + lspDiags.length +
        ' hovers=' + (LSP_index.get(uri).hovers.length) +
        ' defs=' + (LSP_index.get(uri).definitions.length) + '\n');
    } catch (e) {}
    LSP_cur_uri = null; LSP_cur_path = null;
  }

  LSP_connection.onInitialize((params) => {
    const capabilities = params.capabilities;
    LSP_hasConfigurationCapability = !!(
      capabilities.workspace && !!capabilities.workspace.configuration);
    LSP_hasWorkspaceFolderCapability = !!(
      capabilities.workspace && !!capabilities.workspace.workspaceFolders);
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
  });

  LSP_documents.onDidOpen(change => { textValidator(change.document); });
  LSP_documents.onDidSave(change => { textValidator(change.document); });
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
  LSP_connection.listen();
  try { process.stderr.write('[xats-lsp-resident] listening on stdio (resident, in-process)\n'); } catch (e) {}
}
//
////////////////////////////////////////////////////////////////////////.
// end of [language-server/server/resident/CATS/xats_lsp_resident.cats]
////////////////////////////////////////////////////////////////////////.
