#!/usr/bin/env node
/*
 * INCLUDE / SOURCE-FILTER smoke for the RESIDENT in-process ATS3 LSP server
 * (BUILD/xats-lsp-resident.opt1.js).  Bug 1 regression guard.
 *
 * The harvest walks the WHOLE typed AST of the checked file, which INLINES the
 * nodes of every #include'd / #staload'd source. Those foreign nodes carry the
 * OTHER file's source path + line/col. Before the fix, the harvest emitted
 * hovers / definitions / semantic-tokens for them and attributed them to the
 * CHECKED file's uri using the OTHER file's coords -> phantom rows far past EOF
 * (the real bug: opening xats_lsp_typrint_rt.dats — 350 lines — produced 27,687
 * hovers with max line 3805, 16,815 of them beyond EOF).
 *
 * The fix gates the 4 per-file emit sites (diagnostic / hover / token / def
 * use-site) on "the node's source == the checked file's source". This smoke
 * proves it two ways:
 *
 *   (A) SYNTHETIC: a small top file that #include's a sibling whose body has many
 *       lines of its own. Assert NO emitted hover/def/token lands on a line
 *       beyond the TOP file's own line count, the index counts are SANE (only the
 *       top file's own nodes), and a hover on the top file's own identifier lands
 *       on that identifier.
 *
 *   (B) REAL: run the actual server/DATS/xats_lsp_typrint_rt.dats (which #include's
 *       the compiler headers + dynexp2.sats + the typrint HATS) through the
 *       server. Assert max hover line < its line count (~350) and the hover count
 *       is drastically lower than 27k.
 *
 * Uses a TEST-ONLY custom request `xats/indexStats` (added in the .cats) that
 * reports the per-uri index sizes + the max line any harvested row lands on.
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

// the real compiler-internal file that triggered the bug.
const REAL_FILE = path.join(XATSHOME, 'language-server', 'server', 'DATS', 'xats_lsp_typrint_rt.dats');

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
function fail(msg) { failures.push(msg); console.error(`[includes] FAIL: ${msg}`); }
function pass(msg) { console.log(`[includes] PASS: ${msg}`); }

// --- synthetic workspace ----------------------------------------------------
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-includes-'));

// The INCLUDED sibling: many lines of its OWN content (60 lines of vals). Its
// nodes carry THIS file's source path + these line numbers; if the filter is
// broken they'd leak into the top file's index at lines 0..59.
const INC_NAME = 'inc_body.hats';
const INC_FILE = path.join(WS, INC_NAME);
let incLines = [];
incLines.push('// included body — its own nodes live on lines 0..N of THIS file');
for (let i = 0; i < 60; i++) {
  incLines.push(`val inc_v${i}: int = ${i}`);
}
const INC_SRC = incLines.join('\n') + '\n';

// The TOP file: a handful of its OWN lines, then #include the sibling. Total
// line count is small; NO harvested row for the top file may exceed it.
const TOP_SRC =
  '// top file — only these lines are its own\n' +   // 0
  'val top_a: int = 1\n' +                            // 1
  'val top_b: int = top_a\n' +                        // 2
  '#include "./' + INC_NAME + '"\n' +                 // 3
  'val top_c: int = top_b\n';                         // 4
const TOP_FILE = path.join(WS, 'top.dats');
const TOP_URI = 'file://' + TOP_FILE;
const TOP_LINE_COUNT = TOP_SRC.split('\n').length;    // 6 (trailing newline -> empty last elem)

// --- driver ----------------------------------------------------------------
function main() {
  fs.writeFileSync(INC_FILE, INC_SRC);
  fs.writeFileSync(TOP_FILE, TOP_SRC);

  console.log(`[includes] server : ${SERVER}`);
  console.log(`[includes] ws     : ${WS}`);
  console.log(`[includes] top    : ${TOP_FILE} (${TOP_LINE_COUNT} lines)`);
  console.log(`[includes] incl   : ${INC_FILE} (${INC_SRC.split('\n').length} lines)`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }
  if (!fs.existsSync(REAL_FILE)) { fail(`real file missing: ${REAL_FILE}`); }

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
      if (line.includes('[xats-lsp-metric]')) process.stderr.write(`[server] ${line}\n`);
    }
  });
  child.on('exit', (code, sig) => { if (!done) { fail(`server exited early (code=${code}, sig=${sig})`); finish(); } });

  function finish() {
    if (done) return; done = true; clearTimeout(timer);
    try { notify('exit'); } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 200);
    const ok = failures.length === 0;
    console.log(ok ? '\n[includes] ALL PASS' : `\n[includes] FAILURES: ${failures.length}`);
    process.exitCode = ok ? 0 : 1;
  }

  (async () => {
    await request('initialize', { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} });
    notify('initialized', {});

    // ===================== (A) SYNTHETIC INCLUDE ==========================
    const dWaitTop = waitDiagnostics(TOP_URI);
    openDoc(TOP_URI, TOP_SRC);
    await dWaitTop;   // wait until checked + indexed

    const stats = (await request('xats/indexStats', { uri: TOP_URI })).result;
    console.log('\n[includes] top index stats:', JSON.stringify(stats));
    if (!stats || !stats.found) { fail('xats/indexStats returned nothing for the top file'); finish(); return; }

    // (A1) NO harvested row may land beyond the TOP file's own line range. The
    // included sibling has 60+ lines; a leak would push max line >= ~6 (top) up
    // toward 60. We allow up to (TOP_LINE_COUNT-1) (0-based last line).
    const maxAllowed = TOP_LINE_COUNT - 1;
    const overflows = [];
    if (stats.maxHoverLine > maxAllowed) overflows.push(`hover@${stats.maxHoverLine}`);
    if (stats.maxDefUseLine > maxAllowed) overflows.push(`def@${stats.maxDefUseLine}`);
    if (stats.maxTokenLine > maxAllowed) overflows.push(`token@${stats.maxTokenLine}`);
    overflows.length === 0
      ? pass(`no hover/def/token escapes the top file's line range (maxAllowed=${maxAllowed}; ` +
             `maxHover=${stats.maxHoverLine}, maxDef=${stats.maxDefUseLine}, maxToken=${stats.maxTokenLine})`)
      : fail(`INCLUDED-file nodes leaked past EOF: ${overflows.join(', ')} (top file is only ${TOP_LINE_COUNT} lines)`);

    // (A2) counts are SANE: the top file has ~3 own val bindings; the index must
    // be small (a leak would balloon it by the 60+ included nodes). Assert the
    // hover count is well under the included file's line count.
    const INC_LINES = INC_SRC.split('\n').length;
    (stats.hovers > 0 && stats.hovers < INC_LINES)
      ? pass(`top index count is sane (hovers=${stats.hovers} < includedLines=${INC_LINES}; defs=${stats.defs}, tokens=${stats.tokens})`)
      : fail(`top index count off (hovers=${stats.hovers}, expected >0 and < ${INC_LINES})`);

    // (A3) a hover on the top file's OWN identifier `top_b` (line 2) lands on it.
    // `val top_b: int = top_a` — `top_b` starts at column 4.
    const hov = (await request('textDocument/hover', {
      textDocument: { uri: TOP_URI }, position: { line: 2, character: 5 }
    })).result;
    if (hov && hov.range && hov.range.start && hov.range.start.line === 2) {
      pass(`hover on the top file's own identifier (line 2) resolves on its own line`);
    } else {
      fail(`hover on top file's own identifier did not land on line 2 (got ${JSON.stringify(hov && hov.range)})`);
    }

    // ===================== (B) REAL COMPILER-INTERNAL FILE =================
    if (fs.existsSync(REAL_FILE)) {
      const realUri = 'file://' + REAL_FILE;
      const realSrc = fs.readFileSync(REAL_FILE, 'utf8');
      const realLineCount = realSrc.split('\n').length;
      console.log(`\n[includes] real file: ${REAL_FILE} (${realLineCount} lines)`);
      const dWaitReal = waitDiagnostics(realUri);
      openDoc(realUri, realSrc);
      await dWaitReal;
      const rstats = (await request('xats/indexStats', { uri: realUri })).result;
      console.log('[includes] real index stats:', JSON.stringify(rstats));
      if (!rstats || !rstats.found) { fail('xats/indexStats returned nothing for the real file'); }
      else {
        // (B1) max hover line strictly within the file's own line count.
        (rstats.maxHoverLine < realLineCount)
          ? pass(`real file: max hover line ${rstats.maxHoverLine} < line count ${realLineCount} (no past-EOF hovers)`)
          : fail(`real file: max hover line ${rstats.maxHoverLine} >= line count ${realLineCount} (past-EOF leak)`);
        // also def + token bounded.
        (rstats.maxTokenLine < realLineCount && rstats.maxDefUseLine < realLineCount)
          ? pass(`real file: max def/token lines bounded (def=${rstats.maxDefUseLine}, token=${rstats.maxTokenLine} < ${realLineCount})`)
          : fail(`real file: def/token escapes EOF (def=${rstats.maxDefUseLine}, token=${rstats.maxTokenLine}, lines=${realLineCount})`);
        // (B2) hover count drastically lower than the pre-fix 27,687. Use a
        // generous ceiling (a few thousand) — the point is it's not in the tens
        // of thousands. Empirically ~800 after the fix.
        const CEILING = 5000;
        (rstats.hovers > 0 && rstats.hovers < CEILING)
          ? pass(`real file: hover count ${rstats.hovers} is drastically lower than the pre-fix 27,687 (< ${CEILING})`)
          : fail(`real file: hover count ${rstats.hovers} not in the sane range (expected >0 and < ${CEILING})`);
      }
    }

    finish();
  })().catch((e) => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); finish(); });
}

main();
