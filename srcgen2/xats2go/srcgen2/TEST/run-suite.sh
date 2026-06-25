#!/usr/bin/env bash
########################################################################
# xats2go — CONFORMANCE RUNNER (thin wrapper over the canonical Makefile)
#
#   run-suite.sh                 -> `make -j psuite`  (full suite, parallel, fast)
#   run-suite.sh NAME [NAME...]  -> `make run/NAME`   (one or more tests by name)
#   run-suite.sh path/to/x.dats  -> `make run/x`      (by path; basename is used)
#
# THE MAKEFILE IS THE SINGLE SOURCE OF TRUTH for building and testing.
# - The conformance test list lives ONLY in the Makefile's `SUITE_NAMES`.
#   ADD A NEW TEST THERE (not here). This script no longer keeps its own list,
#   so the two can never drift out of sync (a recurring bug before M2.7).
# - The emitter source list lives ONLY in the Makefile's `GO_DATS`. ADD A NEW
#   go1emit_*.dats THERE.
#
# Use `make run/NAME` (~3s) and `make -j psuite` (~10s) directly for the fast
# dev loop; this wrapper just preserves the old entry point.
########################################################################
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../srcgen2/TEST
XATS2GO="$(cd "$HERE/../.." && pwd)"                   # .../xats2go  (Makefile dir)

if [ "$#" -eq 0 ]; then
  exec make -C "$XATS2GO" -j psuite
fi

rc=0
for t in "$@"; do
  name="$(basename "$t" .dats)"
  make -C "$XATS2GO" "run/$name" || rc=1
done
exit "$rc"
