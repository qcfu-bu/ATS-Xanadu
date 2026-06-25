#!/usr/bin/env node
/*
 * "Formerly-CFAIL" smoke for the RESIDENT in-process ATS3 LSP server
 * (BUILD/xats-lsp-resident.opt1.js).  FIX-INTEGRATED regression guard.
 *
 * HISTORY: server/DATS/xats_lsp_check.dats used to make the front-end *abort*
 * with XATS000_cfail — a non-exhaustive case in `unify00_s2typ` reached when an
 * under-applied type constructor (here `argv`, via the `#if defq(_XATS2JS_)`
 * guard) is used in a called position. The .cats `runValidation` CATCHES such an
 * abort, logs calmly, and publishes one `Information` "could not analyze this
 * file ..." diagnostic so one bad file never takes down the session. That
 * defensive catch still exists for any genuine future abort (e.g. OOM on
 * pathological inputs).
 *
 * Hongwei fixed the compiler (master b362d545f / 813611246, merged into this
 * branch): trans12 now routes a function's result type through
 * `trans12_s1exp_impr`, and `tread12_staexp`'s `f0_impr`/`f0_prgm` always flag an
 * improper static expression as an ordinary `errck` error — so the file is now
 * ANALYZED GRACEFULLY instead of aborting. This smoke proves the fix is
 * integrated end-to-end through the rebuilt lib2xatsopt.js + resident server:
 *
 *   (A) opening server/DATS/xats_lsp_check.dats now yields ORDINARY diagnostics
 *       (genuine front-end errors — it is a link-only driver file, so standalone
 *       it has unresolved refs), with NO "could not analyze" abort-sentinel and
 *       NO calm-abort log line. If the lib ever reverts to a pre-fix build, the
 *       abort returns and these assertions fail — catching the regression.
 *   (B) the server stays HEALTHY: a follow-up check of an ORDINARY .dats still
 *       works (0 diagnostics for a clean file; the resident is not poisoned).
 *
 * Exit 0 = all pass.
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
const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '180000', 10);
const XATSHOME = process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu';

// the compiler-internal file that ABORTS (XATS000_cfail).
const CFAIL_FILE = path.join(XATSHOME, 'language-server', 'server', 'DATS', 'xats_lsp_check.dats');
const CFAIL_URI = 'file://' + CFAIL_FILE;

// LSP DiagnosticSeverity.Information === 3.
const SEV_INFORMATION = 3;

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
function fail(msg) { failures.push(msg); console.error(`[cfail] FAIL: ${msg}`); }
function pass(msg) { console.log(`[cfail] PASS: ${msg}`); }

// --- a real on-disk OK file for the health check ---------------------------
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-cfail-'));
const OK_FILE = path.join(WS, 'ok.dats');
const OK_URI = 'file://' + OK_FILE;
const OK_SRC = 'val x: int = 3\nval y: int = x\n';

// --- driver ----------------------------------------------------------------
function main() {
  fs.writeFileSync(OK_FILE, OK_SRC);

  console.log(`[cfail] server : ${SERVER}`);
  console.log(`[cfail] cfail  : ${CFAIL_FILE}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }
  if (!fs.existsSync(CFAIL_FILE)) { fail(`cfail file missing: ${CFAIL_FILE}`); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: XATSHOME }),
  });

  let done = false;
  let nextId = 100;
  const pending = new Map();
  const diagWaiters = [];
  let sawCalmLog = false;

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
      if (line.includes('could not analyze')) { sawCalmLog = true; process.stderr.write(`[server] ${line}\n`); }
      else if (line.includes('[xats-lsp-metric]')) process.stderr.write(`[server] ${line}\n`);
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[cfail] ALL PASS' : `\n[cfail] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // (A) open the formerly-aborting compiler-internal file.
    const dWaitCfail = waitDiagnostics(CFAIL_URI);
    openDoc(CFAIL_URI, fs.readFileSync(CFAIL_FILE, 'utf8'));
    const diags = await dWaitCfail;
    console.log(`\n[cfail] published ${diags.length} diagnostic(s) for the formerly-aborting file:`);
    for (const d of diags) console.log(`  sev=${d.severity}  "${(d.message || '').slice(0, 80)}..."`);

    // it is now ANALYZED: at least one ordinary diagnostic (a link-only driver
    // file has unresolved refs standalone — that's expected; the point is no abort).
    (diags.length >= 1)
      ? pass(`file analyzed gracefully: ${diags.length} ordinary diagnostic(s), no abort`)
      : fail(`expected >=1 ordinary diagnostic, got ${diags.length}`);

    // NONE is the abort-sentinel (Information severity + "could not analyze").
    const sentinel = diags.find(d =>
      d.severity === SEV_INFORMATION && /could not analyze this file/i.test(d.message || ''));
    (!sentinel)
      ? pass('no "could not analyze" abort-sentinel — the cfail is gone (fix integrated)')
      : fail(`abort-sentinel still present: "${sentinel.message}" — pre-fix lib? fix NOT integrated`);

    // every diagnostic is a genuine front-end Error (severity 1), not a degraded note.
    (diags.length >= 1 && diags.every(d => d.severity === 1))
      ? pass('all diagnostics are severity Error (genuine front-end analysis output)')
      : fail(`some diagnostics are not severity Error: ${JSON.stringify(diags.map(d => d.severity))}`);

    // the server did NOT take the calm-abort log path (no XATS000_cfail caught).
    (!sawCalmLog)
      ? pass('server did NOT log a compiler abort (no XATS000_cfail)')
      : fail('server logged "could not analyze" — the file still aborts (pre-fix lib?)');

    // (B) HEALTH: a follow-up ordinary file still checks fine (0 diagnostics).
    const dWaitOk = waitDiagnostics(OK_URI);
    openDoc(OK_URI, OK_SRC);
    const okDiags = await dWaitOk;
    (okDiags.length === 0)
      ? pass('session stays healthy: a follow-up ordinary .dats checks clean (0 diagnostics)')
      : fail(`follow-up ordinary file reported ${okDiags.length} diagnostic(s): ${JSON.stringify(okDiags)}`);

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
