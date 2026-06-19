#!/usr/bin/env node
/*
 * WS-1b headless smoke test for the ATS3-built LSP server (xats-lsp-server.js).
 *
 * Spawns `node xats-lsp-server.js --stdio` configured (via ATS3_LSP_CHECKER) to
 * use the contract's fake-checker.js, and speaks raw LSP/JSON-RPC over stdio
 * (Content-Length framed), exactly as the VSCode client would. It proves the
 * full round-trip:
 *
 *   client JSON-RPC -> ATS3 server -> debounce -> spawn checker -> read --json-out
 *                   -> cache -> publishDiagnostics -> client
 *
 * Assertions:
 *   A) `initialize` -> result with capabilities (incl. hover/definition provider).
 *   B) didOpen of contract/fixtures/sample-bad.dats -> publishDiagnostics with
 *      BOTH the `type-mismatch` (line 0, char 13-20) AND `unbound-identifier`
 *      (line 1, char 13-28) diagnostics at the contract coordinates.
 *   C) didOpen of a CLEAN doc -> publishDiagnostics with an EMPTY array.
 *
 * Exit code 0 = all pass; non-zero = failure. (No VSCode GUI needed.)
 *
 * Adapted from language-server/scripts/smoke.js (WS-0b).
 */
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const HERE = __dirname;
const SERVER = path.resolve(HERE, '..', 'xats-lsp-server.js');
const CONTRACT = path.resolve(HERE, '..', '..', '..', 'contract');
// Defaults to the fast fake-checker; set ATS3_LSP_CHECKER to the real
// BUILD/xats-lsp-check.js for a true end-to-end run.
const FAKE_CHECKER = process.env.ATS3_LSP_CHECKER || path.join(CONTRACT, 'fake-checker.js');
const SAMPLE_BAD = path.join(CONTRACT, 'fixtures', 'sample-bad.dats');
const SAMPLE_OK = path.join(CONTRACT, 'fixtures', 'sample-ok.dats');

const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '15000', 10);
const BAD_URI = 'file:///tmp/ats3-smoke/sample-bad.dats';
const OK_URI = 'file:///tmp/ats3-smoke/sample-ok.dats';

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
      this.onMessage(JSON.parse(body));
    }
  }
}

