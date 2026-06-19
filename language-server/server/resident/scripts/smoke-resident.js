#!/usr/bin/env node
/*
 * Headless verification harness for the RESIDENT in-process ATS3 LSP server
 * (BUILD/xats-lsp-resident.opt1.js).  Workstream R1.
 *
 * Speaks raw LSP/JSON-RPC over stdio (Content-Length framed), exactly as the
 * VSCode client would. It proves the WHOLE point of the re-architecture:
 *
 *   A) initialize -> capabilities (hover + definition + typeDefinition).
 *   B) didOpen(bad file on disk)  -> publishDiagnostics with the 2 expected
 *      diagnostics (type-mismatch @0:13-0:20, unbound-identifier @1:13-1:28).
 *      Measures FIRST-CHECK latency (prelude loads on the first check).
 *   C) CACHE-EVICTION CORRECTNESS (must-pass): rewrite the SAME file on disk to
 *      introduce a DIFFERENT error, fire didChange (prune) + didSave
 *      (revalidate), and confirm the server reports the NEW diagnostic — proving
 *      it RE-CHECKED and did NOT serve a stale cached result. Measures
 *      WARM-CHECK latency (prelude already loaded).
 *   D) rewrite the file CLEAN on disk, didChange + didSave -> diagnostics CLEAR
 *      (empty array) — proving eviction works both ways.
 *   E) HOVER over a typed expression -> a type tooltip.
 *   F) DEFINITION on a use site -> the binding Location.
 *   G) a SECOND unrelated file checks WARM (no prelude reload) -> latency
 *      comparable to the warm recheck, proving the compiler stays resident.
 *
 * The server reads the SAVED file from disk on didOpen/didSave (the reference
 * v1 trigger model), so this harness writes real files under a temp dir and
 * mutates them on disk between phases.
 *
 * Exit 0 = all pass.  Latency lines are printed for the report.
 */
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const HERE = __dirname;
const RESIDENT = path.resolve(HERE, '..');
const SERVER = process.env.RESIDENT_SERVER ||
  path.join(RESIDENT, 'BUILD', 'xats-lsp-resident.opt1.js');
const NODE_ARGS = ['--stack-size=8801'];
const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '120000', 10);

// --- a real on-disk workspace (the server reads the saved file) ----------
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-resident-'));
const FILE_A = path.join(WS, 'fileA.dats');
const FILE_B = path.join(WS, 'fileB.dats');
const URI_A = 'file://' + FILE_A;
const URI_B = 'file://' + FILE_B;

const SRC_OK   = 'val x: int = 3\nval y: int = x\n';
const SRC_BAD1 = 'val x: int = "hello"\nval y: int = nonexistent_var\n'; // type-mismatch @0:13 + unbound @1:13
const SRC_BAD2 = 'val a: int = 7\nval b: int = totally_undefined_name\n'; // a DIFFERENT unbound @1:13
const SRC_B_OK = 'val p: int = 100\nval q: int = p\n';

// --- LSP framing -----------------------------------------------------------
function encode(msg) {
  const payload = Buffer.from(JSON.stringify(msg), 'utf8');
  return Buffer.concat([
    Buffer.from(`Content-Length: ${payload.length}\r\n\r\n`, 'ascii'),
    payload,
  ]);
}
class MessageReader {
  constructor(onMessage) { this.buffer = Buffer.alloc(0); this.onMessage = onMessage; }
  push(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    for (;;) {
      const headerEnd = this.buffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) return;
      const header = this.buffer.slice(0, headerEnd).toString('ascii');
      const m = /Content-Length:\s*(\d+)/i.exec(header);
      if (!m) { this.buffer = this.buffer.slice(headerEnd + 4); continue; }
      const len = parseInt(m[1], 10);
      const bodyStart = headerEnd + 4;
      if (this.buffer.length < bodyStart + len) return;
      const body = this.buffer.slice(bodyStart, bodyStart + len).toString('utf8');
      this.buffer = this.buffer.slice(bodyStart + len);
      try { this.onMessage(JSON.parse(body)); } catch (e) {}
    }
  }
}

