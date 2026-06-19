// Headless tokenization smoke test for the ATS3 TextMate grammar.
//
//   node fixtures/tokenize-test.js [file.dats]
//
// Loads ./syntaxes/ats3.tmLanguage.json with vscode-textmate +
// vscode-oniguruma, tokenizes a sample, prints the scope assigned to a set of
// key tokens, and asserts they get the expected scope families. Exits non-zero
// on any failed assertion.

const fs = require("fs");
const path = require("path");
const vsctm = require("vscode-textmate");
const oniguruma = require("vscode-oniguruma");

const CLIENT_DIR = path.resolve(__dirname, "..");
const GRAMMAR_PATH = path.join(CLIENT_DIR, "syntaxes", "ats3.tmLanguage.json");
const SAMPLE_PATH = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(__dirname, "sample.dats");

async function makeRegistry() {
  const wasmBin = fs.readFileSync(
    path.join(CLIENT_DIR, "node_modules", "vscode-oniguruma", "release", "onig.wasm")
  ).buffer;
  await oniguruma.loadWASM(wasmBin);
  const onigLib = Promise.resolve({
    createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
    createOnigString: (s) => new oniguruma.OnigString(s),
  });
  return new vsctm.Registry({
    onigLib,
    loadGrammar: async (scopeName) => {
      if (scopeName === "source.ats") {
        const raw = fs.readFileSync(GRAMMAR_PATH, "utf8");
        return vsctm.parseRawGrammar(raw, GRAMMAR_PATH);
      }
      return null;
    },
  });
}

// Returns the deepest (most specific) scope on a token, i.e. the last scope
// other than the base "source.ats".
function leafScope(scopes) {
  for (let i = scopes.length - 1; i >= 0; i--) {
    if (scopes[i] !== "source.ats") return scopes[i];
  }
  return scopes[scopes.length - 1];
}

async function main() {
  const registry = await makeRegistry();
  const grammar = await registry.loadGrammar("source.ats");
  if (!grammar) throw new Error("failed to load grammar source.ats");

  const text = fs.readFileSync(SAMPLE_PATH, "utf8");
  const lines = text.split(/\r?\n/);

  // Collect, for the first occurrence of each interesting literal token, the
  // scope stack assigned to it. Skip tokens that live inside a string or a
  // comment, so e.g. the word `true` inside "true" is not mistaken for the
  // boolean literal.
  const seen = new Map(); // token text -> array of scopes
  let ruleStack = vsctm.INITIAL;
  for (const line of lines) {
    const r = grammar.tokenizeLine(line, ruleStack);
    for (const tok of r.tokens) {
      const piece = line.substring(tok.startIndex, tok.endIndex);
      const trimmed = piece.trim();
      if (trimmed.length === 0) continue;
      const insideStringOrComment = tok.scopes.some(
        (s) => s.startsWith("string.") || s.startsWith("comment.")
      );
      if (insideStringOrComment) continue;
      if (!seen.has(trimmed)) seen.set(trimmed, tok.scopes);
    }
    ruleStack = r.ruleStack;
  }

  function scopeOf(token) {
    const scopes = seen.get(token);
    return scopes ? leafScope(scopes) : "(token not found)";
  }

  // The full scope stack of the first occurrence of `token`, for checks that
  // need to look at an ancestor scope (e.g. a string body whose token is the
  // escape, but whose stack contains string.quoted.double).
  function stackOf(token) {
    return seen.get(token) || [];
  }

  // (token, substring-the-leaf-scope-must-contain) — checked against the leaf
  // scope of the first standalone (non-string, non-comment) occurrence.
  const checks = [
    ["fun", "keyword"],
    ["fn", "keyword"],
    ["val", "keyword"],
    ["if", "keyword.control"],
    ["then", "keyword.control"],
    ["else", "keyword.control"],
    ["case+", "keyword.control"],
    ["datatype", "storage.type"],
    ["prfun", "keyword"],
    ["#staload", "keyword.control.import"],
    ["#include", "keyword.control.import"],
    ["#define", "keyword.other.directive"],
    ["#typedef", "keyword.other.directive"],
    ["#impltmp", "keyword.other.directive"],
    ["$tup", "support.function.builtin"],
    ["$showtype", "support.function.builtin"],
    ["true", "constant.language.boolean"],
    ["false", "constant.language.boolean"],
    ["0", "constant.numeric"],
    ["0xDEADBEEF", "constant.numeric"],
    ["3.14159", "constant.numeric.float"],
    ["6.022e23", "constant.numeric.float"],
    ["=>", "keyword.operator"],
    ["->", "keyword.operator"],
  ];

  let failures = 0;
  console.log("token".padEnd(16) + "leaf scope");
  console.log("-".repeat(64));
  for (const [token, mustContain] of checks) {
    const leaf = scopeOf(token);
    const ok = leaf.includes(mustContain);
    if (!ok) failures++;
    console.log(
      (ok ? "PASS " : "FAIL ") +
        JSON.stringify(token).padEnd(16) +
        leaf +
        (ok ? "" : `   (expected to contain "${mustContain}")`)
    );
  }

  // Comment checks: find a token that is inside a (* *) block, a // line, and
  // the //// rest-of-file region, by scanning the whole stack.
  function findTokenWithScopeContaining(substr) {
    let rs = vsctm.INITIAL;
    for (const line of lines) {
      const r = grammar.tokenizeLine(line, rs);
      for (const tok of r.tokens) {
        if (tok.scopes.some((s) => s.includes(substr))) {
          const piece = line.substring(tok.startIndex, tok.endIndex).trim();
          if (piece.length) return { piece, scopes: tok.scopes };
        }
      }
      rs = r.ruleStack;
    }
    return null;
  }

  console.log("-".repeat(64));

  // String / char / comment checks: locate any token whose scope STACK
  // contains the target scope family.
  function checkStackScope(substr, mustStartWith, label) {
    const hit = findTokenWithScopeContaining(substr);
    const ok = hit && hit.scopes.some((s) => s.startsWith(mustStartWith));
    if (!ok) failures++;
    console.log(
      (ok ? "PASS " : "FAIL ") +
        label +
        " -> " +
        (hit ? leafScope(hit.scopes) : "(none found)")
    );
  }

  checkStackScope("string.quoted.double", "string.quoted.double", '"..." string');
  checkStackScope("string.quoted.single", "string.quoted.single", "'c' char");
  checkStackScope("constant.character.escape", "string.quoted.double", "\\t / \\n escape inside string");
  checkStackScope("comment.block", "comment.block", "(* block comment *)");
  checkStackScope("comment.line", "comment.line", "// line comment");
  checkStackScope("comment.block.documentation", "comment.block.documentation", "//// rest-of-file comment");

  console.log("-".repeat(64));
  console.log(
    failures === 0
      ? "ALL CHECKS PASSED"
      : `${failures} CHECK(S) FAILED`
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
