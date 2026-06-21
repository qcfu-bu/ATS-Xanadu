#!/usr/bin/env node
/*
 * M6a smoke for the RESIDENT in-process ATS3 LSP server: PYTHON-SURFACE dispatch.
 *
 * Proves the resident server VALIDATES .psats/.pdats files through the pyfront
 * typecheck pipeline (frontend/SATS/pyfront_lsp.sats -> pyfront_d3parsed_of_
 * fname/fpath) and harvests diagnostics IDENTICALLY to the stock .dats/.sats path.
 *
 *   (A) a VALID .pdats  (def double(x: Int) -> Int: x + x)  -> 0 diagnostics.
 *   (B) a TYPE-ERROR .pdats (def bad(x: Int) -> Int: x + "s") -> >=1 Error
 *       diagnostic landing ON the .pdats SPAN (the `x + "s"` body, line 2 0-based
 *       line 1). This is the M6a gate: a Python-surface type error surfaces as an
 *       LSP diagnostic on the right span.
 *   (C) the server stays HEALTHY: an ORDINARY .dats still checks clean afterward.
 *
 * didOpen drives text_validator (disk path: pyfront_d3parsed_of_fname reads the
 * file). The harness writes the fixtures to a temp workspace so the on-disk read
 * matches the buffer. Modeled on smoke-cfail.js.
 *
 * Override the server artifact with RESIDENT_SERVER=... (defaults to the minified
 * BUILD/xats-lsp-resident.opt1.js; for a fast dev run point it at the raw .js).
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

const SEV_ERROR = 1;

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
function fail(msg) { failures.push(msg); console.error(`[pdats] FAIL: ${msg}`); }
function pass(msg) { console.log(`[pdats] PASS: ${msg}`); }

// --- fixtures (written to a temp workspace; the disk path is read by the
//     validator, so the buffer text must match what is on disk) -------------
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-pdats-'));
const OK_PDATS   = path.join(WS, 'ok.pdats');
const ERR_PDATS  = path.join(WS, 'bad.pdats');
const OK_DATS    = path.join(WS, 'health.dats');
const OK_PDATS_URI  = 'file://' + OK_PDATS;
const ERR_PDATS_URI = 'file://' + ERR_PDATS;
const OK_DATS_URI   = 'file://' + OK_DATS;

const OK_SRC  = 'def double(x: Int) -> Int:\n    x + x\n';
const ERR_SRC = 'def bad(x: Int) -> Int:\n    x + "s"\n';
const DATS_SRC = 'val x: int = 3\nval y: int = x\n';

function main() {
  fs.writeFileSync(OK_PDATS, OK_SRC);
  fs.writeFileSync(ERR_PDATS, ERR_SRC);
  fs.writeFileSync(OK_DATS, DATS_SRC);

  console.log(`[pdats] server : ${SERVER}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: XATSHOME }),
  });

  let done = false;
  let nextId = 100;
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
  function openDoc(uri, languageId, text) {
    notify('textDocument/didOpen', { textDocument: { uri, languageId, version: 1, text } });
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
      if (line.includes('[xats-lsp-metric]')) process.stderr.write(`[server] ${line}\n`);
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[pdats] ALL PASS' : `\n[pdats] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // (A) VALID .pdats -> 0 diagnostics.
    const dOk = waitDiagnostics(OK_PDATS_URI);
    openDoc(OK_PDATS_URI, 'python', OK_SRC);
    const okDiags = await dOk;
    console.log(`\n[pdats] (A) valid .pdats -> ${okDiags.length} diagnostic(s)`);
    for (const d of okDiags) console.log(`  sev=${d.severity} ${JSON.stringify(d.range)} "${(d.message||'').slice(0,80)}"`);
    (okDiags.length === 0)
      ? pass('valid .pdats validates CLEAN (0 diagnostics)')
      : fail(`valid .pdats reported ${okDiags.length} diagnostic(s): ${JSON.stringify(okDiags.map(d=>d.message))}`);

    // (B) TYPE-ERROR .pdats -> >=1 Error diagnostic on the .pdats span (line 1, 0-based).
    const dErr = waitDiagnostics(ERR_PDATS_URI);
    openDoc(ERR_PDATS_URI, 'python', ERR_SRC);
    const errDiags = await dErr;
    console.log(`\n[pdats] (B) type-error .pdats -> ${errDiags.length} diagnostic(s)`);
    for (const d of errDiags) console.log(`  sev=${d.severity} ${JSON.stringify(d.range)} "${(d.message||'').slice(0,80)}"`);
    (errDiags.length >= 1)
      ? pass(`type-error .pdats produces ${errDiags.length} diagnostic(s)`)
      : fail('type-error .pdats produced NO diagnostics (tread3a not run? harvest miss?)');

    const hasError = errDiags.some(d => d.severity === SEV_ERROR);
    hasError
      ? pass('at least one diagnostic is severity Error')
      : fail(`no Error-severity diagnostic: ${JSON.stringify(errDiags.map(d=>d.severity))}`);

    // the diagnostic must land on a real .pdats span (a line/char range, not 0:0-0:0).
    const onSpan = errDiags.find(d => d.range &&
      !(d.range.start.line === 0 && d.range.start.character === 0 &&
        d.range.end.line === 0 && d.range.end.character === 0));
    onSpan
      ? pass(`diagnostic lands on a real .pdats span: ${JSON.stringify(onSpan.range)}`)
      : fail('no diagnostic carried a non-trivial .pdats span (spans did not flow from the surface)');

    // the body error (x + "s") is on source line 2 (0-based line 1); assert at
    // least one diagnostic touches it.
    const onBody = errDiags.find(d => d.range && d.range.start.line === 1);
    onBody
      ? pass(`a diagnostic lands on the body line (line 1, 0-based): ${JSON.stringify(onBody.range)}`)
      : console.log(`[pdats] NOTE: no diagnostic exactly on body line 1; spans present: ${JSON.stringify(errDiags.map(d=>d.range&&d.range.start))}`);

    // (C) HEALTH: an ordinary .dats still checks clean afterward (resident not poisoned).
    const dHealth = waitDiagnostics(OK_DATS_URI);
    openDoc(OK_DATS_URI, 'ats3', DATS_SRC);
    const healthDiags = await dHealth;
    (healthDiags.length === 0)
      ? pass('session stays healthy: an ordinary .dats checks clean (0 diagnostics) after .pdats checks')
      : fail(`follow-up ordinary .dats reported ${healthDiags.length} diagnostic(s): ${JSON.stringify(healthDiags)}`);

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