// --- expectations ----------------------------------------------------------
// The contract coordinates for sample-bad.dats (README "Coordinates").
const EXPECT_BAD = [
  { code: 'type-mismatch', severity: 1, range: { start: { line: 0, character: 13 }, end: { line: 0, character: 20 } } },
  { code: 'unbound-identifier', severity: 1, range: { start: { line: 1, character: 13 }, end: { line: 1, character: 28 } } },
];
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${d.severity}|${s.line},${s.character}-${e.line},${e.character}`;
}

const failures = [];
function fail(msg) { failures.push(msg); console.error(`[smoke] FAIL: ${msg}`); }
function pass(msg) { console.log(`[smoke] PASS: ${msg}`); }

function main() {
  const badText = fs.readFileSync(SAMPLE_BAD, 'utf8');
  const okText = fs.readFileSync(SAMPLE_OK, 'utf8');

  console.log(`[smoke] server : ${SERVER}`);
  console.log(`[smoke] checker: ${FAKE_CHECKER}`);

  const child = spawn(process.execPath, [SERVER, '--stdio'], {
    cwd: path.resolve(HERE, '..'),
    stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      ATS3_LSP_CHECKER: FAKE_CHECKER,
      // shorten the debounce so the test is snappy (still exercises the timer).
      ATS3_LSP_DEBOUNCE_MS: '120',
    }),
  });

  let initializeReplied = false;
  let gotBad = false;
  let gotOk = false;
  let done = false;
  let stage = 'init';

  const timer = setTimeout(() => {
    if (!done) {
      fail(`timed out after ${TIMEOUT_MS}ms (init=${initializeReplied}, bad=${gotBad}, ok=${gotOk})`);
      finish();
    }
  }, TIMEOUT_MS);

  function send(msg) { child.stdin.write(encode(msg)); }

  function openDoc(uri, text) {
    send({
      jsonrpc: '2.0', method: 'textDocument/didOpen',
      params: { textDocument: { uri, languageId: 'ats3', version: 1, text } },
    });
  }

  function finish() {
    if (done) return;
    done = true;
    clearTimeout(timer);
    try {
      send({ jsonrpc: '2.0', id: 99, method: 'shutdown' });
      send({ jsonrpc: '2.0', method: 'exit' });
    } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} }, 200);

    const ok = initializeReplied && gotBad && gotOk && failures.length === 0;
    if (ok) {
      console.log('\n[smoke] ALL PASS: initialize + bad-doc diagnostics (both codes @contract coords) + clean-doc empty diagnostics.');
      process.exitCode = 0;
    } else {
      fail(`round-trip incomplete (init=${initializeReplied}, bad=${gotBad}, ok=${gotOk}, failures=${failures.length})`);
      process.exitCode = 1;
    }
  }

  const reader = new MessageReader((msg) => {
    const tag = msg.method ? `notif/${msg.method}` : (msg.id !== undefined ? `reply#${msg.id}` : 'msg');
    console.log(`[smoke] <- ${tag}: ${JSON.stringify(msg).slice(0, 300)}`);

    // (A) initialize reply
    if (msg.id === 1 && msg.result && msg.result.capabilities) {
      initializeReplied = true;
      const caps = msg.result.capabilities;
      if (caps.hoverProvider) pass('capabilities advertise hoverProvider');
      else fail('capabilities missing hoverProvider');
      if (caps.definitionProvider) pass('capabilities advertise definitionProvider');
      else fail('capabilities missing definitionProvider');
      send({ jsonrpc: '2.0', method: 'initialized', params: {} });
      // Stage 1: open the BAD doc.
      stage = 'bad';
      openDoc(BAD_URI, badText);
    }

    // (B)/(C) publishDiagnostics
    if (msg.method === 'textDocument/publishDiagnostics') {
      const p = msg.params || {};

      if (p.uri === BAD_URI && !gotBad) {
        const diags = p.diagnostics || [];
        console.log(`[smoke]    publishDiagnostics(bad) ${diags.length} diagnostic(s):`);
        for (const d of diags) {
          console.log(`[smoke]      - [sev=${d.severity}] code=${JSON.stringify(d.code)} @${JSON.stringify(d.range)} :: ${d.message}`);
        }
        const got = new Set(diags.map(diagKey));
        let allPresent = true;
        for (const e of EXPECT_BAD) {
          if (got.has(diagKey(e))) pass(`bad-doc carries ${e.code} @${e.range.start.line}:${e.range.start.character}-${e.range.end.line}:${e.range.end.character}`);
          else { fail(`bad-doc MISSING ${e.code} @contract coords`); allPresent = false; }
        }
        if (diags.length !== EXPECT_BAD.length) fail(`bad-doc expected exactly ${EXPECT_BAD.length} diagnostics, got ${diags.length}`);
        gotBad = allPresent && diags.length === EXPECT_BAD.length;
        // Stage 2: open the CLEAN doc.
        stage = 'ok';
        openDoc(OK_URI, okText);
      } else if (p.uri === OK_URI && !gotOk) {
        const diags = p.diagnostics || [];
        console.log(`[smoke]    publishDiagnostics(ok) ${diags.length} diagnostic(s)`);
        if (diags.length === 0) { pass('clean-doc publishes EMPTY diagnostics'); gotOk = true; }
        else fail(`clean-doc expected 0 diagnostics, got ${diags.length}`);
        finish();
      }
    }
  });

  child.stdout.on('data', (chunk) => reader.push(chunk));
  child.stderr.on('data', (chunk) => process.stderr.write(`[server-stderr] ${chunk.toString()}`));
  child.on('error', (err) => { fail(`failed to spawn server: ${err.message}`); finish(); });
  child.on('exit', (code, signal) => { if (!done) { fail(`server exited early (code=${code}, signal=${signal})`); finish(); } });

  // Kick off the handshake.
  send({
    jsonrpc: '2.0', id: 1, method: 'initialize',
    params: { processId: process.pid, clientInfo: { name: 'ats3-ws1b-smoke', version: '0.1.0' }, rootUri: null, capabilities: {} },
  });
}

main();
