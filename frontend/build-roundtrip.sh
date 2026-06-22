#!/usr/bin/env bash
########################################################################
# ROUND-TRIP GAP-ANALYSIS REPORTER (bootstrap recon) — runs the FAITHFUL pythonic
# translation of a real ATS3 compiler interface file (srcgen2/SATS/xstamp0.sats,
# 133 lines) through the M3 driver and classifies the outcome PER FILE. This is a
# GAP-ANALYSIS instrument (NOT a green regression gate): non-passing fixtures are
# the current implementation signals to investigate. The script always exits 0
# once the reporter itself runs successfully.
#
# Files under frontend/TEST/roundtrip/:
#   xstamp0.psats        — the FAITHFUL translation; still reports frontend errors.
#   xstamp0_probe.psats  — import + @overload-alias removed; isolates the lowercase-type-name
#                          rejection, currently surfaced as parse diagnostics.
#   xstamp0_ucase.psats  — same but type names UPPERCASED (NOT faithful — a diagnostic) to
#                          confirm everything ELSE typechecks; currently PASS.
#   probe_overload.psats — current supported #symload-alias smoke test; currently PASS.
#   probe_overload2.psats — unsupported @overload-alias spelling; still parse-errors.
#   probe_import.psats   — dotted import of a missing .sats; now a recoverable TYPE-ERROR.
#   probe_qual.psats     — a $SYM.foo qualified-name in a type; still reports errors.
#
# Reuses the existing BUILD/pyfront-m3.js (run `bash frontend/build-m3.sh` first if absent).
# PURELY ADDITIVE: reads only; writes outcome logs into BUILD/.
#
# Usage:
#   bash frontend/build-roundtrip.sh
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/roundtrip"
NODE="node --stack-size=8801"

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run 'bash frontend/build-m3.sh' first to build the M3 driver." >&2
  exit 1
fi
echo ">> reusing M3 driver bundle $BUNDLE ($(wc -l < "$BUNDLE") lines)"

# classify_one <file> — run the driver, print outcome class + the salient evidence.
classify_one() {
  local f="$1"; local base; base="$(basename "$f")"
  local out="$BUILD/rt_$(basename "$f" .psats).log"
  echo "----------------------------------------------------------------------"
  echo ">> $base"
  $NODE "$BUNDLE" "$f" > "$out" 2>&1
  local rc=$?
  if grep -qE "ENOENT|is not defined|RangeError|TypeError:" "$out" \
     && ! grep -q "RESULT:" "$out"; then
    echo "   OUTCOME: CRASH (uncaught — driver aborted before a verdict)"
    grep -E "Error:|ENOENT|is not defined" "$out" | head -2 | sed 's/^/     /'
    return 0
  fi
  local nerr; nerr="$(grep -oE "nerror \(after tread3a\) = [0-9]+" "$out" | grep -oE "[0-9]+$" | tail -1)"
  local nparse; nparse="$(grep -cE "parse: " "$out")"
  if grep -q "RESULT: PASS" "$out"; then
    echo "   OUTCOME: PASS (nerror=0 — typechecks clean)"
  elif [ "$nparse" -gt 0 ]; then
    echo "   OUTCOME: PARSE-ERROR ($nparse parse diagnostics; nerror=${nerr:-?})"
    grep -E "parse: " "$out" | sed 's/^.*parse:/     parse:/' | sort -u | head -8
  else
    echo "   OUTCOME: TYPE-ERROR (nerror=${nerr:-?})"
    grep -E "^RESULT:|elab-diag" "$out" | head -6 | sed 's/^/     /'
  fi
  return 0
}

echo ">> classifying round-trip fixtures (gap-analysis snapshot; reporter exits 0)"
for f in \
  "$TESTDIR/xstamp0.psats" \
  "$TESTDIR/xstamp0_probe.psats" \
  "$TESTDIR/xstamp0_ucase.psats" \
  "$TESTDIR/probe_overload.psats" \
  "$TESTDIR/probe_overload2.psats" \
  "$TESTDIR/probe_import.psats" \
  "$TESTDIR/probe_qual.psats" ; do
  [ -f "$f" ] && classify_one "$f"
done
echo "----------------------------------------------------------------------"
echo ">> ROUND-TRIP: done (report-only; see frontend/docs for the gap analysis)."
exit 0
