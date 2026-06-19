#!/usr/bin/env node
/*
 * R2c WHOLE-PROJECT STALOAD INDEX (complete transitive cascade) test.
 *
 * Proves the WHOLE point of R2c: the server scans the workspace and parses every
 * source file's #staload/#include directives to build a PROJECT-WIDE dependency
 * graph — independent of which files have actually been type-checked. The
 * checked-files depgraph (R1's LSP_dependencies) only knows about edges it saw
 * while checking an OPEN file, so a dependent that has never been opened (and a
 * dependency two hops away through an unopened middle file) is invisible to it.
 * The project index makes the reverse cascade COMPLETE.
 *
 * Scenario — a 3-file chain  A <- B <- C  (C #staloads B, B #staloads A):
 *   - ONLY C is ever opened. B and A are NEVER opened and NEVER type-checked,
 *     so the checked-files depgraph has NO A-related edge at all.
 *   - A watched-files change event for A must still cascade transitively to C:
 *     A -> B -> C in the PROJECT reverse graph. The server eagerly evicts the
 *     closure and RE-VALIDATES the open C (a fresh publishDiagnostics for C).
 *
 * Assertions:
 *   (1) the project index was built at startup (scan log: 3 files, edges).
 *   (2) a watched change to A re-validates C — a FRESH publishDiagnostics for C
 *       arrives in response to an event that names ONLY A (never B/C). This is
 *       only possible if the project index found the transitive A->B->C edge,
 *       because B and A were never opened/checked (the checked-files depgraph
 *       could not connect them).
 *   (3) the server's cascade log shows `affected=3` for the A event (A + B + C),
 *       i.e. the transitive reverse closure reached C.
 *
 * (Note: a transitive *type* error does not surface in C's own diagnostics — C
 * only sees B's interface and C's harvest walks only C's AST — so the load-bearing
 * proof is the transitive RE-VALIDATION / cascade reach, exactly the capability
 * R2c adds, per the architecture doc's "Or assert the built project graph has the
 * expected reverse edges".)
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

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-projidx-'));
const A = path.join(WS, 'A.sats');
const B = path.join(WS, 'B.sats');
const C = path.join(WS, 'C.dats');
const URI_A = 'file://' + A;
const URI_C = 'file://' + C;

// A <- B <- C. C only #staloads B; B only #staloads A. C uses bfun (from B).
const A_OK  = 'fun afun(x: int): int\n';
const A_BAD = 'fun afun(x: int, y: int): int\n';   // edit A (its directive set is unchanged)
const B_SRC = '#staload "./A.sats"\nfun bfun(y: int): int\n';
const C_SRC = '#staload "./B.sats"\nval c: int = bfun(2)\n';

// LSP FileChangeType.Changed
const FCT_CHANGED = 2;

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
function fail(msg) { failures.push(msg); console.error(`[projidx] FAIL: ${msg}`); }
function pass(msg) { console.log(`[projidx] PASS: ${msg}`); }

function main() {
  fs.writeFileSync(A, A_OK);
  fs.writeFileSync(B, B_SRC);
  fs.writeFileSync(C, C_SRC);

  console.log(`[projidx] server : ${SERVER}`);
  console.log(`[projidx] ws     : ${WS}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME }),
  });

  let done = false, nextId = 100;
  const pending = new Map();
  const diagWaiters = [];
  let scanLine = null;
  let lastCascade = null;   // { affected, evicted, revalidated } from the A event

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
      if (line.includes('project-index:')) scanLine = line.trim();
      const m = /watched \w+ .*A\.sats -> affected=(\d+) evicted=(\d+) revalidated=(\d+)/.exec(line);
      if (m) lastCascade = { affected: +m[1], evicted: +m[2], revalidated: +m[3] };
      if (line.includes('project-index') || line.includes('watched ') ||
          line.includes('threw') || line.includes('ERROR')) {
        process.stderr.write(`[server] ${line.trim()}\n`);
      }
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[projidx] ALL PASS' : `\n[projidx] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, workspaceFolders: [{ uri: 'file://' + WS, name: 'ws' }], capabilities: {} });
    notify('initialized', {});

    // give the deferred (setImmediate) workspace scan a beat to run.
    await new Promise(r => setTimeout(r, 300));
    console.log(`[projidx] (scan) ${scanLine || '(no scan log seen yet)'}`);
    (scanLine && /files=3\b/.test(scanLine) && /fwd=2\b/.test(scanLine) && /rev=2\b/.test(scanLine))
      ? pass('1: project index scanned all 3 files and built the 2 forward + 2 reverse staload edges (A<-B<-C) WITHOUT any file being opened')
      : fail(`1: project scan did not report the expected 3-file / fwd=2 / rev=2 index. saw: ${scanLine}`);

    // open ONLY C. B and A are never opened, never type-checked.
    let w = waitDiagnostics(URI_C);
    openDoc(URI_C, C_SRC);
    let d = await w;
    console.log(`[projidx] (2) open ONLY C -> ${d.length} diag(s) [${d.map(x => x.code).join(',')}]`);

    // watched-files change to A. Event names ONLY A. The checked-files depgraph
    // has NO A edge (A and B were never checked); only the PROJECT index connects
    // A -> B -> C. A FRESH publishDiagnostics for C must arrive (eager transitive
    // re-validate of the only open doc in A's project-reverse closure).
    fs.writeFileSync(A, A_BAD);
    w = waitDiagnostics(URI_C);
    watchedChange(URI_A, FCT_CHANGED);
    // 5s guard: if no fresh C publish arrives, the transitive cascade failed.
    const revalidated = await Promise.race([
      w.then(diags => ({ ok: true, diags })),
      new Promise(r => setTimeout(() => r({ ok: false }), 5000)),
    ]);
    if (revalidated.ok) {
      pass('2: watched change to A (never-opened, 2 hops from C) EAGERLY re-validated the only-open C via the TRANSITIVE project edge A->B->C (a fresh publishDiagnostics for C arrived; the checked-files depgraph could NOT connect them since B/A were never checked)');
    } else {
      fail('2: NO fresh re-validation of C after a watched change to A -> the transitive project reverse edge A->B->C was not found (R2c cascade incomplete)');
    }

    console.log(`[projidx] (cascade) ${lastCascade ? JSON.stringify(lastCascade) : '(no cascade log)'}`);
    (lastCascade && lastCascade.affected >= 3 && lastCascade.revalidated >= 1)
      ? pass(`3: cascade log confirms the transitive reverse closure of A reached the whole chain (affected=${lastCascade.affected} >= 3: A+B+C) and re-validated the open dependent C (revalidated=${lastCascade.revalidated})`)
      : fail(`3: cascade did not reach the full A+B+C closure. saw: ${JSON.stringify(lastCascade)}`);

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
