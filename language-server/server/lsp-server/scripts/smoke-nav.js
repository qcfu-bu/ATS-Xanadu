#!/usr/bin/env node
/*
 * WS-2 / WS-3 headless smoke test for HOVER + GO-TO-DEFINITION (+ type-def)
 * answered from the ATS3 LSP server's per-(uri,version) cache.
 *
 * Spawns `node xats-lsp-server.js --stdio`, configured (via ATS3_LSP_CHECKER)
 * to use the contract's fake-checker.js (which, for the clean nav fixture
 * contract/fixtures/sample-ok.dats, emits sample `hovers` + `definitions`).
 * It speaks raw LSP/JSON-RPC over stdio exactly as the VSCode client would,
 * and proves hover/def are served PURELY from the cache (no recompile):
 *
 *   initialize -> didOpen(sample-ok) -> wait for publishDiagnostics (bundle
 *   cached) -> textDocument/hover -> textDocument/definition ->
 *   textDocument/typeDefinition -> hover at a blank position.
 *
 * Assertions:
 *   A) initialize result advertises hoverProvider, definitionProvider,
 *      typeDefinitionProvider.
 *   B) hover @{line:1,character:13} -> Hover whose markdown value contains the
 *      type `int`, anchored to a range.
 *   C) definition @{line:1,character:13} -> a Location whose range.start is
 *      {line:0,character:4} (the binding site of `x`).
 *   D) typeDefinition @{line:1,character:13} -> null (fixture has no typeDef
 *      info; the server must gracefully return null, not crash).
 *   E) hover @{line:5,character:0} (a blank position) -> null.
 *
 * Exit code 0 = all pass; non-zero = failure. (No VSCode GUI needed.)
 *
 * Adapted from scripts/smoke.js (WS-1b diagnostics smoke).
 */
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const HERE = __dirname;
const SERVER = path.resolve(HERE, '..', 'xats-lsp-server.js');
const CONTRACT = path.resolve(HERE, '..', '..', '..', 'contract');
// Defaults to the fake-checker (which populates hovers/definitions for the
// clean nav fixture); override via ATS3_LSP_CHECKER for a real end-to-end run.
const FAKE_CHECKER = process.env.ATS3_LSP_CHECKER || path.join(CONTRACT, 'fake-checker.js');
const SAMPLE_OK = path.join(CONTRACT, 'fixtures', 'sample-ok.dats');

const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '15000', 10);
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

const failures = [];
function fail(msg) { failures.push(msg); console.error(`[smoke-nav] FAIL: ${msg}`); }
function pass(msg) { console.log(`[smoke-nav] PASS: ${msg}`); }

// request-id allocation for the typed requests.
const ID = { INIT: 1, HOVER: 10, DEF: 11, TYPEDEF: 12, HOVER_BLANK: 13, SHUTDOWN: 99 };

