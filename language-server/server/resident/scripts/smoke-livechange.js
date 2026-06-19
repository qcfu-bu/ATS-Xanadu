#!/usr/bin/env node
/*
 * LIVE-ON-CHANGE smoke for the RESIDENT in-process ATS3 LSP server
 * (BUILD/xats-lsp-resident.opt1.js).  Workstream R1 / P4 polish.
 *
 * Proves the server validates the UNSAVED in-memory buffer on `didChange`
 * (debounced), NOT the stale file on disk:
 *
 *   1) write a CLEAN file to disk; didOpen it -> 0 diagnostics.
 *   2) DISK STAYS CLEAN for the rest of the test (we never write the error to
 *      disk, and never call didSave). Send a `didChange` whose new text (the
 *      unsaved buffer) introduces a TYPE ERROR. After the ~300 ms debounce a
 *      fresh `publishDiagnostics` MUST arrive reporting that error — from the
 *      buffer, since the disk file is still clean.
 *   3) prove-it's-the-buffer cross-check: with the error still only in the
 *      buffer, the on-disk file is re-read and asserted to be byte-for-byte the
 *      original CLEAN text (so the diagnostic could only have come from the
 *      unsaved buffer).
 *   4) send a `didChange` back to CLEAN text -> diagnostics clear (empty array),
 *      proving the live path re-checks the latest buffer both ways.
 *
 * No didSave is ever sent. Exit 0 = all pass.
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

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-livechg-'));
const FILE = path.join(WS, 'live.dats');
const URI = 'file://' + FILE;

// The ON-DISK content stays this CLEAN text the whole test.
const SRC_DISK_CLEAN = 'val x: int = 3\nval y: int = x\n';
// The UNSAVED buffer that introduces a type error (string where int is wanted).
const SRC_BUF_BAD = 'val x: int = "oops live edit"\nval y: int = x\n'; // type-mismatch @0:13
// A second unsaved buffer that is clean again (different from disk but valid).
const SRC_BUF_CLEAN2 = 'val x: int = 42\nval y: int = x\n';

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
function fail(msg) { failures.push(msg); console.error(`[livechg] FAIL: ${msg}`); }
function pass(msg) { console.log(`[livechg] PASS: ${msg}`); }
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${s.line},${s.character}-${e.line},${e.character}`;
}
function hasCode(diags, code) { return diags.some(d => d.code === code); }

function main() {
  fs.writeFileSync(FILE, SRC_DISK_CLEAN);

  console.log(`[livechg] server : ${SERVER}`);
  console.log(`[livechg] ws     : ${WS}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu' }),
  });

  let done = false;
  let nextId = 100;
  const pending = new Map();
  const diagWaiters = [];
  const lastDiags = new Map();

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
    notify('textDocument/didOpen', { textDocument: { uri, languageId: 'ats3', version: 1, text } });
  }
  // didChange carrying the FULL new buffer text (the unsaved edit). NEVER writes
  // to disk and NEVER calls didSave.
  let ver = 1;
  function changeDoc(uri, text) {
    ver += 1;
    notify('textDocument/didChange', {
      textDocument: { uri, version: ver },
      contentChanges: [{ text }],
    });
  }

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
  child.stderr.on('data', (c) => {
    for (const line of c.toString().split('\n')) {
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
    const ok = failures.length === 0;
    console.log(ok ? '[livechg] ALL PASS' : `[livechg] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    // (A) initialize
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // (B) didOpen the CLEAN file -> expect 0 diagnostics.
    let dWait = waitDiagnostics(URI);
    openDoc(URI, SRC_DISK_CLEAN);
    let diags = await dWait;
    console.log(`[livechg] (B) didOpen clean -> ${diags.length} diag(s)`);
    diags.length === 0
      ? pass('clean open -> no diagnostics')
      : fail(`clean open expected 0 diagnostics, got ${diags.length}: ${JSON.stringify(diags.map(diagKey))}`);

    // (C) LIVE EDIT: didChange the buffer to introduce a type error. NO disk
    //     write, NO save. After the debounce a fresh publishDiagnostics must
    //     carry the type-mismatch from the UNSAVED buffer.
    dWait = waitDiagnostics(URI);
    changeDoc(URI, SRC_BUF_BAD);
    diags = await dWait;
    console.log(`[livechg] (C) didChange -> bad buffer -> ${diags.length} diag(s): [${diags.map(diagKey).join(', ')}]`);
    hasCode(diags, 'type-mismatch')
      ? pass('LIVE: type-mismatch reported from the UNSAVED buffer (no save, debounced)')
      : fail(`LIVE: expected a type-mismatch from the buffer, got ${JSON.stringify(diags.map(diagKey))}`);
    // the error token "oops live edit" starts at byte/col 13 on line 0.
    const tmAt0 = diags.some(d => d.code === 'type-mismatch' && d.range.start.line === 0 && d.range.start.character === 13);
    tmAt0
      ? pass('LIVE: type-mismatch range @0:13 matches the buffer position')
      : fail(`LIVE: type-mismatch not at @0:13 (got ${JSON.stringify(diags.map(diagKey))})`);

    // (D) PROVE IT'S THE BUFFER: the on-disk file is still the original CLEAN
    //     text (we never wrote the error to disk).
    const onDisk = fs.readFileSync(FILE, 'utf8');
    onDisk === SRC_DISK_CLEAN
      ? pass('PROOF: on-disk file is still the original CLEAN text -> diagnostic came from the buffer, not disk')
      : fail(`PROOF: on-disk file was unexpectedly modified to ${JSON.stringify(onDisk)}`);

    // (E) LIVE EDIT BACK TO CLEAN: didChange to a (different) valid buffer ->
    //     diagnostics clear.
    dWait = waitDiagnostics(URI);
    changeDoc(URI, SRC_BUF_CLEAN2);
    diags = await dWait;
    console.log(`[livechg] (E) didChange -> clean buffer -> ${diags.length} diag(s)`);
    diags.length === 0
      ? pass('LIVE: editing the buffer back to valid clears the diagnostics')
      : fail(`LIVE: expected 0 diagnostics after clean edit, got ${diags.length}: ${JSON.stringify(diags.map(diagKey))}`);

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
