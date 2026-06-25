#!/usr/bin/env bash
########################################################################
# ats-check.sh -- type-check an ATS3 file directly (no VSCode), printing
# compiler-style diagnostics to stderr. Exit 0 = clean, 1 = errors found.
#
#   ./ats-check.sh path/to/file.dats
#
# Uses the same checker the LSP server runs (prefers the minified
# BUILD/xats-lsp-check.opt1.js; override with ATS3_LSP_CHECKER).
########################################################################
set -uo pipefail
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECKER="${ATS3_LSP_CHECKER:-}"
if [ -z "$CHECKER" ]; then
  if   [ -f "$HERE/BUILD/xats-lsp-check.opt1.js" ]; then CHECKER="$HERE/BUILD/xats-lsp-check.opt1.js"
  elif [ -f "$HERE/BUILD/xats-lsp-check.js"      ]; then CHECKER="$HERE/BUILD/xats-lsp-check.js"
  else echo "ats-check: no checker built (run build.sh)"; exit 2; fi
fi

F="${1:?usage: ats-check.sh <file.dats|sats>}"
[ -f "$F" ] || { echo "ats-check: no such file: $F"; exit 2; }
ABS="$(cd "$(dirname "$F")" && pwd)/$(basename "$F")"
OUT="$(mktemp -t ats-check)"

node --stack-size=8801 "$CHECKER" "$ABS" --uri "file://$ABS" --json-out "$OUT" 2>/dev/null
node -e '
const fs = require("fs");
const b = JSON.parse(fs.readFileSync(process.argv[1], "utf8")), f = process.argv[2];
const ds = b.diagnostics || [];
if (!ds.length) { console.log(f + ": ok"); process.exit(0); }
for (const d of ds) { const s = d.range.start;
  console.error(`${f}:${s.line+1}:${s.character+1}: ${d.code}: ${d.message}`); }
console.error(`${ds.length} error(s)`);
process.exit(1);
' "$OUT" "$ABS"
RC=$?
rm -f "$OUT"
exit $RC
