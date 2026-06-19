#!/usr/bin/env node
// Stand-in for the real ATS3 checker (xats-lsp-check.js), implementing the SAME CLI contract:
//   node fake-checker.js <source.dats|sats> --uri <uri> --json-out <path.json>
// It writes a contract-v1 JSON bundle to --json-out. Used by WS-1b to develop/test the
// server's spawn→read→cache→publish loop WITHOUT the real checker. Diagnostics are produced
// by trivial content sniffing (hard-coded coordinates matching contract/fixtures), NOT by
// real type-checking. Replace with the real checker once WS-1a lands.
'use strict';
const fs = require('fs');

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : dflt;
}

const src = process.argv[2];
const uri = arg('--uri', 'file:///UNKNOWN');
const out = arg('--json-out', null);
if (!out) { console.error('fake-checker: --json-out required'); process.exit(2); }

let text = '';
try { text = fs.readFileSync(src, 'utf8'); } catch (_) { /* missing file → empty */ }

const diagnostics = [];
// Mirror contract/fixtures/sample-bad.dats coordinates when those snippets are present.
if (text.includes('"hello"')) {
  diagnostics.push({
    range: { start: { line: 0, character: 13 }, end: { line: 0, character: 20 } },
    severity: 1, code: 'type-mismatch', message: 'expected `int`, got `string`', source: 'ats3'
  });
}
if (text.includes('nonexistent_var')) {
  diagnostics.push({
    range: { start: { line: 1, character: 13 }, end: { line: 1, character: 28 } },
    severity: 1, code: 'unbound-identifier', message: 'unbound identifier `nonexistent_var`', source: 'ats3'
  });
}

// Sample hover/definition data for the clean nav fixture
// (contract/fixtures/sample-ok.dats: `val x: int = 3` / `val y: int = x`), so the
// server's onHover/onDefinition handlers can be developed/tested before the real
// checker populates these arrays. Coordinates are illustrative, not type-checked.
const hovers = [];
const definitions = [];
if (diagnostics.length === 0 && text.includes('val y: int = x')) {
  hovers.push(
    { range: { start: { line: 0, character: 13 }, end: { line: 0, character: 14 } }, type: 'int', kind: 'expr' },
    { range: { start: { line: 1, character: 13 }, end: { line: 1, character: 14 } }, type: 'int', kind: 'expr' }
  );
  definitions.push(
    { useRange: { start: { line: 1, character: 13 }, end: { line: 1, character: 14 } },
      defUri: uri,
      defRange: { start: { line: 0, character: 4 }, end: { line: 0, character: 5 } },
      entity: 'var' }
  );
}

const bundle = {
  schema: 1, uri, ok: true, nerror: diagnostics.length,
  diagnostics, hovers, definitions
};
fs.writeFileSync(out, JSON.stringify(bundle, null, 2));
// Emit some noise on stdout to mimic the real checker's debug tracing (server must ignore stdout).
console.log('fake-checker: wrote bundle to', out);
