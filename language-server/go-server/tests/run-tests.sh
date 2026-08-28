#!/usr/bin/env bash
# run-tests.sh — golden JSON-RPC transcripts, byte-diffed.
#
# Each case is a .jsonl of message bodies; feed.py frames them (UTF-8 byte
# Content-Length) and pipes them to the server; stdout must byte-equal the
# checked-in .golden.  UPDATE=1 rewrites goldens (review the diff!).
set -uo pipefail
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN=${XLSP_BIN:-$T/../BUILD/ats3-lsp-server}
[ -x "$BIN" ] || { echo "!! server not built ($BIN): run tools/build.sh"; exit 1; }
mkdir -p "$T/BUILD"
pass=0; fail=0

run_case() { # run_case <name> <jsonl> [feeder args...]
  local name=$1 jsonl=$2; shift 2
  local golden=$T/cases/$name.golden out=$T/BUILD/$name.out log=$T/BUILD/$name.log
  # the feeder can take SIGPIPE if the server exits first; that is not a
  # failure of the case, so shield it from pipefail.
  ( python3 "$T/feed.py" "$jsonl" "$@" || true ) | "$BIN" > "$out" 2> "$log"
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "!! $name: server exited rc=$rc"; fail=$((fail+1)); return
  fi
  # independent protocol validation (python, not our own framing code)
  if ! python3 "$T/check-stream.py" "$out" > "$T/BUILD/$name.chk" 2>&1; then
    echo "!! $name: INVALID stream"; cat "$T/BUILD/$name.chk"
    fail=$((fail+1)); return
  fi
  if [ "${UPDATE:-0}" = 1 ]; then
    cp "$out" "$golden"; echo ">> $name: golden UPDATED"; pass=$((pass+1)); return
  fi
  if cmp -s "$out" "$golden"; then
    echo ">> $name: PASS"; pass=$((pass+1))
  else
    echo "!! $name: FAIL (stdout differs from golden)"
    cmp "$out" "$golden" 2>&1 | head -3
    fail=$((fail+1))
  fi
}

run_case t01-lifecycle   "$T/cases/t01-lifecycle.jsonl"
run_case t02-unknown     "$T/cases/t02-unknown.jsonl"
run_case t03-multibyte   "$T/cases/t03-multibyte.jsonl"
run_case t04-escapes     "$T/cases/t04-escapes.jsonl"
run_case t05-parse-error "$T/cases/t05-parse-error.jsonl"
# same bytes as t01, dribbled 7 bytes at a time: incremental framing.
run_case t06-chunked     "$T/cases/t01-lifecycle.jsonl" --chunk 7 --delay 2

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
