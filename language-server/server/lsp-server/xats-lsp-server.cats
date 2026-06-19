////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//             WS-1b  LSP server core - JS-glue (.cats)               //.
//             companion for xats-lsp-server.dats                     //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// HX-LSP-WS1b:
// This file is the ".cats" (raw-JS companion) half of the FFI idiom
// (ATS3-COMPILER-PRIMER.md S10.1). Every ATS3 function declared with
//   `#extern fun NAME(...) : T = $extnam()`
// is implemented here by a same-named JS function ($ survives into JS
// verbatim and is a legal identifier char).
//
// It is cat-concatenated into the final xats-lsp-server.js by build.sh,
// BEFORE the compiled output, because its `const X = require(...)` lines
// are not hoisted and the compiled top-level main() uses them on load
// (WS-0a spike, deviation #3).
//
// SPLIT (see the .dats header): ATS3 drives all control flow / lifecycle.
// This file is the marshalling layer: it require()s the npm libs + node
// builtins and hands ATS3 only scalars and opaque handles. The per-
// (uri,version) bundle cache is the JS Map `XLSP_cache` below, but every
// put/get/drop is DECIDED and INVOKED from ATS3 -- this file just owns the
// storage and the JSON/array marshalling so the .dats stays clean.
//
////////////////////////////////////////////////////////////////////////.
//
// (1) require() the LSP libs + node builtins. Resolves relative to
//     xats-lsp-server.js's OWN directory (WS-0a deviation #4), so we ship
//     it next to node_modules/.
//
const XLSP_ls = require('vscode-languageserver/node');
const XLSP_td = require('vscode-languageserver-textdocument');
const XLSP_cp = require('node:child_process');
const XLSP_fs = require('node:fs');
const XLSP_os = require('node:os');
const XLSP_path = require('node:path');
//
const {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  TextDocumentSyncKind,
  StreamMessageReader,
  StreamMessageWriter,
} = XLSP_ls;
const { TextDocument } = XLSP_td;
//
////////////////////////////////////////////////////////////////////////.
//
// (2) module-global state. A stdio server has exactly one connection and one
//     document manager, so we keep them module-global rather than threading
//     opaque handles through ATS3 (cleaner; matches the single-connection
//     reality). The cache + debounce-timer tables also live here; ATS3 drives
//     every operation on them.
//
let   XLSP_connection = null;       // the JSON-RPC connection
let   XLSP_documents  = null;       // the TextDocuments manager
const XLSP_timers     = new Map();  // uri -> pending setTimeout handle (debounce)
const XLSP_cache      = new Map();  // "uri version" -> parsed bundle (opaque)
//
// configuration (Decision: the checker command is configurable). The env var
// ATS3_LSP_CHECKER always wins (the smoke test points it at
// contract/fake-checker.js). Otherwise we fall back to the REAL checker
// (WS-1a). The real checker (xats-lsp-check.js) is a sibling build artifact:
// WS-1a builds it under language-server/server/BUILD/ (one level up from this
// lsp-server/ dir). We probe a couple of likely locations and use the first
// that exists; if none exist we keep the conventional sibling path and log a
// clear warning at startup so misconfiguration is obvious.
//
function XLSP_pick_checker () {
  const env = process.env.ATS3_LSP_CHECKER;
  if (env) { return env; }
  const candidates = [
    // Prefer the Closure-minified checker (~43x smaller, faster cold start,
    // ~4.5x less RSS). Fall back to the raw bundle if it was not minified.
    XLSP_path.join(__dirname, 'xats-lsp-check.opt1.js'),              // shipped beside server
    XLSP_path.join(__dirname, '..', 'BUILD', 'xats-lsp-check.opt1.js'),// build dir (minified)
    XLSP_path.join(__dirname, 'xats-lsp-check.js'),                   // shipped beside server
    XLSP_path.join(__dirname, '..', 'BUILD', 'xats-lsp-check.js'),    // build dir (raw)
  ];
  for (const c of candidates) {
    try { if (XLSP_fs.existsSync(c)) { return c; } } catch (_) {}
  }
  return candidates[0]; // conventional default (may not exist yet -> warn later)
}
const XLSP_CHECKER = XLSP_pick_checker();
const XLSP_DEBOUNCE_MS =
  parseInt(process.env.ATS3_LSP_DEBOUNCE_MS || '300', 10) || 300;