function main() {
  const okText = fs.readFileSync(SAMPLE_OK, 'utf8');

  console.log(`[smoke-nav] server : ${SERVER}`);
  console.log(`[smoke-nav] checker: ${FAKE_CHECKER}`);

  const child = spawn(process.execPath, [SERVER, '--stdio'], {
    cwd: path.resolve(HERE, '..'),
    stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      ATS3_LSP_CHECKER: FAKE_CHECKER,
      ATS3_LSP_DEBOUNCE_MS: '120',
    }),
  });

  let initializeReplied = false;
  let bundleCached = false;
  let gotHover = false, gotDef = false, gotTypeDef = false, gotHoverBlank = false;
  let done = false;

  const timer = setTimeout(() => {
    if (!done) {
      fail(`timed out after ${TIMEOUT_MS}ms (init=${initializeReplied}, cached=${bundleCached}, ` +
           `hover=${gotHover}, def=${gotDef}, typedef=${gotTypeDef}, hoverBlank=${gotHoverBlank})`);
      finish();
    }
  }, TIMEOUT_MS);

  function send(msg) { child.stdin.write(encode(msg)); }

  function finish() {
    if (done) return;
    done = true;
    clearTimeout(timer);
    try {
      send({ jsonrpc: '2.0', id: ID.SHUTDOWN, method: 'shutdown' });
      send({ jsonrpc: '2.0', method: 'exit' });
    } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} }, 200);

    const ok = initializeReplied && bundleCached &&
               gotHover && gotDef && gotTypeDef && gotHoverBlank &&
               failures.length === 0;
    if (ok) {
      console.log('\n[smoke-nav] ALL PASS: hover -> `int`, definition -> binding @0:4, ' +
                  'type-definition -> null (no info), blank hover -> null.');
      process.exitCode = 0;
    } else {
      fail(`nav round-trip incomplete (init=${initializeReplied}, cached=${bundleCached}, ` +
           `hover=${gotHover}, def=${gotDef}, typedef=${gotTypeDef}, hoverBlank=${gotHoverBlank}, ` +
           `failures=${failures.length})`);
      process.exitCode = 1;
    }
  }

  // Once the bundle is cached, fire the typed nav requests.
  function sendNavRequests() {
    // B) hover at the use-site of `x` on line 1 (char 13).
    send({
      jsonrpc: '2.0', id: ID.HOVER, method: 'textDocument/hover',
      params: { textDocument: { uri: OK_URI }, position: { line: 1, character: 13 } },
    });
    // C) definition at the same position.
    send({
      jsonrpc: '2.0', id: ID.DEF, method: 'textDocument/definition',
      params: { textDocument: { uri: OK_URI }, position: { line: 1, character: 13 } },
    });
    // D) type-definition at the same position (fixture has no typeDef -> null).
    send({
      jsonrpc: '2.0', id: ID.TYPEDEF, method: 'textDocument/typeDefinition',
      params: { textDocument: { uri: OK_URI }, position: { line: 1, character: 13 } },
    });
    // E) hover at a blank position (beyond any hover range) -> null.
    send({
      jsonrpc: '2.0', id: ID.HOVER_BLANK, method: 'textDocument/hover',
      params: { textDocument: { uri: OK_URI }, position: { line: 5, character: 0 } },
    });
  }

  function maybeDone() {
    if (gotHover && gotDef && gotTypeDef && gotHoverBlank) finish();
  }

  const reader = new MessageReader((msg) => {
    const tag = msg.method ? `notif/${msg.method}` : (msg.id !== undefined ? `reply#${msg.id}` : 'msg');
    console.log(`[smoke-nav] <- ${tag}: ${JSON.stringify(msg).slice(0, 320)}`);

    // (A) initialize reply -> capabilities.
    if (msg.id === ID.INIT && msg.result && msg.result.capabilities) {
      initializeReplied = true;
      const caps = msg.result.capabilities;
      if (caps.hoverProvider) pass('capabilities advertise hoverProvider');
      else fail('capabilities missing hoverProvider');
      if (caps.definitionProvider) pass('capabilities advertise definitionProvider');
      else fail('capabilities missing definitionProvider');
      if (caps.typeDefinitionProvider) pass('capabilities advertise typeDefinitionProvider');
      else fail('capabilities missing typeDefinitionProvider');
      send({ jsonrpc: '2.0', method: 'initialized', params: {} });
      // open the clean nav fixture; wait for its publishDiagnostics (= bundle cached).
      send({
        jsonrpc: '2.0', method: 'textDocument/didOpen',
        params: { textDocument: { uri: OK_URI, languageId: 'ats3', version: 1, text: okText } },
      });
      return;
    }

    // bundle-cached signal: the publishDiagnostics for the opened doc.
    if (msg.method === 'textDocument/publishDiagnostics' && !bundleCached) {
      const p = msg.params || {};
      if (p.uri === OK_URI) {
        bundleCached = true;
        pass('bundle cached (publishDiagnostics received for opened doc)');
        sendNavRequests();
      }
      return;
    }

    // (B) hover reply.
    if (msg.id === ID.HOVER) {
      const r = msg.result;
      const value = r && r.contents && r.contents.value;
      if (r && typeof value === 'string' && value.includes('int')) {
        pass(`hover @1:13 returns type containing \`int\` (value=${JSON.stringify(value)})`);
        if (r.range && r.range.start) {
          pass(`hover carries an anchor range (start=${JSON.stringify(r.range.start)})`);
        } else {
          fail('hover result missing range');
        }
        gotHover = true;
      } else {
        fail(`hover @1:13 did not return \`int\` (got ${JSON.stringify(r)})`);
        gotHover = true; // record we saw the reply (so we can finish/report)
      }
      maybeDone();
      return;
    }

    // (C) definition reply (a single Location or an array of them).
    if (msg.id === ID.DEF) {
      const r = msg.result;
      const loc = Array.isArray(r) ? r[0] : r;
      const start = loc && loc.range && loc.range.start;
      if (loc && loc.uri && start && start.line === 0 && start.character === 4) {
        pass(`definition @1:13 returns Location at binding ${JSON.stringify(loc.range.start)} ` +
             `(uri=${loc.uri})`);
        gotDef = true;
      } else {
        fail(`definition @1:13 did not return a Location @0:4 (got ${JSON.stringify(r)})`);
        gotDef = true;
      }
      maybeDone();
      return;
    }

    // (D) type-definition reply -> null (fixture has no typeDef info).
    if (msg.id === ID.TYPEDEF) {
      const r = msg.result;
      if (r === null) {
        pass('typeDefinition @1:13 returns null (no typeDef info in fixture)');
        gotTypeDef = true;
      } else {
        // not a hard failure if a real checker DID supply typeDef info, but the
        // fake-checker does not, so for this smoke we expect null.
        fail(`typeDefinition @1:13 expected null, got ${JSON.stringify(r)}`);
        gotTypeDef = true;
      }
      maybeDone();
      return;
    }

    // (E) blank hover reply -> null.
    if (msg.id === ID.HOVER_BLANK) {
      const r = msg.result;
      if (r === null) {
        pass('hover @5:0 (blank) returns null');
        gotHoverBlank = true;
      } else {
        fail(`hover @5:0 (blank) expected null, got ${JSON.stringify(r)}`);
        gotHoverBlank = true;
      }
      maybeDone();
      return;
    }
  });

  child.stdout.on('data', (chunk) => reader.push(chunk));
  child.stderr.on('data', (chunk) => process.stderr.write(`[server-stderr] ${chunk.toString()}`));
  child.on('error', (err) => { fail(`failed to spawn server: ${err.message}`); finish(); });
  child.on('exit', (code, signal) => { if (!done) { fail(`server exited early (code=${code}, signal=${signal})`); finish(); } });

  // Kick off the handshake.
  send({
    jsonrpc: '2.0', id: ID.INIT, method: 'initialize',
    params: { processId: process.pid, clientInfo: { name: 'ats3-nav-smoke', version: '0.1.0' }, rootUri: null, capabilities: {} },
  });
}

main();