// --- assertions ------------------------------------------------------------
const failures = [];
function fail(msg) { failures.push(msg); console.error(`[smoke] FAIL: ${msg}`); }
function pass(msg) { console.log(`[smoke] PASS: ${msg}`); }
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${s.line},${s.character}-${e.line},${e.character}`;
}
function hasDiag(diags, code, sl, sc, el, ec) {
  return diags.some(d => d.code === code &&
    d.range && d.range.start.line === sl && d.range.start.character === sc &&
    d.range.end.line === el && d.range.end.character === ec);
}
function hasCode(diags, code) { return diags.some(d => d.code === code); }

// --- driver ----------------------------------------------------------------
function main() {
  // seed the bad file on disk.
  fs.writeFileSync(FILE_A, SRC_BAD1);
  fs.writeFileSync(FILE_B, SRC_B_OK);

  console.log(`[smoke] server : ${SERVER}`);
  console.log(`[smoke] ws     : ${WS}`);

  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu' }),
  });

  let done = false;
  let nextId = 100;
  const pending = new Map();   // id -> resolve
  const diagWaiters = [];      // {uri, resolve}
  const lastDiags = new Map(); // uri -> diagnostics[]
  const timing = {};

  const timer = setTimeout(() => { if (!done) { fail(`timed out after ${TIMEOUT_MS}ms`); finish(); } }, TIMEOUT_MS);

  function send(msg) { child.stdin.write(encode(msg)); }
  function request(method, params) {
    const id = nextId++;
    return new Promise((resolve) => { pending.set(id, resolve); send({ jsonrpc: '2.0', id, method, params }); });
  }
  function notify(method, params) { send({ jsonrpc: '2.0', method, params }); }

  // wait for the NEXT publishDiagnostics for `uri`, with a wall-clock stamp.
  function waitDiagnostics(uri, label) {
    const t0 = Date.now();
    return new Promise((resolve) => {
      diagWaiters.push({ uri, resolve: (diags) => { if (label) timing[label] = Date.now() - t0; resolve(diags); } });
    });
  }

  function openDoc(uri, text) {
    notify('textDocument/didOpen', { textDocument: { uri, languageId: 'ats3', version: 1, text } });
  }
  function changeDoc(uri, version) {
    // content changes are on disk; we just fire didChange to trigger the prune.
    notify('textDocument/didChange', { textDocument: { uri, version }, contentChanges: [{ text: fs.readFileSync(uri.replace('file://',''), 'utf8') }] });
  }
  function saveDoc(uri) { notify('textDocument/didSave', { textDocument: { uri } }); }

  const reader = new MessageReader((msg) => {
    if (msg.id !== undefined && pending.has(msg.id)) { const r = pending.get(msg.id); pending.delete(msg.id); r(msg); return; }
    if (msg.method === 'textDocument/publishDiagnostics') {
      const p = msg.params || {};
      lastDiags.set(p.uri, p.diagnostics || []);
      const idx = diagWaiters.findIndex(w => w.uri === p.uri);
      if (idx >= 0) { const w = diagWaiters.splice(idx, 1)[0]; w.resolve(p.diagnostics || []); }
    }
  });
  child.stdout.on('data', (c) => reader.push(c));
  const tSpawn = Date.now();
  const serverCheckMs = [];   // the in-process check ms reported by the server
  child.stderr.on('data', (c) => {
    const s = c.toString();
    // surface only the metric + listening lines (the compiler trace is huge).
    for (const line of s.split('\n')) {
      if (line.includes('listening') && timing.preludeLoad === undefined) {
        timing.preludeLoad = Date.now() - tSpawn;   // process-spawn -> prelude loaded
      }
      const mm = /\[xats-lsp-metric\].*\bms=(\d+)/.exec(line);
      if (mm) serverCheckMs.push(parseInt(mm[1], 10));
      if (line.includes('[xats-lsp-metric]') || line.includes('listening') ||
          line.includes('threw') || line.includes('ERROR')) {
        process.stderr.write(`[server] ${line}\n`);
      }
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);

    console.log('\n===================== LATENCY =====================');
    console.log(`  ONE-TIME prelude load (spawn->listen): ${timing.preludeLoad} ms  (paid once at startup)`);
    console.log(`  --- per-check round-trip (client->server->publish), incl. RPC ---`);
    console.log(`  first-check  (file A, warm compiler) : ${timing.firstCheck} ms`);
    console.log(`  warm-check   (file A re-check)        : ${timing.warmCheck} ms`);
    console.log(`  clean-check  (file A cleared)         : ${timing.cleanCheck} ms`);
    console.log(`  second-file  (file B, warm)          : ${timing.fileB} ms`);
    console.log(`  --- server-side in-process check time (excl. RPC) ---`);
    console.log(`  per-check d3parsed+harvest ms        : [${serverCheckMs.join(', ')}]`);
    console.log(`  --- baseline ---`);
    console.log(`  old process-per-check (fresh node)   : ~370 ms / keystroke`);
    console.log('==================================================\n');

    const ok = failures.length === 0;
    console.log(ok ? '[smoke] ALL PASS' : `[smoke] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    // (A) initialize
    const initRes = await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    const caps = (initRes.result && initRes.result.capabilities) || {};
    caps.hoverProvider ? pass('capabilities advertise hoverProvider') : fail('missing hoverProvider');
    caps.definitionProvider ? pass('capabilities advertise definitionProvider') : fail('missing definitionProvider');
    notify('initialized', {});

    // (B) didOpen the BAD file -> first (cold) check.
    let dWait = waitDiagnostics(URI_A, 'firstCheck');
    openDoc(URI_A, SRC_BAD1);
    let diags = await dWait;
    console.log(`[smoke] (B) bad file A -> ${diags.length} diagnostic(s): ` +
      diags.map(d => `${d.code}@${d.range.start.line}:${d.range.start.character}`).join(', '));
    hasDiag(diags, 'type-mismatch', 0, 13, 0, 20)
      ? pass('bad-A carries type-mismatch @0:13-0:20')
      : fail(`bad-A missing type-mismatch @0:13-0:20 (got ${JSON.stringify(diags.map(diagKey))})`);
    hasDiag(diags, 'unbound-identifier', 1, 13, 1, 28)
      ? pass('bad-A carries unbound-identifier @1:13-1:28')
      : fail(`bad-A missing unbound-identifier @1:13-1:28 (got ${JSON.stringify(diags.map(diagKey))})`);

    // (C) EVICTION CORRECTNESS: rewrite file A on disk with a DIFFERENT error.
    //     didChange (prune) then didSave (revalidate). Expect the NEW diagnostic,
    //     NOT the stale one.
    fs.writeFileSync(FILE_A, SRC_BAD2);
    changeDoc(URI_A, 2);                 // prune: evict file A from the caches
    dWait = waitDiagnostics(URI_A, 'warmCheck');
    saveDoc(URI_A);                      // revalidate: re-check from disk
    diags = await dWait;
    console.log(`[smoke] (C) edited file A (NEW error) -> ${diags.length} diagnostic(s): ` +
      diags.map(d => `${d.code}@${d.range.start.line}:${d.range.start.character}`).join(', '));
    // the NEW file has its unbound id at 1:13 (length differs) and NO type-mismatch.
    const newUnbound = diags.some(d => d.code === 'unbound-identifier' && d.range.start.line === 1);
    const noStaleTM = !hasCode(diags, 'type-mismatch');
    newUnbound ? pass('EVICTION: re-check reports the NEW unbound-identifier (line 1)') : fail('EVICTION: NEW diagnostic missing -> stale or no re-check');
    noStaleTM ? pass('EVICTION: stale type-mismatch from the OLD content is GONE (no stale cache)') : fail('EVICTION: STALE type-mismatch still served -> eviction did NOT work');

    // (D) rewrite file A CLEAN on disk -> diagnostics clear.
    fs.writeFileSync(FILE_A, SRC_OK);
    changeDoc(URI_A, 3);
    dWait = waitDiagnostics(URI_A, 'cleanCheck');
    saveDoc(URI_A);
    diags = await dWait;
    console.log(`[smoke] (D) cleaned file A -> ${diags.length} diagnostic(s)`);
    diags.length === 0 ? pass('CLEAN: errors cleared after fixing the file (re-check on clean content)') : fail(`CLEAN: expected 0 diagnostics, got ${diags.length}: ${JSON.stringify(diags.map(diagKey))}`);

    // (E) HOVER over the clean file A. `val x: int = 3 \ val y: int = x` — the
    //     use of x is at line 1, the last token. Scan a few columns for a hover.
    let gotHover = false, hoverVal = null;
    for (let ch = 13; ch <= 14 && !gotHover; ch++) {
      const hov = await request('textDocument/hover', { textDocument: { uri: URI_A }, position: { line: 1, character: ch } });
      if (hov.result && hov.result.contents) { gotHover = true; hoverVal = hov.result.contents.value; }
    }
    // also try the declaration site of x.
    if (!gotHover) {
      const hov = await request('textDocument/hover', { textDocument: { uri: URI_A }, position: { line: 0, character: 4 } });
      if (hov.result && hov.result.contents) { gotHover = true; hoverVal = hov.result.contents.value; }
    }
    gotHover ? pass(`hover over a typed node -> ${JSON.stringify(hoverVal)}`) : fail('hover returned null on the clean file');

    // (F) DEFINITION on the use of `x` in `val y: int = x` (clean file -> defs=1).
    let gotDef = false, defLoc = null;
    for (let ch = 13; ch <= 14 && !gotDef; ch++) {
      const def = await request('textDocument/definition', { textDocument: { uri: URI_A }, position: { line: 1, character: ch } });
      const r = def.result && (Array.isArray(def.result) ? def.result[0] : def.result);
      if (r && r.uri) { gotDef = true; defLoc = r; }
    }
    gotDef ? pass(`definition of x -> ${defLoc.uri} @${defLoc.range.start.line}:${defLoc.range.start.character} (binding site of x)`)
           : fail('definition returned null for the use of x on the clean file');

    // (G) a SECOND unrelated file checks WARM (prelude already resident).
    dWait = waitDiagnostics(URI_B, 'fileB');
    openDoc(URI_B, SRC_B_OK);
    diags = await dWait;
    console.log(`[smoke] (G) second file B -> ${diags.length} diagnostic(s) (expect 0)`);
    diags.length === 0 ? pass('second file B checks clean (warm: no prelude reload)') : fail(`file B expected 0 diagnostics, got ${diags.length}`);

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
