#!/usr/bin/env node
// Dependency-free validator for the ATS3 LSP checker→server JSON bundle (contract v1).
// Usage:
//   node validate-bundle.js <bundle.json> [--expected <expected.json>]
// Validates structure/coordinates against the contract. With --expected, also asserts the
// CANONICAL fields match: per-diagnostic (code, severity, range) as a set, ignoring message
// text and ordering. `message` and `nerror` are advisory and NOT asserted. Exit 0 = OK.
'use strict';
const fs = require('fs');

const SEVERITIES = new Set([1, 2, 3, 4]);
const CODES = new Set(['type-mismatch', 'unbound-identifier', 'unresolved-template', 'pattern-error', 'decl-error', 'unknown']);
const ENTITIES = new Set(['var', 'cst', 'con']);
const KINDS = new Set(['expr', 'pat']);

const errs = [];
const E = (m) => errs.push(m);

function isInt(n) { return Number.isInteger(n); }
function checkPos(p, where) {
  if (typeof p !== 'object' || p === null) return E(`${where}: position not an object`);
  if (!isInt(p.line) || p.line < 0) E(`${where}.line must be int>=0 (got ${JSON.stringify(p.line)})`);
  if (!isInt(p.character) || p.character < 0) E(`${where}.character must be int>=0 (got ${JSON.stringify(p.character)})`);
}
function checkRange(r, where) {
  if (typeof r !== 'object' || r === null) return E(`${where}: range not an object`);
  checkPos(r.start, `${where}.start`);
  checkPos(r.end, `${where}.end`);
  if (r.start && r.end && isInt(r.start.line) && isInt(r.end.line)) {
    const before = r.start.line < r.end.line || (r.start.line === r.end.line && r.start.character <= r.end.character);
    if (!before) E(`${where}: start must be <= end (${JSON.stringify(r.start)} > ${JSON.stringify(r.end)})`);
  }
}
function checkString(v, where) { if (typeof v !== 'string') E(`${where} must be a string`); }

function validate(b) {
  if (typeof b !== 'object' || b === null) { E('bundle is not an object'); return; }
  if (b.schema !== 1) E(`schema must be 1 (got ${JSON.stringify(b.schema)})`);
  if (typeof b.uri !== 'string' || !b.uri.startsWith('file://')) E(`uri must be a file:// string (got ${JSON.stringify(b.uri)})`);
  if (typeof b.ok !== 'boolean') E('ok must be a boolean');
  if (!isInt(b.nerror) || b.nerror < 0) E('nerror must be int>=0');
  for (const k of ['diagnostics', 'hovers', 'definitions']) {
    if (!Array.isArray(b[k])) E(`${k} must be an array`);
  }
  (b.diagnostics || []).forEach((d, i) => {
    const w = `diagnostics[${i}]`;
    checkRange(d.range, `${w}.range`);
    if (!SEVERITIES.has(d.severity)) E(`${w}.severity must be 1..4 (got ${JSON.stringify(d.severity)})`);
    if (!CODES.has(d.code)) E(`${w}.code invalid: ${JSON.stringify(d.code)}`);
    checkString(d.message, `${w}.message`);
    if (d.source !== 'ats3') E(`${w}.source must be "ats3"`);
  });
  (b.hovers || []).forEach((h, i) => {
    const w = `hovers[${i}]`;
    checkRange(h.range, `${w}.range`);
    checkString(h.type, `${w}.type`);
    if (!KINDS.has(h.kind)) E(`${w}.kind must be expr|pat`);
  });
  (b.definitions || []).forEach((d, i) => {
    const w = `definitions[${i}]`;
    checkRange(d.useRange, `${w}.useRange`);
    if (typeof d.defUri !== 'string' || !d.defUri.startsWith('file://')) E(`${w}.defUri must be file://`);
    checkRange(d.defRange, `${w}.defRange`);
    if (!ENTITIES.has(d.entity)) E(`${w}.entity must be var|cst|con`);
  });
}

// Canonical comparison: code + severity + range, as a multiset (ignore message, order).
function diagKey(d) {
  const r = d.range || {}, s = r.start || {}, e = r.end || {};
  return `${d.code}|${d.severity}|${s.line},${s.character}-${e.line},${e.character}`;
}
function compareExpected(actual, expected) {
  const a = (actual.diagnostics || []).map(diagKey).sort();
  const x = (expected.diagnostics || []).map(diagKey).sort();
  if (JSON.stringify(a) === JSON.stringify(x)) return true;
  E(`diagnostics mismatch vs expected (code+severity+range; message ignored):`);
  E(`  expected: ${JSON.stringify(x, null, 0)}`);
  E(`  actual  : ${JSON.stringify(a, null, 0)}`);
  return false;
}

function main() {
  const args = process.argv.slice(2);
  const bundlePath = args[0];
  const ei = args.indexOf('--expected');
  const expectedPath = ei >= 0 ? args[ei + 1] : null;
  if (!bundlePath) { console.error('usage: validate-bundle.js <bundle.json> [--expected <expected.json>]'); process.exit(2); }

  let bundle;
  try { bundle = JSON.parse(fs.readFileSync(bundlePath, 'utf8')); }
  catch (e) { console.error(`FAIL: cannot read/parse ${bundlePath}: ${e.message}`); process.exit(1); }

  validate(bundle);
  if (expectedPath) {
    let expected;
    try { expected = JSON.parse(fs.readFileSync(expectedPath, 'utf8')); }
    catch (e) { console.error(`FAIL: cannot read/parse expected ${expectedPath}: ${e.message}`); process.exit(1); }
    compareExpected(bundle, expected);
  }

  if (errs.length) {
    console.error(`FAIL (${errs.length} problem(s)) for ${bundlePath}:`);
    for (const m of errs) console.error('  - ' + m);
    process.exit(1);
  }
  console.log(`PASS: ${bundlePath}${expectedPath ? ' (canonical match vs ' + expectedPath + ')' : ' (schema-valid)'}`);
}
main();
