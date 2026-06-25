#!/usr/bin/env node
/*
 * WS-6 BACKGROUND PROJECT INDEXER smoke for the RESIDENT ATS3 LSP server.
 *
 *   (A) the server background-indexes workspace files it has NOT opened
 *       (stderr: "bg-index: N file(s) indexed", N>0).
 *   (B) workspace/symbol finds a symbol in an UNOPENED file (from the bg cache).
 *   (C) completion in one file offers a project symbol from another UNOPENED file.
 *
 * AST-accurate, no regex. Exit 0 = all pass.
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

function encode(msg) {
  const p = Buffer.from(JSON.stringify(msg), 'utf8');
  return Buffer.concat([Buffer.from(`Content-Length: ${p.length}\r\n\r\n`, 'ascii'), p]);
}
class MR {
  constructor(on) { this.b = Buffer.alloc(0); this.on = on; }
  push(c) { this.b = Buffer.concat([this.b, c]);
    for (;;) { const he = this.b.indexOf('\r\n\r\n'); if (he < 0) return;
      const m = /Content-Length:\s*(\d+)/i.exec(this.b.slice(0, he)); if (!m) { this.b = this.b.slice(he + 4); continue; }
      const len = +m[1], bs = he + 4; if (this.b.length < bs + len) return;
      const body = this.b.slice(bs, bs + len).toString('utf8'); this.b = this.b.slice(bs + len);
      try { this.on(JSON.parse(body)); } catch (e) {} } }
}
const failures = [];
const fail = m => { failures.push(m); console.error(`[bg] FAIL: ${m}`); };
const pass = m => console.log(`[bg] PASS: ${m}`);

// workspace with TWO files we never open; plus one file we DO open for completion.
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-bg-'));
fs.writeFileSync(path.join(WS, 'helper.dats'), 'fun helperUniqueFn (x: int): int = x\n');
fs.writeFileSync(path.join(WS, 'consts.dats'), 'val theMagicConst = 42\n');
const OPEN_FILE = path.join(WS, 'main.dats'); const OPEN_URI = 'file://' + OPEN_FILE;
const OPEN_SRC = 'val r = theMagic\n';   // references a symbol from consts.dats (unopened)
fs.writeFileSync(OPEN_FILE, OPEN_SRC);

function main() {
  if (!fs.existsSync(SERVER)) { fail(`server missing: ${SERVER}`); process.exit(1); }
  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME }),
  });
  let done = false, id = 100, bgN = -1;
  const pend = new Map(); const diagW = [];
  const timer = setTimeout(() => { if (!done) { fail(`timed out`); finish(); } }, TIMEOUT_MS);
  const send = m => child.stdin.write(encode(m));
  const req = (method, params) => { const i = id++; return new Promise(r => { pend.set(i, r); send({ jsonrpc: '2.0', id: i, method, params }); }); };
  const notify = (method, params) => send({ jsonrpc: '2.0', method, params });
  const waitDiag = uri => new Promise(r => diagW.push({ uri, r }));
  const items = res => { const x = res && res.result; return Array.isArray(x) ? x : (x && x.items) || []; };
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  const reader = new MR(msg => {
    if (msg.id !== undefined && pend.has(msg.id)) { const r = pend.get(msg.id); pend.delete(msg.id); r(msg); return; }
    if (msg.method === 'textDocument/publishDiagnostics') { const p = msg.params || {}; const i = diagW.findIndex(w => w.uri === p.uri); if (i >= 0) diagW.splice(i, 1)[0].r(p.diagnostics || []); }
  });
  child.stdout.on('data', c => reader.push(c));
  child.stderr.on('data', c => { for (const line of c.toString().split('\n')) {
    const m = /bg-index:\s*(\d+)\s*file/.exec(line); if (m) { bgN = +m[1]; process.stderr.write(`[server] ${line}\n`); } } });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[bg] ALL PASS' : `\n[bg] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await req('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // (A) wait for the background indexer to finish (it starts after the scan).
    for (let k = 0; k < 120 && bgN < 0; k++) await sleep(500);
    (bgN > 0) ? pass(`background-indexed ${bgN} file(s)`) : fail(`bg-index did not run (N=${bgN})`);

    // (B) workspace/symbol finds a symbol in an UNOPENED file.
    const wss = (await req('workspace/symbol', { query: 'helperUnique' })).result || [];
    console.log('[bg] workspace/symbol(helperUnique) -> ' + JSON.stringify(wss.map(s => s.name)));
    const helper = wss.find(s => s.name === 'helperUniqueFn');
    (helper) ? pass('workspace/symbol finds `helperUniqueFn` in an UNOPENED file')
             : fail('workspace/symbol did not find the unopened-file symbol');
    (helper && helper.location && /helper\.dats$/.test(helper.location.uri))
      ? pass('…with a location in helper.dats') : fail('…location wrong/missing');

    // (C) completion offers a project symbol from another UNOPENED file.
    const dW = waitDiag(OPEN_URI);
    notify('textDocument/didOpen', { textDocument: { uri: OPEN_URI, languageId: 'ats3', version: 1, text: OPEN_SRC } });
    await dW;
    const line0 = OPEN_SRC.split('\n')[0];
    const cmp = items(await req('textDocument/completion', { textDocument: { uri: OPEN_URI }, position: { line: 0, character: line0.length } }));
    console.log('[bg] complete(theMagic) -> ' + JSON.stringify(cmp.slice(0, 6).map(i => i.label + ':' + i.detail)));
    const magic = cmp.find(i => i.label === 'theMagicConst');
    (magic) ? pass('completion offers `theMagicConst` from an UNOPENED project file')
            : fail('completion did not offer the unopened-file project symbol');

    finish();
  })().catch(e => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}
main();
