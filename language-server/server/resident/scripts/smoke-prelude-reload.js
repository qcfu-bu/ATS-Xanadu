#!/usr/bin/env node
/*
 * PRELUDE IN-PROCESS RELOAD wiring smoke test for the RESIDENT server.
 *
 * Proves the "workspace IS the prelude / $XATSHOME" edge case is handled by an
 * IN-PROCESS reload (not a server restart): saving a file that resolves UNDER
 * $XATSHOME triggers
 *     reload_prelude()  ->  xglobal_reset() + replay the startup prelude-load
 *                           sequence + re-snapshot,
 * after which the server clears its per-uri index / depgraph / signature map and
 * RE-VALIDATES every open document, publishing fresh diagnostics.
 *
 * Flow:
 *   1. initialize.
 *   2. open a NORMAL workspace .dats with a known type error -> assert it gets a
 *      diagnostic (proves the warm in-process check works pre-reload).
 *   3. send a didSave for a path UNDER $XATSHOME ($XATSHOME/prelude/SATS/
 *      gint000.sats) WITHOUT modifying that file. The save notification ALONE
 *      must trigger the prelude-reload path (detection -> reload -> re-validate).
 *   4. assert:
 *        (a) the server logs `reload_prelude` on stderr (detection + reload fired);
 *        (b) a FRESH publishDiagnostics fires for the open workspace doc
 *            (re-validate-all), still carrying its type error (prelude intact);
 *        (c) the server stays HEALTHY: a follow-up hover request still answers
 *            (the reloaded prelude is usable).
 *
 * It NEVER modifies the real prelude file on disk — the bare didSave notification
 * is enough to exercise detection -> reload -> re-validate-all, so the real
 * prelude is never corrupted.
 *
 * Spawns the server WITH `node --stack-size=8801`. Exit 0 = all pass.
 */
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const HERE = __dirname;
const RESIDENT = path.resolve(HERE, '..');
const XATSHOME = process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu';
const SERVER = process.env.RESIDENT_SERVER ||
  path.join(RESIDENT, 'BUILD', 'xats-lsp-resident.opt1.js');
const NODE_ARGS = ['--stack-size=8801'];
const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '120000', 10);

// a real $XATSHOME prelude file. We only SAVE it (never modify it).
const PRELUDE_FILE = path.join(XATSHOME, 'prelude', 'SATS', 'gint000.sats');
const PRELUDE_URI = 'file://' + PRELUDE_FILE;

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-preload-'));
const FILE_A = path.join(WS, 'work.dats');
const URI_A = 'file://' + FILE_A;
// a known type-mismatch: int = string. Stable across prelude reload (the
// prelude is intact, so the error stays).
const SRC_A = 'val x: int = "boom"\n';

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
function fail(msg) { failures.push(msg); console.error(`[preload] FAIL: ${msg}`); }
function pass(msg) { console.log(`[preload] PASS: ${msg}`); }
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${s.line},${s.character}-${e.line},${e.character}`;
}
function hasCode(diags, code) { return diags.some(d => d.code === code); }

function main() {
  if (!fs.existsSync(PRELUDE_FILE)) {
    fail(`prelude file missing (cannot exercise $XATSHOME save): ${PRELUDE_FILE}`);
    process.exit(1);
  }
  // record the prelude file's mtime/size so we can PROVE we never touched it.
  const preStat = fs.statSync(PRELUDE_FILE);

  fs.writeFileSync(FILE_A, SRC_A);

  console.log(`[preload] server  : ${SERVER}`);
  console.log(`[preload] XATSHOME: ${XATSHOME}`);
  console.log(`[preload] prelude : ${PRELUDE_FILE} (will SAVE, never modify)`);
  console.log(`[preload] ws      : ${WS}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME }),
  });

  let done = false, nextId = 100;
  let sawReloadLog = false;
  const pending = new Map();
  const diagWaiters = [];

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
  // save WITHOUT a prior didOpen / didChange — this is the key: a $XATSHOME
  // file is saved that the server never had open, and the bare save notification
  // alone must trigger the prelude-reload path.
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
      if (line.includes('reload_prelude')) sawReloadLog = true;
      if (line.includes('[xats-lsp-metric]') || line.includes('prelude immutable') ||
          line.includes('reload_prelude') || line.includes('threw') || line.includes('ERROR')) {
        process.stderr.write(`[server] ${line}\n`);
      }
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    // PROVE the real prelude file was never modified.
    try {
      const postStat = fs.statSync(PRELUDE_FILE);
      if (postStat.mtimeMs === preStat.mtimeMs && postStat.size === preStat.size) {
        pass('real prelude file UNCHANGED on disk (mtime+size identical) -> not corrupted');
      } else {
        fail(`real prelude file CHANGED on disk! (mtime ${preStat.mtimeMs}->${postStat.mtimeMs}, size ${preStat.size}->${postStat.size})`);
      }
    } catch (e) { fail('could not re-stat prelude file: ' + e); }
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[preload] ALL PASS' : `\n[preload] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // 1) open a normal workspace doc with a type error -> gets a diagnostic.
    let w = waitDiagnostics(URI_A);
    openDoc(URI_A, SRC_A);
    let d = await w;
    console.log(`[preload] (1) open work.dats (bad) -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    hasCode(d, 'type-mismatch')
      ? pass('1: warm in-process check works -> type-mismatch reported (pre-reload)')
      : fail(`1: expected a type-mismatch pre-reload, got ${JSON.stringify(d.map(diagKey))}`);

    // 2) save a $XATSHOME prelude file (NEVER opened, NEVER modified). The bare
    //    save must trigger the prelude reload + re-validate-all. We expect a
    //    FRESH publishDiagnostics for the open work.dats.
    w = waitDiagnostics(URI_A);
    saveDoc(PRELUDE_URI);
    d = await w;
    console.log(`[preload] (2) didSave $XATSHOME prelude file -> work.dats re-validated -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);

    // (a) the reload path fired (stderr log).
    sawReloadLog
      ? pass('2a: server logged `reload_prelude` (detection -> in-process reload fired)')
      : fail('2a: no `reload_prelude` log seen -> save under $XATSHOME did NOT trigger the reload path');
    // (b) the open doc was re-validated (fresh diagnostics) and still has its error
    //     (prelude intact after reload).
    hasCode(d, 'type-mismatch')
      ? pass('2b: open work.dats RE-VALIDATED after prelude reload (fresh diagnostic, prelude intact)')
      : fail(`2b: expected the type-mismatch to persist after reload, got ${JSON.stringify(d.map(diagKey))}`);

    // (c) health check: a follow-up hover still answers (reloaded prelude usable).
    const hov = await request('textDocument/hover', {
      textDocument: { uri: URI_A }, position: { line: 0, character: 4 }
    });
    const healthy = hov && hov.result !== undefined;
    healthy && hov.result !== null
      ? pass('2c: server HEALTHY after reload -> hover still answers (reloaded prelude usable)')
      : (healthy
          ? pass('2c: server HEALTHY after reload -> hover responded (null is a valid no-hover answer)')
          : fail('2c: hover request did not return a well-formed response after reload'));

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
