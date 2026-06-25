#!/usr/bin/env node
/*
 * SEMANTIC TOKENS smoke for the RESIDENT in-process ATS3 LSP server
 * (BUILD/xats-lsp-resident.opt1.js).  Workstream R1 / LSP semantic tokens.
 *
 * AST-based token classification the regex TextMate grammar cannot do: a name
 * is resolved (by the typed AST) to a variable / function / data-constructor /
 * type. This smoke proves that end-to-end:
 *
 *   (A) initialize -> the server advertises `semanticTokensProvider` WITH a
 *       legend (tokenTypes incl. variable/function/enumMember/type, and
 *       tokenModifiers incl. declaration/definition/defaultLibrary).
 *   (B) didOpen a sample .dats with: a datatype + constructor, a function def,
 *       a val-bound variable, and a type usage; request
 *       textDocument/semanticTokens/full; DECODE the returned `data` array back
 *       to absolute (line,char,len,type,mods) tuples.
 *   (C) assert the four headline classifications:
 *         - the function name (def + use)   -> `function`
 *         - a val-bound name (use)          -> `variable`
 *         - a data constructor (use)        -> `enumMember`
 *         - a type name (decl)              -> `type`
 *
 * Print the decoded tokens for the report.  Exit 0 = all pass.
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

// --- a real on-disk workspace (the server reads the saved file) ----------
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-semantic-'));
const FILE = path.join(WS, 'sem.dats');
const URI = 'file://' + FILE;

// A self-contained sample exercising every category.  Line numbers (0-based):
//   0: blank
//   1: datatype color = Red of () | Green of () | Blue of ()    -- `color` TYPE @col 9
//   2: blank
//   3: fun pick(): color = Red()         -- `pick` FUNCTION; `color` TYPE use*; `Red` enumMember
//   4: blank
//   5: val chosen: color = pick()        -- `chosen` decl; `pick` FUNCTION use; `color` type
//   6: val again: color = chosen         -- `chosen` VARIABLE use @col 22
//   7: blank
// (*) a type NAME in an annotation is not separately located in the typed AST;
//     the authoritative `type` token is the datatype DECLARATION name on line 1.
const SRC =
  '\n' +
  'datatype color = Red of () | Green of () | Blue of ()\n' +
  '\n' +
  'fun pick(): color = Red()\n' +
  '\n' +
  'val chosen: color = pick()\n' +
  'val again: color = chosen\n';

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
function fail(msg) { failures.push(msg); console.error(`[semantic] FAIL: ${msg}`); }
function pass(msg) { console.log(`[semantic] PASS: ${msg}`); }

// the legend we expect the server to advertise (and decode against).
const EXPECT_TYPES = [
  'namespace', 'type', 'typeParameter', 'parameter', 'variable', 'property',
  'function', 'enumMember', 'keyword', 'string', 'number', 'operator', 'comment'
];
const EXPECT_MODS = [
  'declaration', 'definition', 'readonly', 'static', 'defaultLibrary'
];

// decode the LSP flat int array (5-tuples, relative) back to absolute tokens
// using the server's advertised legend.
function decodeTokens(data, legend) {
  const out = [];
  let line = 0, char = 0;
  for (let i = 0; i + 4 < data.length; i += 5) {
    const dLine = data[i], dChar = data[i + 1], len = data[i + 2];
    const tIdx = data[i + 3], mBits = data[i + 4];
    if (dLine === 0) char += dChar; else { line += dLine; char = dChar; }
    const type = legend.tokenTypes[tIdx] || ('#' + tIdx);
    const mods = [];
    for (let b = 0; b < legend.tokenModifiers.length; b++) {
      if (mBits & (1 << b)) mods.push(legend.tokenModifiers[b]);
    }
    out.push({ line, char, len, type, mods });
  }
  return out;
}
// the source text of a token (for human-readable printing + assertions).
const SRC_LINES = SRC.split('\n');
function tokText(t) {
  const l = SRC_LINES[t.line] || '';
  return l.slice(t.char, t.char + t.len);
}

// --- driver ----------------------------------------------------------------
function main() {
  fs.writeFileSync(FILE, SRC);

  console.log(`[semantic] server : ${SERVER}`);
  console.log(`[semantic] ws     : ${WS}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
    cwd: WS, stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { XATSHOME: process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu' }),
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
      if (line.includes('[xats-lsp-metric]') || line.includes('listening') ||
          line.includes('threw') || line.includes('ERROR')) {
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
    console.log(ok ? '\n[semantic] ALL PASS' : `\n[semantic] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    // (A) initialize -> capabilities + legend.
    const initRes = await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    const caps = (initRes.result && initRes.result.capabilities) || {};
    const stp = caps.semanticTokensProvider;
    if (stp) pass('capabilities advertise semanticTokensProvider');
    else fail('missing semanticTokensProvider');
    const legend = (stp && stp.legend) || null;
    if (legend && Array.isArray(legend.tokenTypes) && Array.isArray(legend.tokenModifiers)) {
      pass('semanticTokensProvider carries a legend');
    } else { fail('semanticTokensProvider missing legend'); finish(); return; }
    // assert the legend matches the standard subset we expect to decode against.
    const typesOk = EXPECT_TYPES.every(t => legend.tokenTypes.includes(t));
    const modsOk = EXPECT_MODS.every(m => legend.tokenModifiers.includes(m));
    typesOk ? pass('legend.tokenTypes includes the standard subset')
            : fail(`legend.tokenTypes missing some of ${JSON.stringify(EXPECT_TYPES)} (got ${JSON.stringify(legend.tokenTypes)})`);
    modsOk ? pass('legend.tokenModifiers includes the standard subset')
           : fail(`legend.tokenModifiers missing some of ${JSON.stringify(EXPECT_MODS)} (got ${JSON.stringify(legend.tokenModifiers)})`);
    // the `full` capability must be on (object or boolean true).
    (stp.full === true || (stp.full && typeof stp.full === 'object'))
      ? pass('semanticTokensProvider.full is enabled')
      : fail(`semanticTokensProvider.full not enabled (got ${JSON.stringify(stp.full)})`);
    notify('initialized', {});

    // (B) open + check the sample, then request full semantic tokens.
    const dWait = waitDiagnostics(URI);
    openDoc(URI, SRC);
    await dWait;   // wait until the doc has been checked + indexed
    const res = await request('textDocument/semanticTokens/full', { textDocument: { uri: URI } });
    const data = (res.result && res.result.data) || null;
    if (!Array.isArray(data)) { fail(`semanticTokens/full returned no data array (got ${JSON.stringify(res.result)})`); finish(); return; }
    (data.length % 5 === 0)
      ? pass(`semanticTokens/full returned a flat 5-tuple array (${data.length / 5} token(s))`)
      : fail(`data length ${data.length} is not a multiple of 5`);

    const toks = decodeTokens(data, legend);
    console.log('\n===================== DECODED TOKENS =====================');
    for (const t of toks) {
      console.log(`  L${t.line}:${t.char}+${t.len}  ${t.type}` +
        (t.mods.length ? ` [${t.mods.join(',')}]` : '') +
        `   "${tokText(t)}"`);
    }
    console.log('==========================================================\n');

    // (C) the four headline classifications.  We assert by TOKEN TEXT (robust to
    //     exact columns) AND that at least one such token has the right type.
    function tokensFor(name) { return toks.filter(t => tokText(t) === name); }
    function anyType(name, type) { return tokensFor(name).some(t => t.type === type); }

    // `pick` -> function (a fun-bound name; its resolved type is a function type)
    anyType('pick', 'function')
      ? pass('function name `pick` classified as `function`')
      : fail(`\`pick\` not classified function (got ${JSON.stringify(tokensFor('pick').map(t => t.type))})`);

    // `chosen` -> variable (a val-bound name, used on line 6)
    anyType('chosen', 'variable')
      ? pass('val-bound name `chosen` classified as `variable`')
      : fail(`\`chosen\` not classified variable (got ${JSON.stringify(tokensFor('chosen').map(t => t.type))})`);

    // `Red` -> enumMember (the data constructor)
    anyType('Red', 'enumMember')
      ? pass('data constructor `Red` classified as `enumMember`')
      : fail(`\`Red\` not classified enumMember (got ${JSON.stringify(tokensFor('Red').map(t => t.type))})`);

    // `color` -> type (the datatype declaration name)
    anyType('color', 'type')
      ? pass('type name `color` classified as `type`')
      : fail(`\`color\` not classified type (got ${JSON.stringify(tokensFor('color').map(t => t.type))})`);

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
