#!/usr/bin/env node
/*
 * WS-5 smoke for the RESIDENT ATS3 LSP server: documentSymbol, references,
 * documentHighlight, inlayHint.
 *
 *   (A) initialize advertises documentSymbolProvider / referencesProvider /
 *       documentHighlightProvider / inlayHintProvider.
 *   (B) documentSymbol on a small file lists `add` (Function) + the vals.
 *   (C) references on a USE of `a` (includeDeclaration) returns every use + decl.
 *   (D) documentHighlight on a USE of `add` returns all occurrences (+ the decl).
 *   (E) inlayHint over the file returns inferred ": int" hints on the vals.
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

// SymbolKind / DocumentHighlightKind / InlayHintKind constants used below.
const SK_FUNCTION = 12, SK_CONSTANT = 14;

// L0: fun add (x: int, y: int): int = x + y
// L1: val a = add(1, 2)
// L2: val b = add(a, 3)
// L3: val c = add(a, b)
const SRC = [
  'fun add (x: int, y: int): int = x + y',
  'val a = add(1, 2)',
  'val b = add(a, 3)',
  'val c = add(a, b)',
  ''
].join('\n');

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
function fail(msg) { failures.push(msg); console.error(`[ws5] FAIL: ${msg}`); }
function pass(msg) { console.log(`[ws5] PASS: ${msg}`); }

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-ws5-'));
const FILE = path.join(WS, 'ws5.dats');
const URI = 'file://' + FILE;

function main() {
  fs.writeFileSync(FILE, SRC);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: XATSHOME }),
  });

  let done = false, nextId = 100;
  const pending = new Map();
  const diagWaiters = [];
  const timer = setTimeout(() => { if (!done) { fail(`timed out after ${TIMEOUT_MS}ms`); finish(); } }, TIMEOUT_MS);

  function send(msg) { child.stdin.write(encode(msg)); }
  function request(method, params) {
    const id = nextId++;
    return new Promise((resolve) => { pending.set(id, resolve); send({ jsonrpc: '2.0', id, method, params }); });
  }
  function notify(method, params) { send({ jsonrpc: '2.0', method, params }); }
  function waitDiagnostics(uri) { return new Promise((r) => diagWaiters.push({ uri, resolve: r })); }

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
    for (const line of c.toString().split('\n'))
      if (line.includes('[xats-lsp-metric]')) process.stderr.write(`[server] ${line}\n`);
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[ws5] ALL PASS' : `\n[ws5] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    const initRes = await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // (A) capabilities
    const caps = (initRes.result && initRes.result.capabilities) || {};
    caps.documentSymbolProvider ? pass('caps: documentSymbolProvider') : fail('caps missing documentSymbolProvider');
    caps.referencesProvider ? pass('caps: referencesProvider') : fail('caps missing referencesProvider');
    caps.documentHighlightProvider ? pass('caps: documentHighlightProvider') : fail('caps missing documentHighlightProvider');
    caps.inlayHintProvider ? pass('caps: inlayHintProvider') : fail('caps missing inlayHintProvider');
    caps.workspaceSymbolProvider ? pass('caps: workspaceSymbolProvider') : fail('caps missing workspaceSymbolProvider');

    // open + wait for the first diagnostics (validation done -> index ready)
    const dWait = waitDiagnostics(URI);
    notify('textDocument/didOpen', { textDocument: { uri: URI, languageId: 'ats3', version: 1, text: SRC } });
    await dWait;

    // (B) documentSymbol
    const ds = (await request('textDocument/documentSymbol', { textDocument: { uri: URI } })).result || [];
    const names = ds.map(s => s.name);
    console.log('[ws5] documentSymbol -> ' + JSON.stringify(ds.map(s => s.name + ':' + s.kind)));
    (ds.length >= 4) ? pass(`documentSymbol returned ${ds.length} symbols`) : fail(`documentSymbol returned ${ds.length} (<4)`);
    const addSym = ds.find(s => s.name === 'add');
    (addSym && addSym.kind === SK_FUNCTION) ? pass('documentSymbol: `add` is Function') : fail('documentSymbol: `add` missing/!Function');
    (['a','b','c'].every(n => names.includes(n))) ? pass('documentSymbol: vals a,b,c present') : fail('documentSymbol: missing some of a,b,c');

    // (C) references on a USE of `a` (L2 col 12), includeDeclaration
    const refs = (await request('textDocument/references', {
      textDocument: { uri: URI }, position: { line: 2, character: 12 },
      context: { includeDeclaration: true }
    })).result || [];
    console.log('[ws5] references(a) -> ' + JSON.stringify(refs.map(r => r.range.start.line + ':' + r.range.start.character)));
    // uses at L2:12 and L3:12, plus declaration at L1:4 -> 3
    (refs.length >= 3) ? pass(`references(a) returned ${refs.length} (uses + decl)`) : fail(`references(a) returned ${refs.length} (<3)`);
    (refs.some(r => r.range.start.line === 1 && r.range.start.character === 4))
      ? pass('references(a): includes the declaration (L1:4)') : fail('references(a): missing the declaration');

    // (D) documentHighlight on a USE of `add` (L1 col 8)
    const hls = (await request('textDocument/documentHighlight', {
      textDocument: { uri: URI }, position: { line: 1, character: 8 }
    })).result || [];
    console.log('[ws5] highlight(add) -> ' + JSON.stringify(hls.map(h => h.range.start.line + ':' + h.range.start.character + '/' + h.kind)));
    // 3 call-site uses (L1,L2,L3 col 8) + the decl (L0:4) -> >=4
    (hls.length >= 4) ? pass(`documentHighlight(add) returned ${hls.length} occurrences`) : fail(`documentHighlight(add) returned ${hls.length} (<4)`);
    (hls.some(h => h.range.start.line === 0 && h.kind === 3))
      ? pass('documentHighlight(add): the decl is kind=Write(3)') : fail('documentHighlight(add): no Write-kind decl');

    // (E) inlayHint over the whole file
    const inl = (await request('textDocument/inlayHint', {
      textDocument: { uri: URI }, range: { start: { line: 0, character: 0 }, end: { line: 4, character: 0 } }
    })).result || [];
    console.log('[ws5] inlayHint -> ' + JSON.stringify(inl.map(h => h.position.line + ':' + h.position.character + h.label)));
    (inl.length >= 3) ? pass(`inlayHint returned ${inl.length} hints`) : fail(`inlayHint returned ${inl.length} (<3 for a,b,c)`);
    (inl.every(h => /:\s*int/.test(h.label))) ? pass('inlayHint: all labels are `: int`') : fail('inlayHint: some label is not `: int`');

    // (F) workspace/symbol — the startup project scan textually indexed ws5.dats.
    const wss = (await request('workspace/symbol', { query: 'add' })).result || [];
    console.log('[ws5] workspace/symbol("add") -> ' + JSON.stringify(wss.map(s => s.name + ':' + s.kind)));
    const addWs = wss.find(s => s.name === 'add');
    (addWs && addWs.kind === SK_FUNCTION)
      ? pass('workspace/symbol: finds `add` (Function) project-wide')
      : fail('workspace/symbol: did not find `add` as Function');
    // the project index stores symlink-canonical paths (realpath), so on macOS a
    // /tmp uri may be /private/var/... vs the editor's /var/... — same file. Compare
    // by realpath of the decoded path, not raw string equality.
    function uriRealpath(u) {
      try { return fs.realpathSync(decodeURIComponent(String(u).replace(/^file:\/\//, ''))); }
      catch (e) { return String(u); }
    }
    (addWs && addWs.location && uriRealpath(addWs.location.uri) === uriRealpath(URI))
      ? pass('workspace/symbol: `add` location points at the file')
      : fail('workspace/symbol: `add` location wrong/missing (' + (addWs && addWs.location && addWs.location.uri) + ')');

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
