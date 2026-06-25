#!/usr/bin/env node
/*
 * R2b WATCHED-FILES (eager eviction + cascade) test for the RESIDENT server.
 *
 * Proves the WHOLE point of R2b: the client's native file watcher fires a
 * `workspace/didChangeWatchedFiles` notification on an in-workspace EXTERNAL edit
 * (another editor, git pull/checkout, codegen, a formatter run outside the
 * editor). On that notification — and with NO `didChange`/`didSave`/`didOpen` for
 * the changed file — the server must EAGERLY evict the changed file + cascade to
 * every dependent (via the project index) and RE-VALIDATE the affected OPEN docs,
 * republishing fresh diagnostics. This is promptness on top of R2a's lazy
 * pre-check: the dependent's squiggles update the moment the change lands, not
 * only on the next time someone touches the dependent.
 *
 * The contrast with smoke-extedit.js (R2a) is deliberate: there, the dependent
 * was re-validated by a `didSave` ON THE DEPENDENT (the mtime pre-check fired
 * inside that save's check). HERE THE ONLY TRIGGER IS THE WATCHED-FILES EVENT FOR
 * THE STALOADED FILE — no editor event for either file after the initial opens.
 * If R2b were absent, the open `use.dats` would keep its stale clean diagnostics
 * until the user re-saved it.
 *
 *   1. open+validate use.dats (#staload lib.sats) clean -> 0 diags.
 *   2. EXTERNALLY rewrite lib.sats so use.dats no longer type-checks. Send a
 *      single workspace/didChangeWatchedFiles {uri: lib.sats, type: Changed}.
 *      NO didChange/didSave/didOpen for lib.sats OR use.dats. Assert the server
 *      eagerly re-validates the OPEN use.dats -> it now reports an error.
 *   3. EXTERNALLY revert lib.sats. Send the watched-files event again. Assert
 *      use.dats's diagnostics CLEAR (eager re-validate both ways).
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
const SERVER = process.env.RESIDENT_SERVER ||
  path.join(RESIDENT, 'BUILD', 'xats-lsp-resident.opt1.js');
const NODE_ARGS = ['--stack-size=8801'];
const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '120000', 10);
const XATSHOME = process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu';

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-watched-'));
const LIB = path.join(WS, 'lib.sats');
const USE = path.join(WS, 'use.dats');
const URI_LIB = 'file://' + LIB;
const URI_USE = 'file://' + USE;

const LIB_OK  = 'fun lfun(x: int): int\n';
const LIB_BAD = 'fun lfun(x: int, y: int): int\n';        // now needs 2 args
const USE_SRC = '#staload "./lib.sats"\nval z: int = lfun(5)\n'; // calls lfun w/ 1 arg

// LSP FileChangeType.
const FCT_CREATED = 1, FCT_CHANGED = 2, FCT_DELETED = 3;

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
function fail(msg) { failures.push(msg); console.error(`[watched] FAIL: ${msg}`); }
function pass(msg) { console.log(`[watched] PASS: ${msg}`); }
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${s.line},${s.character}-${e.line},${e.character}`;
}

function main() {
  fs.writeFileSync(LIB, LIB_OK);
  fs.writeFileSync(USE, USE_SRC);

  console.log(`[watched] server : ${SERVER}`);
  console.log(`[watched] ws     : ${WS}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME }),
  });

  let done = false, nextId = 100;
  const pending = new Map();
  const diagWaiters = [];
  let sawWatchedLog = false;

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
  // THE ONLY trigger this test uses to re-validate after an external edit: the
  // native client watcher's notification. NO didChange / didSave / didOpen.
  function watchedChange(uri, type) {
    notify('workspace/didChangeWatchedFiles', { changes: [{ uri, type }] });
  }

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
      if (line.includes('watched ')) sawWatchedLog = true;
      if (line.includes('[xats-lsp-metric]') || line.includes('watched ') ||
          line.includes('project-index') || line.includes('threw') || line.includes('ERROR')) {
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
    console.log(ok ? '\n[watched] ALL PASS' : `\n[watched] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, workspaceFolders: [{ uri: 'file://' + WS, name: 'ws' }], capabilities: {} });
    notify('initialized', {});

    // 1) open + validate use.dats clean (records its project edge use->lib too).
    let w = waitDiagnostics(URI_USE);
    openDoc(URI_USE, USE_SRC);
    let d = await w;
    console.log(`[watched] (1) open use.dats (clean) -> ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    d.length === 0
      ? pass('1: use.dats validates clean against the original lib.sats (cached; project edge use<-lib recorded)')
      : fail(`1: expected 0 diagnostics, got ${JSON.stringify(d.map(diagKey))}`);

    // 2) EXTERNALLY break lib.sats. Send ONLY a watched-files Changed event for
    //    lib.sats. NO editor event for lib.sats OR use.dats. The server must
    //    EAGERLY evict lib + cascade to use.dats (a dependent) and re-validate
    //    the OPEN use.dats -> it now reports an error.
    fs.writeFileSync(LIB, LIB_BAD);
    w = waitDiagnostics(URI_USE);
    watchedChange(URI_LIB, FCT_CHANGED);
    d = await w;
    console.log(`[watched] (2) external edit to lib.sats + watched event (NO editor event) -> use.dats: ${d.length} diag(s) [${d.map(diagKey).join(', ')}]`);
    d.length > 0
      ? pass('2: WATCHED event for lib.sats EAGERLY re-validated the open dependent use.dats with NO editor event -> error reported (eager evict + project cascade)')
      : fail('2: use.dats still clean after externally breaking its staloaded lib.sats + watched event -> eager cascade did NOT fire');

    // 3) EXTERNALLY revert lib.sats. Watched event again -> use.dats clears.
    fs.writeFileSync(LIB, LIB_OK);
    w = waitDiagnostics(URI_USE);
    watchedChange(URI_LIB, FCT_CHANGED);
    d = await w;
    console.log(`[watched] (3) external revert of lib.sats + watched event -> use.dats: ${d.length} diag(s)`);
    d.length === 0
      ? pass('3: WATCHED event after revert EAGERLY cleared the dependent use.dats diagnostics (eager cascade both ways)')
      : fail(`3: expected 0 diagnostics after revert, got ${JSON.stringify(d.map(diagKey))}`);

    sawWatchedLog
      ? pass('server logged the watched-files handler firing (eager path exercised)')
      : console.log('[watched] note: did not observe a "watched" stderr line (non-fatal)');

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
