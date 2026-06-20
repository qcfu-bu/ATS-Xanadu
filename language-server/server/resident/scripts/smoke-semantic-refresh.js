#!/usr/bin/env node
/*
 * Semantic-tokens REFRESH-ON-EDIT smoke for the RESIDENT ATS3 LSP server.
 *
 * Bug: semantic tokens are served from a per-uri cache updated only when a
 * (debounced) check completes. A token request made during the debounce window
 * gets STALE tokens and the client is never told to re-fetch -> highlighting
 * doesn't update on edits. Fix: the server sends workspace/semanticTokens/refresh
 * after each check updates the cache.
 *
 *   (A) initialize (advertising refreshSupport) -> server uses it.
 *   (B) after an EDIT (didChange) the server SENDS workspace/semanticTokens/refresh.
 *   (C) re-pulling tokens after the edit reflects the NEW content (cache updated).
 *
 * Exit 0 = all pass.
 */
'use strict';
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const RESIDENT = path.resolve(__dirname, '..');
const SERVER = process.env.RESIDENT_SERVER || path.join(RESIDENT, 'BUILD', 'xats-lsp-resident.opt1.js');
const XATSHOME = process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu';
const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '120000', 10);

function encode(m) { const p = Buffer.from(JSON.stringify(m), 'utf8'); return Buffer.concat([Buffer.from(`Content-Length: ${p.length}\r\n\r\n`, 'ascii'), p]); }
class MR { constructor(on){this.b=Buffer.alloc(0);this.on=on;} push(c){this.b=Buffer.concat([this.b,c]);for(;;){const he=this.b.indexOf('\r\n\r\n');if(he<0)return;const m=/Content-Length:\s*(\d+)/i.exec(this.b.slice(0,he));if(!m){this.b=this.b.slice(he+4);continue;}const len=+m[1],bs=he+4;if(this.b.length<bs+len)return;const body=this.b.slice(bs,bs+len).toString('utf8');this.b=this.b.slice(bs+len);try{this.on(JSON.parse(body));}catch(e){}}}}

const failures = [];
const fail = m => { failures.push(m); console.error(`[sem] FAIL: ${m}`); };
const pass = m => console.log(`[sem] PASS: ${m}`);

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-sem-'));
const FILE = path.join(WS, 'sem.dats'); const URI = 'file://' + FILE;
const SRC1 = 'val aaa = 1\n';
const SRC2 = 'val aaa = 1\nval bbbbb = 2\nval ccccc = aaa\n';   // edit: more bound names -> more tokens

function main() {
  if (!fs.existsSync(SERVER)) { fail(`server missing: ${SERVER}`); process.exit(1); }
  fs.writeFileSync(FILE, SRC1);
  const child = spawn(process.execPath, ['--stack-size=8801', SERVER, '--stdio'],
    { cwd: WS, stdio: ['pipe','pipe','pipe'], env: Object.assign({}, process.env, { XATSHOME }) });
  let done = false, id = 100, refreshCount = 0;
  const pend = new Map(); const diagW = [];
  const timer = setTimeout(() => { if (!done) { fail('timed out'); finish(); } }, TIMEOUT_MS);
  const send = m => child.stdin.write(encode(m));
  const req = (method, params) => { const i = id++; return new Promise(r => { pend.set(i, r); send({ jsonrpc:'2.0', id:i, method, params }); }); };
  const notify = (method, params) => send({ jsonrpc:'2.0', method, params });
  const waitDiag = uri => new Promise(r => diagW.push({ uri, r }));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const waitRefresh = () => new Promise(r => { const t0 = refreshCount; const iv = setInterval(() => { if (refreshCount > t0) { clearInterval(iv); r(true); } }, 50); setTimeout(() => { clearInterval(iv); r(false); }, 8000); });

  const reader = new MR(msg => {
    if (msg.id !== undefined && msg.method === undefined && pend.has(msg.id)) { const r = pend.get(msg.id); pend.delete(msg.id); r(msg); return; }
    // server -> client REQUESTS (have both id and method): respond so the server isn't blocked.
    if (msg.id !== undefined && msg.method) {
      if (msg.method === 'workspace/semanticTokens/refresh') refreshCount++;
      send({ jsonrpc:'2.0', id: msg.id, result: null });
      return;
    }
    if (msg.method === 'textDocument/publishDiagnostics') { const p = msg.params||{}; const i = diagW.findIndex(w=>w.uri===p.uri); if (i>=0) diagW.splice(i,1)[0].r(p.diagnostics||[]); }
  });
  child.stdout.on('data', c => reader.push(c));
  child.stderr.on('data', () => {});
  child.on('exit', (code,sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch(_){}
    setTimeout(() => { try { child.kill(); } catch(_){} try { fs.rmSync(WS, {recursive:true, force:true}); } catch(_){} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[sem] ALL PASS' : `\n[sem] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }
  const ntok = res => { const d = res && res.result && res.result.data; return Array.isArray(d) ? d.length/5 : -1; };

  (async () => {
    // (A) initialize advertising semantic-tokens refresh support.
    await req('initialize', { processId: process.pid, rootUri: 'file://'+WS,
      capabilities: { workspace: { semanticTokens: { refreshSupport: true } } } });
    notify('initialized', {});
    const dWait = waitDiag(URI);
    notify('textDocument/didOpen', { textDocument: { uri: URI, languageId: 'ats3', version: 1, text: SRC1 } });
    await dWait;
    const n1 = ntok(await req('textDocument/semanticTokens/full', { textDocument: { uri: URI } }));
    console.log('[sem] tokens before edit: ' + n1);
    (n1 >= 1) ? pass(`initial tokens present (${n1})`) : fail('no initial tokens');

    // (B) EDIT the document; expect a refresh request after the debounced check.
    const refreshes0 = refreshCount;
    notify('textDocument/didChange', { textDocument: { uri: URI, version: 2 },
      contentChanges: [{ text: SRC2 }] });
    const got = await waitRefresh();
    (got && refreshCount > refreshes0)
      ? pass('server sent workspace/semanticTokens/refresh after the edit')
      : fail('NO semanticTokens/refresh sent after edit (stale-highlight bug)');

    // (C) re-pull tokens -> reflect the NEW content (cache updated by the check).
    await sleep(200);
    const n2 = ntok(await req('textDocument/semanticTokens/full', { textDocument: { uri: URI } }));
    console.log('[sem] tokens after edit: ' + n2);
    (n2 > n1)
      ? pass(`re-pulled tokens reflect the edit (${n1} -> ${n2})`)
      : fail(`tokens did not grow after adding symbols (${n1} -> ${n2})`);

    finish();
  })().catch(e => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}
main();
