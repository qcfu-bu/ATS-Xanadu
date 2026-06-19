#!/usr/bin/env node
/*
 * UTF-16 COLUMN smoke for the RESIDENT in-process ATS3 LSP server
 * (BUILD/xats-lsp-resident.opt1.js).  Workstream R1 / P4 polish.
 *
 * The harvest emits `character` = the BYTE column (ncol; primer §5). LSP wants
 * the UTF-16 code-unit column for the line. They differ on lines with multi-byte
 * UTF-8 glyphs. This smoke proves the server converts byte -> UTF-16 columns:
 *
 *   source line 0 (ASCII control): `val a: int = undef_ascii`
 *       -> undef_ascii at column 13 == byte 13 (no change; pure ASCII).
 *   source line 1 (NON-ASCII): a string literal with an emoji (😀 = 4 bytes /
 *       2 UTF-16 units), then an undefined name:
 *       `val s: int = "😀 hi" ++ undef_emoji`
 *       -> the undefined names AFTER the emoji must report UTF-16 columns that
 *          are STRICTLY LESS than their raw byte columns (by the emoji's 2-unit
 *          deficit).
 *
 * The test runs the server TWICE — once with conversion DISABLED
 * (ATS3_LSP_UTF16=0, the ground-truth byte columns) and once with conversion ON
 * (the default) — and asserts:
 *   (a) ASCII control line: converted column == byte column (unchanged);
 *   (b) non-ASCII line: converted column < byte column;
 *   (c) converted column == the UTF-16 column independently computed from the
 *       byte column via TextDecoder over the source bytes (exact correctness).
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
const TIMEOUT_MS = parseInt(process.env.SMOKE_TIMEOUT_MS || '120000', 10);

// line 0 = ASCII control; line 1 = emoji string then undefined names.
const LINE0 = 'val a: int = undef_ascii';
const LINE1 = 'val s: int = "\u{1F600} hi" ++ undef_emoji';
const SRC = LINE0 + '\n' + LINE1 + '\n';

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
function fail(msg) { failures.push(msg); console.error(`[utf16] FAIL: ${msg}`); }
function pass(msg) { console.log(`[utf16] PASS: ${msg}`); }

// independent ground truth: byte column -> UTF-16 column on a given line of SRC.
const SRC_BYTES_BY_LINE = SRC.split('\n').map(l => Buffer.from(l, 'utf8'));
function byteColToUtf16(line, byteCol) {
  const bytes = SRC_BYTES_BY_LINE[line];
  if (!bytes) return byteCol;
  const sub = bytes.slice(0, byteCol);
  return new TextDecoder('utf-8').decode(sub).length;  // .length = utf16 units
}

// run ONE server instance with the given env; resolve with the diagnostics for
// the opened doc (a Map keyed by `${code}@${line}` -> {sl,sc,el,ec,message}).
function runServer(utf16Enabled) {
  return new Promise((resolve, reject) => {
    const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-utf16-'));
    const FILE = path.join(WS, 'u.dats');
    const URI = 'file://' + FILE;
    fs.writeFileSync(FILE, SRC);
    const env = Object.assign({}, process.env, {
      XATSHOME: process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu',
    });
    if (!utf16Enabled) env.ATS3_LSP_UTF16 = '0';

    const child = spawn(process.execPath, [...NODE_ARGS, SERVER, '--stdio'], {
      cwd: WS, stdio: ['pipe', 'pipe', 'pipe'], env,
    });
    let settled = false;
    const to = setTimeout(() => {
      if (!settled) { settled = true; try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} reject(new Error('server timed out')); }
    }, TIMEOUT_MS);

    function send(m) { child.stdin.write(encode(m)); }
    const reader = new MessageReader((msg) => {
      if (msg.method === 'textDocument/publishDiagnostics' && msg.params && msg.params.uri === URI) {
        if (settled) return; settled = true; clearTimeout(to);
        const out = new Map();
        for (const d of (msg.params.diagnostics || [])) {
          const r = d.range || {}, s = r.start || {}, e = r.end || {};
          out.set(`${d.code}@${s.line}`, { sl: s.line, sc: s.character, el: e.line, ec: e.character, message: d.message });
        }
        setTimeout(() => { try { child.kill(); } catch (_) {} try { fs.rmSync(WS, { recursive: true, force: true }); } catch (_) {} }, 100);
        resolve(out);
      }
    });
    child.stdout.on('data', c => reader.push(c));
    child.stderr.on('data', c => {});
    child.on('exit', () => { if (!settled) { settled = true; clearTimeout(to); reject(new Error('server exited early')); } });

    send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { processId: process.pid, rootUri: 'file://' + WS, capabilities: {} } });
    setTimeout(() => {
      send({ jsonrpc: '2.0', method: 'initialized', params: {} });
      send({ jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: { uri: URI, languageId: 'ats3', version: 1, text: SRC } } });
    }, 300);
  });
}

async function main() {
  console.log(`[utf16] server : ${SERVER}`);
  console.log(`[utf16] line 0 : ${JSON.stringify(LINE0)}`);
  console.log(`[utf16] line 1 : ${JSON.stringify(LINE1)}`);
  if (!fs.existsSync(SERVER)) { fail(`server artifact missing: ${SERVER}`); process.exit(1); }

  // (1) ground-truth byte columns (conversion disabled).
  const raw = await runServer(false);
  // (2) converted UTF-16 columns (default).
  const conv = await runServer(true);

  console.log('[utf16] raw (byte) columns :');
  for (const [k, v] of raw) console.log(`         ${k} -> ${v.sc}-${v.ec}  ${JSON.stringify(v.message)}`);
  console.log('[utf16] converted (utf16)  :');
  for (const [k, v] of conv) console.log(`         ${k} -> ${v.sc}-${v.ec}  ${JSON.stringify(v.message)}`);

  // helper: the diagnostic for `code` on `line`.
  function get(map, code, line) { return map.get(`${code}@${line}`); }

  // (A) ASCII CONTROL line 0: undef_ascii — converted == byte (unchanged).
  const rawA = get(raw, 'unbound-identifier', 0);
  const convA = get(conv, 'unbound-identifier', 0);
  if (!rawA || !convA) {
    fail('missing the line-0 ASCII control diagnostic (undef_ascii)');
  } else {
    (rawA.sc === convA.sc && rawA.ec === convA.ec)
      ? pass(`ASCII control line 0: column UNCHANGED (byte ${rawA.sc}-${rawA.ec} == utf16 ${convA.sc}-${convA.ec})`)
      : fail(`ASCII control line 0: column CHANGED (byte ${rawA.sc}-${rawA.ec} != utf16 ${convA.sc}-${convA.ec}) — ASCII must be identity`);
    // and the converted column equals the independent ground truth.
    const exp = byteColToUtf16(0, rawA.sc);
    convA.sc === exp ? pass(`ASCII control line 0: utf16 start ${convA.sc} == independent ground truth ${exp}`)
                     : fail(`ASCII control line 0: utf16 start ${convA.sc} != ground truth ${exp}`);
  }

  // (B) NON-ASCII line 1: undef_emoji — converted < byte, and == ground truth.
  const rawB = get(raw, 'unbound-identifier', 1);
  const convB = get(conv, 'unbound-identifier', 1);
  if (!rawB || !convB) {
    fail('missing the line-1 non-ASCII diagnostic (undef_emoji / ++ on line 1)');
  } else {
    // strict inequality: the emoji (4 bytes / 2 units) makes byte col > utf16 col.
    convB.sc < rawB.sc
      ? pass(`non-ASCII line 1: utf16 start ${convB.sc} < byte start ${rawB.sc} (emoji deficit applied)`)
      : fail(`non-ASCII line 1: utf16 start ${convB.sc} NOT < byte start ${rawB.sc} — conversion did not fire`);
    convB.ec < rawB.ec
      ? pass(`non-ASCII line 1: utf16 end ${convB.ec} < byte end ${rawB.ec}`)
      : fail(`non-ASCII line 1: utf16 end ${convB.ec} NOT < byte end ${rawB.ec}`);
    // exact correctness: converted == independent TextDecoder ground truth.
    const expS = byteColToUtf16(1, rawB.sc);
    const expE = byteColToUtf16(1, rawB.ec);
    (convB.sc === expS && convB.ec === expE)
      ? pass(`non-ASCII line 1: utf16 ${convB.sc}-${convB.ec} == independent ground truth ${expS}-${expE} (EXACT)`)
      : fail(`non-ASCII line 1: utf16 ${convB.sc}-${convB.ec} != ground truth ${expS}-${expE}`);
    // and the deficit equals the emoji's (4 bytes - 2 units) = 2 byte/unit gap.
    (rawB.sc - convB.sc === 2)
      ? pass(`non-ASCII line 1: byte->utf16 deficit is exactly 2 (one astral emoji = 4 bytes / 2 units)`)
      : fail(`non-ASCII line 1: expected a deficit of 2, got ${rawB.sc - convB.sc}`);
  }

  const ok = failures.length === 0;
  console.log(ok ? '[utf16] ALL PASS' : `[utf16] FAILURES: ${failures.length}`);
  process.exit(ok ? 0 : 1);
}

main().catch(e => { fail('harness threw: ' + (e && e.stack ? e.stack : e)); process.exit(1); });
