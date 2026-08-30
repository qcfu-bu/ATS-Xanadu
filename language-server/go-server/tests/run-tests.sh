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
export ATS3_REPO="$(cd "$T/../../.." && pwd)"
mkdir -p "$T/BUILD"
pass=0; fail=0

run_case() { # [EXPECT_RC=n] run_case <name> <jsonl> [feeder args...]
  local name=$1 jsonl=$2; shift 2
  local golden=$T/cases/$name.golden out=$T/BUILD/$name.out log=$T/BUILD/$name.log
  # the feeder can take SIGPIPE if the server exits first; that is not a
  # failure of the case, so shield it from pipefail.
  ( python3 "$T/feed.py" "$jsonl" "$@" || true ) | "$BIN" > "$out" 2> "$log"
  local rc=$?
  if [ $rc -ne "${EXPECT_RC:-0}" ]; then
    echo "!! $name: server exited rc=$rc (want ${EXPECT_RC:-0})"; fail=$((fail+1)); return
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

# like run_case, but compared through normalize-stream.py (canonical JSON
# bodies, repo root -> @X@) — for cases whose output embeds absolute paths.
run_ncase() { # run_ncase <name> <jsonl> [feeder args...]
  local name=$1 jsonl=$2; shift 2
  local golden=$T/cases/$name.ngolden out=$T/BUILD/$name.out log=$T/BUILD/$name.log
  ( python3 "$T/feed.py" "$jsonl" "$@" || true ) | "$BIN" > "$out" 2> "$log"
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "!! $name: server exited rc=$rc"; fail=$((fail+1)); return
  fi
  if ! python3 "$T/check-stream.py" "$out" > "$T/BUILD/$name.chk" 2>&1; then
    echo "!! $name: INVALID stream"; cat "$T/BUILD/$name.chk"
    fail=$((fail+1)); return
  fi
  python3 "$T/normalize-stream.py" "$out" > "$T/BUILD/$name.norm" \
    || { echo "!! $name: normalize failed"; fail=$((fail+1)); return; }
  if [ "${UPDATE:-0}" = 1 ]; then
    cp "$T/BUILD/$name.norm" "$golden"; echo ">> $name: golden UPDATED"; pass=$((pass+1)); return
  fi
  if cmp -s "$T/BUILD/$name.norm" "$golden"; then
    echo ">> $name: PASS"; pass=$((pass+1))
  else
    echo "!! $name: FAIL (normalized stream differs from golden)"
    diff "$golden" "$T/BUILD/$name.norm" | head -6
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
# M2+: real checks (M6: IN-PROCESS — the compiler is linked into the
# server; no separate checker binary is needed).
run_ncase t07-diagnostics "$T/cases/t07-diagnostics.jsonl"
run_ncase t08-save-close  "$T/cases/t08-save-close.jsonl"
run_ncase t10-crossfile   "$T/cases/t10-crossfile.jsonl"
run_ncase t11-hover-def   "$T/cases/t11-hover-def.jsonl"
run_ncase t12-semtok      "$T/cases/t12-semtok.jsonl"
run_ncase t13-completion  "$T/cases/t13-completion.jsonl"
run_ncase t14-dot-member  "$T/cases/t14-dot-member.jsonl"
# M6 state-isolation cases: t15 — a re-check of the same uri must
# re-elaborate its (broken) dep and re-report it (eviction works; a
# stale shr=1 cache would silently drop the dep summary the second
# time); t16 — a name defined by one checked file must NOT resolve in
# a later check of another file (no cross-check pollution).
run_ncase t15-recheck-fresh "$T/cases/t15-recheck-fresh.jsonl"
run_ncase t16-isolation     "$T/cases/t16-isolation.jsonl"
# t17 — a didSave of a $XATSHOME prelude file triggers xglobal_reset +
# prelude reload + revalidation of open docs: the same diagnostics must
# come back after the reload (a broken reload would abort or drift).
run_ncase t17-prelude-reload "$T/cases/t17-prelude-reload.jsonl"
# t18 — M7: references (on-def + on-use, +/- declaration),
# documentHighlight (def + uses light up), documentSymbol (outline).
run_ncase t18-refs-syms "$T/cases/t18-refs-syms.jsonl"
# LSP exit-code contract: 'exit' without a prior 'shutdown' exits 1.
EXPECT_RC=1 run_case t09-exit-code "$T/cases/t09-exit-code.jsonl"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
