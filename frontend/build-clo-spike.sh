#!/usr/bin/env bash
########################################################################
# clo-spike — GATING SPIKE for the "uniform cloref" closure model.
#
# Read-only feasibility probe: reuses the M3 driver bundle (BUILD/pyfront-m3.js) to run four
# .pdats probes through the pyfront pipeline (lex -> parse -> elab -> lower -> trans23 -> tread3a)
# and report `nerror (after tread3a)` per probe. NO new DATS compiled; NO srcgen2 change.
#
#   T  probeT_funtype     : cloref-shaped function TYPE `(Int) -> Int` as a HOF param + applied.
#   C  probeC_make_adder  : a CAPTURING lambda `(x) => x + n` RETURNED at type `(Int) -> Int`.
#   X  probeX_use_closure : CALL the returned closure (`make_adder(5)` then `add5(3)`).
#   N  probeN_named_coerce: pass a flat-`fun` named `def` where a `(Int)->Int` is expected.
#
# Each probe runs in its OWN node process (a crashing probe cannot poison the others). The
# authoritative count is the `nerror (after tread3a) = N` line the driver prints; the codegen
# ReferenceError that follows a nerror=0 typecheck is the PARKED #13b backend, NOT a typecheck error.
#
# Usage:  bash frontend/build-clo-spike.sh
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/clo-spike"
NODE="node --stack-size=8801"

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — build it first (bash frontend/build-m3.sh)" >&2; exit 1
fi

PROBES=(
  "T:probeT_funtype"
  "C:probeC_make_adder"
  "X:probeX_use_closure"
  "N:probeN_named_coerce"
)

echo "======================================================================"
echo ">> clo-spike: 4 probes (each own-process), authoritative = nerror (after tread3a)"
echo "======================================================================"
for entry in "${PROBES[@]}"; do
  tag="${entry%%:*}"; base="${entry#*:}"
  f="$TESTDIR/${base}.pdats"
  echo "----------------------------------------------------------------------"
  echo ">> Probe $tag  ($base)"
  echo "-- source --"; cat "$f"
  echo "-- run --"
  out="$($NODE "$BUNDLE" "$f" 2>&1)"
  n="$(printf '%s' "$out" | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1)"
  echo ">> Probe $tag nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" != "0" ]; then
    echo "-- diagnostics / FPERR0 (probe $tag did NOT reach nerror=0) --"
    printf '%s\n' "$out" | grep -iE "FPERR0-ERROR|F.PERR0|errck|unify|t2pck|cfail|Exception|Error:" | head -20
  fi
done
echo "======================================================================"
echo ">> clo-spike done (interpret nerror per probe above; codegen ReferenceError after nerror=0 = parked #13b)"