//
function XLSP_cache_key (uri, version) {
  return uri + ' ' + String(version);
}
//
////////////////////////////////////////////////////////////////////////.
//
// (a) logging -> stderr. stdout is the JSON-RPC channel and MUST stay clean,
//     so all server logging goes to stderr (the smoke harness surfaces it).
//
function XLSP_log (msg) {
  try { process.stderr.write('[xats-lsp] ' + msg.toString() + '\n'); }
  catch (_) { /* never let logging crash the server */ }
  return;
}
//
// (b) configuration accessors.
//
function XLSP_checker_path () { return XLSP_CHECKER; }
function XLSP_debounce_ms  () { return XLSP_DEBOUNCE_MS; }
//
////////////////////////////////////////////////////////////////////////.
//
// (c) connection lifecycle.
//
// createConnection over stdio. vscode-languageserver does NOT auto-select a
// transport: it needs a --stdio/--node-ipc/--socket flag (the VSCode client
// passes one) or explicit reader/writer streams. Bind stdin/stdout explicitly
// unless a transport flag is present, so the server works both under VSCode
// and when launched bare by the smoke harness (mirrors the WS-0b stub).
//
function XLSP_connection_make () {
  const hasTransportFlag = process.argv.some(
    (a) => a === '--stdio' || a === '--node-ipc' || a.startsWith('--socket')
  );
  XLSP_connection = hasTransportFlag
    ? createConnection(ProposedFeatures.all)
    : createConnection(
        ProposedFeatures.all,
        new StreamMessageReader(process.stdin),
        new StreamMessageWriter(process.stdout)
      );
  XLSP_documents = new TextDocuments(TextDocument);
  return;
}
//
// onInitialize: run the ATS3 callback (logging), then return capabilities.
// Advertise incremental sync + hoverProvider + definitionProvider so the
// later phases (WS-2/WS-3) light up without a client change.
//
function XLSP_on_initialize (cb) {
  XLSP_connection.onInitialize(function (/*params*/) {
    try { cb(); } catch (e) { XLSP_log('onInitialize cb threw: ' + e); }
    return {
      capabilities: {
        textDocumentSync: TextDocumentSyncKind.Incremental,
        hoverProvider: true,
        definitionProvider: true,
        typeDefinitionProvider: true,
      },
      serverInfo: { name: 'xats-lsp-server', version: '0.1.0' },
    };
  });
  return;
}
//
// document events. The TextDocuments manager handles full/incremental sync;
// we forward SCALARS (uri, version, full current text) to the ATS3 callback,
// which makes the debounce decision.
//
function XLSP_on_open (cb) {
  XLSP_documents.onDidOpen(function (e) {
    const d = e.document;
    try { cb(d.uri, d.version | 0, d.getText()); }
    catch (err) { XLSP_log('onDidOpen cb threw: ' + err); }
  });
  return;
}
function XLSP_on_change (cb) {
  XLSP_documents.onDidChangeContent(function (e) {
    const d = e.document;
    try { cb(d.uri, d.version | 0, d.getText()); }
    catch (err) { XLSP_log('onDidChangeContent cb threw: ' + err); }
  });
  return;
}
function XLSP_on_close (cb) {
  XLSP_documents.onDidClose(function (e) {
    try { cb(e.document.uri); }
    catch (err) { XLSP_log('onDidClose cb threw: ' + err); }
  });
  return;
}
//
// hover / definition / type-definition (WS-2 / WS-3), answered PURELY from the
// per-(uri,version) cache -- no recompile, no checker spawn.
//
// SPLIT recap: ATS3 drives the lookup decision; this file holds the Map access
// + the contains/innermost helper + the LSP-object shaping. Each `onX` handler
// below: (1) pulls the SCALARS (uri, line, char) out of the request params,
// (2) calls the ATS3 callback `cb(uri, line, char)` -- which itself calls our
// `*_find` primitive and hands back the chosen entry INDEX (or -1), (3) shapes
// the LSP result object from that index (or returns null for -1).
//
// ---- position / range geometry (the "contains" + "innermost" helper) ----
//
// LSP positions order lexicographically by (line, character). `pos` is the
// request Position; `r` is a contract range {start:{line,character},
// end:{line,character}} (0-based, contract S4).
//
function XLSP_pos_ge (a, b) { // a >= b  (a after-or-equal b)
  if (a.line !== b.line) { return a.line > b.line; }
  return a.character >= b.character;
}
function XLSP_pos_le (a, b) { // a <= b  (a before-or-equal b)
  if (a.line !== b.line) { return a.line < b.line; }
  return a.character <= b.character;
}
// standard LSP "range contains position": start <= pos <= end.
function XLSP_range_contains (r, pos) {
  if (!r || !r.start || !r.end) { return false; }
  return XLSP_pos_ge(pos, r.start) && XLSP_pos_le(pos, r.end);
}
// a comparable "span size" for picking the INNERMOST (smallest) containing
// range. Line difference dominates; character difference breaks line ties.
// (Exact magnitude is irrelevant -- only the ordering between candidates is.)
function XLSP_range_span (r) {
  const dl = r.end.line - r.start.line;
  const dc = r.end.character - r.start.character;
  return dl * 1000000 + dc;
}
//
// generic innermost-contains scan: over `entries`, take rangeOf(entry) for each
// and return the INDEX of the smallest-span range that contains `pos`; on a tie
// keep the FIRST (we only replace on a STRICTLY smaller span). -1 if none.
//
function XLSP_innermost_index (entries, rangeOf, pos) {
  let bestIdx = -1, bestSpan = Infinity;
  for (let i = 0; i < entries.length; i++) {
    const r = rangeOf(entries[i]);
    if (!XLSP_range_contains(r, pos)) { continue; }
    const span = XLSP_range_span(r);
    if (span < bestSpan) { bestSpan = span; bestIdx = i; }
  }
  return bestIdx;
}
//
// the request-side scratch: the find primitives stash the chosen bundle so the
// matching build primitive (called by the same handler turn) can read it back
// without re-scanning. Single-threaded node -> a module-global is safe.
//
let XLSP_last_hover_bundle = null;
let XLSP_last_def_bundle   = null;
//
// XLSP_hover_find(uri, line, char): index of the innermost `hovers` entry whose
// `range` contains (line,char) in the LATEST cached bundle, or -1.
//
function XLSP_hover_find (uri, line, char) {
  const bundle = XLSP_latest_bundle(uri);
  XLSP_last_hover_bundle = bundle;
  if (!bundle) { return -1; }
  const hs = bundle.hovers || [];
  const pos = { line: line | 0, character: char | 0 };
  return XLSP_innermost_index(hs, function (h) { return h.range; }, pos);
}
//
// XLSP_definition_find(uri, line, char): index of the innermost `definitions`
// entry whose `useRange` contains (line,char) in the LATEST bundle, or -1.
//
function XLSP_definition_find (uri, line, char) {
  const bundle = XLSP_latest_bundle(uri);
  XLSP_last_def_bundle = bundle;
  if (!bundle) { return -1; }
  const ds = bundle.definitions || [];
  const pos = { line: line | 0, character: char | 0 };
  return XLSP_innermost_index(ds, function (d) { return d.useRange; }, pos);
}
//
// ---- LSP-object builders (from the chosen index in the last-found bundle) ----
//
// Hover: ```ats\n<type>\n``` markdown, anchored to the hover entry's range.
//
function XLSP_build_hover (idx) {
  const b = XLSP_last_hover_bundle;
  if (!b || idx < 0) { return null; }
  const h = (b.hovers || [])[idx];
  if (!h) { return null; }
  return {
    contents: { kind: 'markdown', value: '```ats\n' + String(h.type) + '\n```' },
    range: h.range,
  };
}
//
// Definition: an LSP Location { uri:defUri, range:defRange }.
//
function XLSP_build_definition (idx) {
  const b = XLSP_last_def_bundle;
  if (!b || idx < 0) { return null; }
  const d = (b.definitions || [])[idx];
  if (!d || !d.defUri || !d.defRange) { return null; }
  return { uri: d.defUri, range: d.defRange };
}
//
// TypeDefinition: Location from the OPTIONAL typeDefUri/typeDefRange; null when
// the chosen definition has no type-def info (contract S4 marks them optional).
//
function XLSP_build_type_definition (idx) {
  const b = XLSP_last_def_bundle;
  if (!b || idx < 0) { return null; }
  const d = (b.definitions || [])[idx];
  if (!d || !d.typeDefUri || !d.typeDefRange) { return null; }
  return { uri: d.typeDefUri, range: d.typeDefRange };
}
//
// extract (uri, line, character) scalars from an LSP TextDocumentPositionParams.
//
function XLSP_params_uri (params) {
  return (params && params.textDocument && params.textDocument.uri) || '';
}
function XLSP_params_line (params) {
  const p = params && params.position;
  return p ? (p.line | 0) : 0;
}
function XLSP_params_char (params) {
  const p = params && params.position;
  return p ? (p.character | 0) : 0;
}
//
// handlers: ATS3 owns the decision (cb returns the index); we shape the result.
//
function XLSP_on_hover (cb) {
  XLSP_connection.onHover(function (params) {
    let idx = -1;
    try {
      idx = cb(XLSP_params_uri(params),
               XLSP_params_line(params),
               XLSP_params_char(params)) | 0;
    } catch (e) { XLSP_log('onHover cb threw: ' + e); return null; }
    return XLSP_build_hover(idx);
  });
  return;
}
function XLSP_on_definition (cb) {
  XLSP_connection.onDefinition(function (params) {
    let idx = -1;
    try {
      idx = cb(XLSP_params_uri(params),
               XLSP_params_line(params),
               XLSP_params_char(params)) | 0;
    } catch (e) { XLSP_log('onDefinition cb threw: ' + e); return null; }
    return XLSP_build_definition(idx);
  });
  return;
}
function XLSP_on_type_definition (cb) {
  // onTypeDefinition exists on the full-feature connection (ProposedFeatures.all).
  if (typeof XLSP_connection.onTypeDefinition !== 'function') {
    XLSP_log('onTypeDefinition not available on this connection; skipping');
    return;
  }
  XLSP_connection.onTypeDefinition(function (params) {
    let idx = -1;
    try {
      idx = cb(XLSP_params_uri(params),
               XLSP_params_line(params),
               XLSP_params_char(params)) | 0;
    } catch (e) { XLSP_log('onTypeDefinition cb threw: ' + e); return null; }
    return XLSP_build_type_definition(idx);
  });
  return;
}
//
// listen: documents.listen(connection); connection.listen().
//
function XLSP_listen () {
  XLSP_documents.listen(XLSP_connection);
  XLSP_connection.listen();
  XLSP_log('listening on stdio');
  return;
}
//
////////////////////////////////////////////////////////////////////////.
//
// (d) debounce (~300ms; coalesce didChange bursts per uri). Re-arming clears
//     any prior pending timer for the same uri, so a burst collapses to one
//     run with the latest text. ATS3 decides WHEN to schedule.
//
function XLSP_debounce_schedule (uri, cb) {
  const prev = XLSP_timers.get(uri);
  if (prev) { clearTimeout(prev); }
  const h = setTimeout(function () {
    XLSP_timers.delete(uri);
    try { cb(); } catch (e) { XLSP_log('debounced cb threw: ' + e); }
  }, XLSP_DEBOUNCE_MS);
  XLSP_timers.set(uri, h);
  return;
}
function XLSP_debounce_cancel (uri) {
  const prev = XLSP_timers.get(uri);
  if (prev) { clearTimeout(prev); XLSP_timers.delete(uri); }
  return;
}
//
////////////////////////////////////////////////////////////////////////.
//
// (e) the check pipeline primitives.
//
// uri -> filesystem path of the original document (file:// only).
//
function XLSP_uri_to_fspath (uri) {
  if (typeof uri === 'string' && uri.startsWith('file://')) {
    try { return decodeURIComponent(uri.replace(/^file:\/\//, '')); }
    catch (_) { return uri.replace(/^file:\/\//, ''); }
  }
  return uri;
}
//
// write the current buffer to a UNIQUE temp file, PRESERVING the source
// extension (.dats/.sats; the checker dispatches on it). Returns the temp path.
//
let XLSP_tmp_seq = 0;
function XLSP_tmp_write (uri, text) {
  const fsp = XLSP_uri_to_fspath(uri);
  let ext = XLSP_path.extname(fsp);
  if (ext !== '.dats' && ext !== '.sats') { ext = '.dats'; }
  const base = 'xats-lsp-' + process.pid + '-' + (XLSP_tmp_seq++) + ext;
  const tmp = XLSP_path.join(XLSP_os.tmpdir(), base);
  XLSP_fs.writeFileSync(tmp, text);
  return tmp;
}
//
// derive the --json-out path for a temp source (same dir, .json suffix).
//
function XLSP_json_out_for (tmpSrc) {
  return tmpSrc + '.bundle.json';
}
//
// spawnSync the checker:
//   node <checkerJs> <tmpSrc> --uri <uri> --json-out <tmpJson>
// One check at a time (we debounce). stdout/stderr of the checker are
// IGNORED here (debug noise, Decision D3) -- only the --json-out file is read.
// Returns the --json-out path (so ATS3 hands it to the reader).
//
function XLSP_run_checker (tmpSrc, uri) {
  const jsonOut = XLSP_json_out_for(tmpSrc);
  // best-effort: remove a stale bundle so we never read a previous run's file.
  try { XLSP_fs.unlinkSync(jsonOut); } catch (_) {}
  // make a missing checker obvious (e.g. real checker not built yet).
  try { if (!XLSP_fs.existsSync(XLSP_CHECKER)) {
    XLSP_log('WARNING: checker not found at ' + XLSP_CHECKER +
             ' (set ATS3_LSP_CHECKER); will publish empty diagnostics');
  } } catch (_) {}
  // Node flags for the checker. The REAL (compiler-linking) checker stack-overflows
  // in the lexer without a large --stack-size, and the ~171MB lib wants a roomy heap.
  // The fake-checker ignores these harmlessly. Override via ATS3_LSP_CHECKER_NODE_ARGS
  // (space-separated); set it to "" to pass none.
  const nodeArgs = (process.env.ATS3_LSP_CHECKER_NODE_ARGS !== undefined
                    ? process.env.ATS3_LSP_CHECKER_NODE_ARGS
                    : '--stack-size=8801 --max-old-space-size=8192').split(/\s+/).filter(Boolean);
  const args = [...nodeArgs, XLSP_CHECKER, tmpSrc, '--uri', uri, '--json-out', jsonOut];
  try {
    const r = XLSP_cp.spawnSync(process.execPath, args, {
      stdio: ['ignore', 'ignore', 'ignore'], // D3: ignore the checker's stdout
      encoding: 'utf8',
    });
    if (r.error) { XLSP_log('spawn error: ' + r.error); }
  } catch (e) {
    XLSP_log('spawnSync threw: ' + e);
  }
  return jsonOut;
}
//
// read + JSON.parse the bundle into the cache under (uri, version). Returns
// true on success, false if unreadable/unparsable (ATS3 then clears + logs).
// We also clean up the temp source + bundle files now that we hold the parsed
// object in memory.
//
function XLSP_cache_put_from_json (uri, version, jsonPath) {
  let bundle = null;
  try {
    const raw = XLSP_fs.readFileSync(jsonPath, 'utf8');
    bundle = JSON.parse(raw);
  } catch (e) {
    XLSP_log('cache_put: cannot read/parse ' + jsonPath + ': ' + e);
    return false;
  }
  if (!bundle || typeof bundle !== 'object') {
    XLSP_log('cache_put: bundle not an object');
    return false;
  }
  // The server type-checks a TEMP copy of the buffer, so the checker labels
  // in-file locations with the temp path it actually read. Remap any location
  // that resolves to that temp file back to the editor's real document uri, so
  // within-file go-to-def lands in the OPEN document, not a phantom temp file.
  // (Cross-file targets like the prelude keep their real paths and are untouched.)
  const tmpSrc = jsonPath.endsWith('.bundle.json')
    ? jsonPath.replace(/\.bundle\.json$/, '') : null;
  if (tmpSrc) {
    const isTmp = (u) => {
      try { return !!u && XLSP_uri_to_fspath(u) === tmpSrc; } catch (_) { return false; }
    };
    for (const d of (bundle.definitions || [])) {
      if (isTmp(d.defUri)) { d.defUri = uri; }
      if (isTmp(d.typeDefUri)) { d.typeDefUri = uri; }
    }
  }
  XLSP_cache.set(XLSP_cache_key(uri, version), bundle);
  XLSP_log(
    'cache_put: uri=' + uri + ' version=' + version +
    ' diagnostics=' + ((bundle.diagnostics || []).length)
  );
  // tidy the temp files (source had a .dats/.sats ext; bundle is .bundle.json).
  try { if (jsonPath.endsWith('.bundle.json')) {
    XLSP_fs.unlinkSync(jsonPath.replace(/\.bundle\.json$/, ''));
  } } catch (_) {}
  try { XLSP_fs.unlinkSync(jsonPath); } catch (_) {}
  return true;
}
//
function XLSP_cache_has (uri, version) {
  return XLSP_cache.has(XLSP_cache_key(uri, version));
}
//
// drop every cached version for a uri (on close).
//
function XLSP_cache_drop (uri) {
  const prefix = uri + ' ';
  for (const k of Array.from(XLSP_cache.keys())) {
    if (k.startsWith(prefix)) { XLSP_cache.delete(k); }
  }
  return;
}
//
// the LATEST cached bundle for a uri. Hover/def requests carry only uri +
// position (no version), so we scan the keys ("uri version") under this uri's
// prefix and return the bundle with the highest numeric version (or null).
//
function XLSP_latest_bundle (uri) {
  const prefix = uri + ' ';
  let best = null, bestV = -Infinity;
  for (const k of XLSP_cache.keys()) {
    if (!k.startsWith(prefix)) { continue; }
    const v = parseInt(k.slice(prefix.length), 10);
    if (Number.isFinite(v) && v >= bestV) { bestV = v; best = XLSP_cache.get(k); }
  }
  return best;
}
//
// map a cached bundle's diagnostics -> LSP Diagnostic[] and sendDiagnostics.
// The bundle range is ALREADY 0-based LSP shape (contract S4), so the mapping
// is near-identity: copy range, severity (1->Error), message, source, code.
// If nothing is cached for (uri, version) -> publish an EMPTY array (clear).
//
function XLSP_bundle_to_diagnostics (bundle) {
  const out = [];
  const ds = (bundle && bundle.diagnostics) || [];
  for (let i = 0; i < ds.length; i++) {
    const d = ds[i];
    out.push({
      range: d.range,                                   // already 0-based LSP
      severity: (typeof d.severity === 'number') ? d.severity : 1, // 1->Error
      code: d.code,
      message: d.message,
      source: d.source || 'ats3',
    });
  }
  return out;
}
//
function XLSP_publish (uri, version) {
  const bundle = XLSP_cache.get(XLSP_cache_key(uri, version));
  const diagnostics = bundle ? XLSP_bundle_to_diagnostics(bundle) : [];
  XLSP_connection.sendDiagnostics({ uri: uri, diagnostics: diagnostics });
  XLSP_log(
    'publish: uri=' + uri + ' version=' + version +
    ' -> ' + diagnostics.length + ' diagnostic(s)'
  );
  return;
}
//
function XLSP_publish_empty (uri) {
  XLSP_connection.sendDiagnostics({ uri: uri, diagnostics: [] });
  XLSP_log('publish_empty: uri=' + uri);
  return;
}
//
////////////////////////////////////////////////////////////////////////.
////////////////////////////////////////////////////////////////////////.
// end of [language-server/server/lsp-server/xats-lsp-server.cats]
////////////////////////////////////////////////////////////////////////.
////////////////////////////////////////////////////////////////////////.
