#!/usr/bin/env bash
########################################################################
# assemble-py.sh — Phase D: assemble the pythonic-built Chez compiler.
#
# Concatenate the Chez runtime + all PY/ .scm fragments (in component order) into
# PY/chez_py_selfhost.scm, then precompile to a native .so. Optionally smoke-test it
# by compiling a sample .dats and diffing against the seed xats2cz output.
#
# Prereq: bash frontend/compile-py.sh has produced BUILD/py-scm/*.scm (all 171).
#
# Usage:
#   bash frontend/assemble-py.sh            # assemble .scm + build .so
#   bash frontend/assemble-py.sh --check    # also smoke-test vs seed on m0_hello
########################################################################
set -uo pipefail
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
PY="$HERE/PY"
SCMDIR="$BUILD/py-scm"
CZRT="$XATSHOME/srcgen2/xats2cz/runtime/xats2cz_runtime.scm"
OUT_SCM="$PY/chez_py_selfhost.scm"
OUT_SO="$PY/chez_py_selfhost.so"

CHECK=0; for a in "$@"; do [ "$a" = "--check" ] && CHECK=1; done

nfrag=$(ls "$SCMDIR"/*.scm 2>/dev/null | wc -l | tr -d ' ')
[ "$nfrag" -gt 0 ] || { echo "!! no fragments in $SCMDIR — run compile-py.sh" >&2; exit 1; }
echo ">> assembling $nfrag fragments + runtime -> $OUT_SCM"
cat "$CZRT" $(ls "$SCMDIR"/*.scm | sort) > "$OUT_SCM"
echo "   $(wc -l < "$OUT_SCM") lines"

echo ">> precompiling -> $OUT_SO (optimize-level 3)"
echo "(optimize-level 3)(generate-inspector-information #f)(compile-file \"$OUT_SCM\" \"$OUT_SO\")" \
  | chez -q 2>"$BUILD/assemble-py.cerr"
if [ -s "$OUT_SO" ]; then echo "   built $OUT_SO ($(du -h "$OUT_SO"|cut -f1))"; else
  echo "!! .so build failed (see $BUILD/assemble-py.cerr)"; tail -20 "$BUILD/assemble-py.cerr"; exit 1; fi

if [ "$CHECK" -eq 1 ]; then
  echo ">> smoke test: run the PY-built compiler on m0_hello.dats, diff vs seed"
  T="$XATSHOME/srcgen2/xats2cz/TEST/m0_hello.dats"
  chez --script "$OUT_SO" "$T" 2>/dev/null | awk '/BEGIN==/{f=1;next}/END==/{f=0}f' > "$BUILD/py_m0.scm"
  $XATSHOME/srcgen2/xats2cz/BUILD/xats2cz-bundle.js >/dev/null 2>&1 # noop guard
  node --stack-size=8801 "$XATSHOME/srcgen2/xats2cz/BUILD/xats2cz-bundle.js" "$T" 2>/dev/null \
    | awk '/BEGIN==/{f=1;next}/END==/{f=0}f' > "$BUILD/seed_m0.scm"
  echo "   PY-built body: $(wc -l < "$BUILD/py_m0.scm") lines; seed body: $(wc -l < "$BUILD/seed_m0.scm") lines"
  if diff -q "$BUILD/py_m0.scm" "$BUILD/seed_m0.scm" >/dev/null 2>&1; then
    echo ">> SELF-HOST CHECK: PY-built compiler emits BYTE-IDENTICAL Scheme to the seed on m0_hello"
  else
    echo "!! differs from seed (first diffs):"; diff "$BUILD/py_m0.scm" "$BUILD/seed_m0.scm" | head -20
  fi
fi
echo ">> done."
