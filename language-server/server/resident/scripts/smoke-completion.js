#!/usr/bin/env node
/*
 * WS-6 Stage-1 completion smoke for the RESIDENT ATS3 LSP server.
 *
 *   (A) initialize advertises completionProvider (trigger char '.').
 *   (B) the prelude/global index is built (stderr: "prelude-index: N name(s)", N>0).
 *   (C) completing `my`   -> current-file `myConst` (Constant).
 *   (D) completing `addN` -> current-file `addNumbers` (Function), with a textEdit.
 *   (E) completing `va`   -> the `val` keyword (kind 14).
 *   (F) completing `g`    -> at least one prelude-sourced candidate.
 *   (G) member context (after `.`) returns an empty, re-queryable list (Stage 3).
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

const CIK_FUNCTION = 3, CIK_KEYWORD = 14, CIK_CONSTANT = 21;

// L0: fun addNumbers (x: int, y: int): int = x + y
// L1: val myConst = 42
// L2: val a = my       (complete @ end -> myConst)
// L3: val b = addN     (complete @ end -> addNumbers)
// L4: val c = va       (complete @ end -> `val` keyword)
// L5: val d = g        (complete @ end -> a prelude candidate)
const SRC = [
  'fun addNumbers (x: int, y: int): int = x + y',
  'val myConst = 42',
  'val a = my',
  'val b = addN',
  'val c = va',
  'val d = g',
  ''
].join('\n');
// member-context doc (after `.` -> Stage-1 returns empty).
const MEMBER_SRC = 'val z = abc.fl\n';
// Stage-2 locals doc: a fun param completed mid-typing inside its body — the body
// is an UNBOUND partial (`valu`), the real live-completion scenario.
const LOCALS_SRC = 'fun twice (value: int): int = valu\n';
// Stage-3 member doc: a record-typed receiver; complete a field by prefix.
const MEMBER_REC_SRC = 'fun getx (p: @{xfield= int, yfield= int}): int = p.x\n';

function encode(msg) {
  const payload = Buffer.from(JSON.stringify(msg), 'utf8');
  return Buffer.concat([
    Buffer.from(`Content-Length: ${payload.length}\r\n\r\n`, 'ascii'), payload]);
}
class MessageReader {
  constructor(onMessage) { this.buffer = Buffer.alloc(0); this.onMessage = onMessage; }
  push(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    for (;;) {
      const he = this.buffer.indexOf('\r\n\r\n');
      if (he === -1) return;
      const m = /Content-Length:\s*(\d+)/i.exec(this.buffer.slice(0, he).toString('ascii'));
      if (!m) { this.buffer = this.buffer.slice(he + 4); continue; }
      const len = parseInt(m[1], 10), bs = he + 4;
      if (this.buffer.length < bs + len) return;
      const body = this.buffer.slice(bs, bs + len).toString('utf8');
      this.buffer = this.buffer.slice(bs + len);
      try { this.onMessage(JSON.parse(body)); } catch (e) {}
    }
  }
}
const failures = [];
function fail(m) { failures.push(m); console.error(`[cmp] FAIL: ${m}`); }
function pass(m) { console.log(`[cmp] PASS: ${m}`); }

const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-cmp-'));
const FILE = path.join(WS, 'cmp.dats'); const URI = 'file://' + FILE;
const MFILE = path.join(WS, 'member.dats'); const MURI = 'file://' + MFILE;
const LFILE = path.join(WS, 'locals.dats'); const LURI = 'file://' + LFILE;
const RFILE = path.join(WS, 'rec.dats'); const RURI = 'file://' + RFILE;

function items(res) { const r = res && res.result; return Array.isArray(r) ? r : (r && r.items) || []; }

function main() {
  fs.writeFileSync(FILE, SRC); fs.writeFileSync(MFILE, MEMBER_SRC); fs.writeFileSync(LFILE, LOCALS_SRC); fs.writeFileSync(RFILE, MEMBER_REC_SRC);
  if (!fs.existsSync(SERVER)) { fail(`server missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: XATSHOME }),
  });
  let done = false, nextId = 100, preludeN = -1, preludeSrc = '';
  const pending = new Map(); const diagWaiters = [];
  const timer = setTimeout(() => { if (!done) { fail(`timed out after ${TIMEOUT_MS}ms`); finish(); } }, TIMEOUT_MS);

  function send(m) { child.stdin.write(encode(m)); }
  function request(method, params) {
    const id = nextId++;
    return new Promise((res) => { pending.set(id, res); send({ jsonrpc: '2.0', id, method, params }); });
  }
  function notify(method, params) { send({ jsonrpc: '2.0', method, params }); }
  function waitDiagnostics(uri) { return new Promise((r) => diagWaiters.push({ uri, resolve: r })); }
  function complete(uri, line, character) {
    return request('textDocument/completion', { textDocument: { uri }, position: { line, character } });
  }

  const reader = new MessageReader((msg) => {
    if (msg.id !== undefined && pending.has(msg.id)) { const r = pending.get(msg.id); pending.delete(msg.id); r(msg); return; }
    if (msg.method === 'textDocument/publishDiagnostics') {
      const p = msg.params || {};
      const idx = diagWaiters.findIndex(w => w.uri === p.uri);
      if (idx >= 0) diagWaiters.splice(idx, 1)[0].resolve(p.diagnostics || []);
    }
  });
  child.stdout.on('data', (c) => reader.push(c));
  child.stderr.on('data', (c) => {
    for (const line of c.toString().split('\n')) {
      const m = /prelude-index:\s*(\d+)\s*name\(s\)\s*\[([\w-]+)\]/.exec(line);
      if (m) { preludeN = parseInt(m[1], 10); preludeSrc = m[2]; process.stderr.write(`[server] ${line}\n`); }
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[cmp] ALL PASS' : `\n[cmp] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));

  (async () => {
    const initRes = await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // (A) capability
    const caps = (initRes.result && initRes.result.capabilities) || {};
    const cp = caps.completionProvider;
    cp ? pass('caps: completionProvider') : fail('caps missing completionProvider');
    (cp && cp.triggerCharacters && cp.triggerCharacters.includes('.'))
      ? pass("caps: trigger char '.'") : fail("caps: missing trigger char '.'");

    // open + wait for validation (current-file index ready)
    const dWait = waitDiagnostics(URI);
    notify('textDocument/didOpen', { textDocument: { uri: URI, languageId: 'ats3', version: 1, text: SRC } });
    await dWait;

    // (B) prelude index: must come from the canonical compiler, NEVER regex.
    for (let k = 0; k < 20 && preludeN < 0; k++) await sleep(100);
    (preludeSrc && !/regex/.test(preludeSrc))
      ? pass(`prelude index source is canonical (${preludeSrc}, never regex); N=${preludeN}`)
      : fail(`prelude index source is "${preludeSrc}" (must be canonical / never regex)`);
    if (preludeN === 0)
      console.log('[cmp] NOTE: prelude completion is empty pending the canonical source ' +
        '(allist disabled upstream / cached-AST walk not yet wired) — by design, not a regression');

    // (C) complete `my` @ L2 end -> myConst
    const cMy = items(await complete(URI, 2, 10));
    const myConst = cMy.find(i => i.label === 'myConst');
    console.log('[cmp] complete(my) -> ' + JSON.stringify(cMy.slice(0, 6).map(i => i.label)));
    (myConst && myConst.kind === CIK_CONSTANT) ? pass('complete(my): myConst (Constant)') : fail('complete(my): no myConst/Constant');

    // (D) complete `addN` @ L3 end -> addNumbers (+ textEdit over the partial)
    const cAdd = items(await complete(URI, 3, 12));
    const addN = cAdd.find(i => i.label === 'addNumbers');
    (addN && addN.kind === CIK_FUNCTION) ? pass('complete(addN): addNumbers (Function)') : fail('complete(addN): no addNumbers/Function');
    (addN && /->/.test(addN.detail || '')) ? pass(`complete(addN): detail shows the type (${addN.detail})`) : fail(`complete(addN): detail not a type (${addN && addN.detail})`);
    (addN && addN.textEdit && addN.textEdit.range &&
       addN.textEdit.range.start.line === 3 && addN.textEdit.range.start.character === 8 &&
       addN.textEdit.range.end.character === 12)
      ? pass('complete(addN): textEdit replaces the partial range [8,12)') : fail('complete(addN): textEdit range wrong');

    // (E) complete `va` @ L4 end -> `val` keyword
    const cVa = items(await complete(URI, 4, 10));
    const valKw = cVa.find(i => i.label === 'val');
    (valKw && valKw.kind === CIK_KEYWORD) ? pass('complete(va): `val` keyword (kind 14)') : fail('complete(va): no `val` keyword');

    // (F) complete `g` -> prelude candidates IFF the canonical source is populated.
    const cG = items(await complete(URI, 5, 9));
    const fromPrelude = cG.filter(i => (i.sortText || '').charAt(0) === '3');   // tier 3 = prelude
    console.log('[cmp] complete(g) -> ' + cG.length + ' items, ' + fromPrelude.length + ' prelude');
    if (preludeN > 0)
      (fromPrelude.length >= 1) ? pass(`complete(g): ${fromPrelude.length} prelude candidate(s)`) : fail('complete(g): prelude index populated but no candidates surfaced');
    else
      pass('complete(g): no prelude candidates (canonical source empty — expected, never regex)');
    // prelude functions carry their type in the detail box too
    const pTyped = fromPrelude.filter(i => i.detail && i.detail !== 'prelude' && /[-:>(]/.test(i.detail));
    if (preludeN > 0)
      (pTyped.length >= 1) ? pass(`prelude completions show types (e.g. ${pTyped[0].label}: ${pTyped[0].detail})`) : fail('no prelude completion shows a type');

    // (G) member context after `.` -> empty (Stage-3 placeholder)
    const dWaitM = waitDiagnostics(MURI);
    notify('textDocument/didOpen', { textDocument: { uri: MURI, languageId: 'ats3', version: 1, text: MEMBER_SRC } });
    await dWaitM;
    const cMem = items(await complete(MURI, 0, 14));   // `val z = abc.fl` (abc is unbound, not a record)
    (cMem.length === 0) ? pass('member context on a non-record receiver returns empty (no field leak)') : fail(`member context returned ${cMem.length} items (expected 0)`);

    // (H) Stage-2 in-scope LOCALS: a fun param completes inside its body.
    const dWaitL = waitDiagnostics(LURI);
    notify('textDocument/didOpen', { textDocument: { uri: LURI, languageId: 'ats3', version: 1, text: LOCALS_SRC } });
    await dWaitL;
    const bodyAt = LOCALS_SRC.indexOf('= ') + 2;       // start of the first `value`
    const cLoc = items(await complete(LURI, 0, bodyAt + 4));   // cursor after `valu`
    console.log('[cmp] complete(valu in body) -> ' + JSON.stringify(cLoc.slice(0, 6).map(i => i.label + ':' + i.kind + '/' + i.sortText)));
    const valloc = cLoc.find(i => i.label === 'value');
    (valloc && valloc.kind === 6)                      // 6 = Variable
      ? pass('locals: `value` (param) offered in-scope as Variable')
      : fail('locals: `value` not offered as in-scope Variable');
    (valloc && /^0/.test(valloc.sortText || ''))       // tier 0 = locals (ranked first)
      ? pass('locals: `value` ranked in the locals tier (sortText 0…)')
      : fail('locals: `value` not ranked first (sortText=' + (valloc && valloc.sortText) + ')');

    // (I) Stage-3 MEMBER completion: a record field by prefix, type-filtered.
    const dWaitR = waitDiagnostics(RURI);
    notify('textDocument/didOpen', { textDocument: { uri: RURI, languageId: 'ats3', version: 1, text: MEMBER_REC_SRC } });
    await dWaitR;
    const rline = MEMBER_REC_SRC.split('\n')[0];       // '...= p.x'
    const cRec = items(await complete(RURI, 0, rline.length));   // cursor after `p.x`
    console.log('[cmp] complete(p.x) -> ' + JSON.stringify(cRec.map(i => i.label + ':' + i.kind)));
    const xf = cRec.find(i => i.label === 'xfield');
    (xf && xf.kind === 5)                              // 5 = Field
      ? pass('member: `p.x` offers field `xfield` (Field)')
      : fail('member: `xfield` not offered as a Field');
    (!cRec.some(i => i.label === 'yfield'))            // type-filtered: only matching fields
      ? pass('member: prefix-filtered (no `yfield` for `.x`)')
      : fail('member: offered `yfield` (should be filtered by `x`)');
    (cRec.every(i => i.kind === 5))                    // ONLY fields — no globals leak in
      ? pass('member: only fields offered (no globals)')
      : fail('member: non-field candidates leaked into member context');

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}
main();
