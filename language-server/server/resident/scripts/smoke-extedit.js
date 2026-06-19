#!/usr/bin/env node
/*
 * R2a EXTERNAL-EDIT (content-validated cache) test for the RESIDENT server.
 *
 * Proves the WHOLE point of R2a: out-of-band edits — another editor, git
 * pull/checkout/rebase, codegen, a formatter run outside the editor — fire NO
 * `didChange`/`didOpen`, yet the server must NOT serve a stale cached check. The
 * mtime/size pre-check (statSync the target's staload closure before each check)
 * detects the on-disk drift, evicts the stale cache, and re-checks — with NO
 * editor event prompting the eviction.
 *
 * The contrast with smoke-resident.js is deliberate and load-bearing: that test
 * fires `didChange` (the R1 prune) before `didSave`. HERE WE NEVER FIRE didChange
 * (nor a fresh didOpen) for the externally-edited file. The only trigger is a
 * plain `didSave` (phase A) or validating a DEPENDENT (phase B). If the mtime
 * pre-check were absent, `d3parsed_of_fil*` would return the stale cached parse
 * and the new error would be missed (the exact R1 gap R2a closes).
 *
 *   (A) SINGLE-FILE out-of-band edit:
 *       1. open+validate A (clean) -> 0 diags. A is now cached + signature stamped.
 *       2. rewrite A on disk introducing a NEW error. Send NO didChange/didOpen.
 *       3. didSave(A) only -> server MUST report the NEW error (pre-check evicted
 *          the stale cache with no editor event).
 *       4. revert A on disk to clean. didSave(A) only -> diagnostics MUST clear.
 *
 *   (B) CROSS-FILE out-of-band edit:
 *       1. open+validate B (a .sats A staloads) clean, then open+validate A clean.
 *          The dependency pass records the A->B forward edge + B's signature.
 *       2. externally edit B on disk so the symbol A uses no longer type-checks.
 *          Send NO event for B.
 *       3. validate A (didSave A) -> A's pre-check walks its closure, sees B
 *          drifted, evicts B + cascades to A, re-checks A -> A MUST report an error.
 *
 * Spawns the server WITH `node --stack-size=8801` (the bundled compiler overflows
 * the default stack). Exit 0 = all pass.
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

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-extedit-'));
// phase A: a standalone file edited out-of-band.
const FILE_A = path.join(WS, 'solo.dats');
const URI_A = 'file://' + FILE_A;
// phase B: A2 staloads LIB; LIB is edited out-of-band to break A2.
const LIB = path.join(WS, 'lib.sats');
const A2  = path.join(WS, 'use.dats');
const URI_LIB = 'file://' + LIB;
const URI_A2  = 'file://' + A2;

const SOLO_OK  = 'val x: int = 3\nval y: int = x\n';
const SOLO_BAD = 'val x: int = "boom"\n';                 // type-mismatch @0:13

const LIB_OK  = 'fun lfun(x: int): int\n';
const LIB_BAD = 'fun lfun(x: int, y: int): int\n';        // now needs 2 args
const A2_SRC  = '#staload "./lib.sats"\nval z: int = lfun(5)\n'; // calls lfun with 1 arg

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

const failures = [];
function fail(msg) { failures.push(msg); console.error(`[extedit] FAIL: ${msg}`); }
function pass(msg) { console.log(`[extedit] PASS: ${msg}`); }
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${s.line},${s.character}-${e.line},${e.character}`;
}
function hasCode(diags, code) { return diags.some(d => d.code === code); }

function main() {
  fs.writeFileSync(FILE_A, SOLO_OK);
  fs.writeFileSync(LIB, LIB_OK);
  fs.writeFileSync(A2, A2_SRC);

  console.log(`[extedit] server : ${SERVER}`);
  console.log(`[extedit] ws     : ${WS}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu' }),
  });

  let done = false, nextId = 100;
  const pending = new Map();
  const diagWaiters = [];
  const statCounts = [];

  const timer = setTimeout(() => { if (!done) { fail(`timed out after ${TIMEOUT_MS}ms`); finish(); } }, TIMEOUT_MS);

  function send(msg) { child.stdin.write(encode(msg)); }
  function request(method, params) {
    const id = nextId++;
    return new Promise((resolve) => { pending.set(id, resolve); send({ jsonrpc: '2.0', id, method, params }); });
  }
  function notify(method, params) { send({ jsonrpc: '2.0', method, params }); }
  function waitDiagnostics(uri) {
    return new Promise((resolve) => { diagWaiters.push({ uri, resolve }); });
  }
  function openDoc(uri, text) {
    notify('textDocument/didOpen', { textDocument: { uri, languageId: uri.endsWith('.sats') ? 'ats' : 'ats3', version: 1, text } });
  }
  // IMPORTANT: this test deliberately uses ONLY didSave to trigger a re-validate.
  // It NEVER fires didChange for an externally-edited file (that would be the R1
  // event-driven prune; the whole point is to prove the mtime pre-check works
  // with NO such event).
  function saveDoc(uri) { notify('textDocument/didSave', { textDocument: { uri } }); }

  const reader = new MessageReader((msg) => {
    if (msg.id !== undefined && pending.has(msg.id)) { const r = pending.get(msg.id); pending.delete(msg.id); r(msg); return; }
    if (msg.method === 'textDocument/publishDiagnostics') {
      const p = msg.params || {};
      const idx = diagWaiters.findIndex(w => w.uri === p.uri);
      if (idx >= 0) { const w = diagWaiters.splice(idx, 1)[0]; w.resolve(p.diagnostics || []); }
    }
  });
  child.stdout.on('data', (c) => reader.push(c));
  child.stderr.on('data', (c) => {
    for (const line of c.toString().split('\n')) {
      const sm = /\bstats=(\d+)/.exec(line);
      if (sm) statCounts.push(parseInt(sm[1], 10));
      if (line.includes('[xats-lsp-metric]') || line.includes('prelude immutable') ||
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
    console.log('\n=================== R2a STATS ===================');
    console.log(`  per-check statSync counts (workspace closure only): [${statCounts.join(', ')}]`);
    const mx = statCounts.length ? Math.max(...statCounts) : 0;
    console.log(`  max stat-count = ${mx}  (must stay small: never the ~100 prelude files)`);
    mx <= 10 ? pass(`stat-count stayed small (max ${mx}) -> prelude NOT statted`)
             : fail(`stat-count too high (max ${mx}) -> prelude may be getting statted`);
    console.log('================================================\n');
    const ok = failures.length === 0;
    console.log(ok ? '[extedit] ALL PASS' : `[extedit] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // ============ (A) SINGLE-FILE out-of-band edit ============
    // 1) open+validate A clean.
    let w = waitDiagnostics(URI_A);
    openDoc(URI_A, SOLO_OK);
    let d = await w;
    console.log(`[extedit] (A1) open solo (clean) -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    d.length === 0 ? pass('A1: clean file validates with 0 diagnostics (cached + signature stamped)')
                   : fail(`A1: expected 0 diagnostics, got ${JSON.stringify(d.map(diagKey))}`);

    // 2) rewrite A on disk with a NEW error. NO didChange / NO didOpen.
    fs.writeFileSync(FILE_A, SOLO_BAD);
    // 3) ONLY didSave -> the mtime pre-check must evict the stale clean cache.
    w = waitDiagnostics(URI_A);
    saveDoc(URI_A);
    d = await w;
    console.log(`[extedit] (A3) out-of-band edit (NO didChange) + didSave -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    hasCode(d, 'type-mismatch')
      ? pass('A3: OUT-OF-BAND edit detected with NO editor event -> NEW type-mismatch reported (mtime pre-check evicted the stale cache)')
      : fail(`A3: stale clean cache served -> NEW error MISSED. got ${JSON.stringify(d.map(diagKey))}`);

    // 4) revert A on disk to clean. ONLY didSave -> diagnostics clear.
    fs.writeFileSync(FILE_A, SOLO_OK);
    w = waitDiagnostics(URI_A);
    saveDoc(URI_A);
    d = await w;
    console.log(`[extedit] (A4) revert on disk (NO didChange) + didSave -> ${d.length} diag(s)`);
    d.length === 0
      ? pass('A4: out-of-band REVERT detected -> diagnostics cleared (pre-check both ways)')
      : fail(`A4: expected 0 diagnostics after revert, got ${JSON.stringify(d.map(diagKey))}`);

    // ============ (B) CROSS-FILE out-of-band edit ============
    // 1) validate LIB clean, then A2 clean (records A2 -> LIB edge + LIB signature).
    w = waitDiagnostics(URI_LIB);
    openDoc(URI_LIB, LIB_OK);
    d = await w;
    console.log(`[extedit] (B1a) open lib (clean) -> ${d.length} diag(s)`);

    w = waitDiagnostics(URI_A2);
    openDoc(URI_A2, A2_SRC);
    d = await w;
    console.log(`[extedit] (B1b) open use (staloads lib, clean) -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    d.length === 0 ? pass('B1: use.dats checks clean against the original lib (A2->LIB edge + LIB signature recorded)')
                   : console.log(`[extedit] note: use.dats not clean initially: ${JSON.stringify(d.map(diagKey))}`);

    // 2) externally edit LIB so lfun now needs 2 args. NO event for LIB.
    fs.writeFileSync(LIB, LIB_BAD);
    // 3) validate A2 (didSave A2) -> A2's pre-check walks its closure, sees LIB
    //    drifted, evicts LIB + cascades to A2, re-checks A2 -> A2 reports an error.
    w = waitDiagnostics(URI_A2);
    saveDoc(URI_A2);
    d = await w;
    console.log(`[extedit] (B3) out-of-band edit to LIB (NO event) + validate use -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    d.length > 0
      ? pass('B3: CROSS-FILE out-of-band edit to a staloaded file detected with NO event -> dependent re-checked and now reports an error')
      : fail('B3: dependent still clean after externally breaking its staloaded dep -> stale cross-file cache (pre-check did NOT walk the closure)');

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
