#!/usr/bin/env bash
########################################################################
# compile-py.sh — Phase C of the self-host: compile each PY/ pythonic component
# (.pdats) through pyfront_cz in MIRROR MODE -> a Chez Scheme fragment.
#
# Mirror mode (PYL_MIRROR_ROOT=PY) makes a .pdats import its sibling pythonic .psats
# interfaces via OUR loader (cz_load_pysats); the prelude + compiler HATS still resolve
# to their ATS originals via XATSHOME. The emitted Scheme is the same code the stock
# xats2cz backend emits for the corresponding .dats.
#
# Fragments land in BUILD/py-scm/NNNN_<kind>_<base>.scm (NNNN = list order, for assembly).
#
# Usage:
#   bash frontend/compile-py.sh            # compile all 171 components, baseline report
#   bash frontend/compile-py.sh --force    # recompile even cached fragments
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYL_MIRROR_ROOT="$HERE/PY"
BUILD="$HERE/BUILD"
PY="$HERE/PY"
BUNDLE="$BUILD/pyfront-cz.js"
SCMDIR="$BUILD/py-scm"
NODE="node --stack-size=8801"
mkdir -p "$SCMDIR"

FORCE=0; for a in "$@"; do [ "$a" = "--force" ] && FORCE=1; done
[ -s "$BUNDLE" ] || { echo "!! missing $BUNDLE — run build-cz.sh first" >&2; exit 1; }

# The 171 .dats components in ORDER (= the assembly order): SH_FE, then SH_BE, then cz0emit, driver.
LIST="$BUILD/py-mirror.files"
[ -s "$LIST" ] || { echo "!! missing $LIST — run convert-py.sh first" >&2; exit 1; }

REPORT="$BUILD/py-compile.report"; : > "$REPORT"
DATSLIST="$BUILD/py-compile.dats"
grep '\.dats$' "$LIST" > "$DATSLIST"
pass=0; fail=0; n=0; idx=0
total=$(wc -l < "$DATSLIST" | tr -d ' ')
echo ">> compiling $total .pdats components (mirror mode) -> $SCMDIR"

while IFS= read -r rel <&3; do
  n=$((n+1)); idx=$((idx+1))
  pdats="$PY/${rel%.dats}.pdats"
  base="$(basename "${rel%.dats}")"
  # kind tag for assembly grouping
  case "$rel" in
    srcgen2/xats2js/*) kind=be;;
    srcgen2/xats2cz/DATS/*) kind=cz;;
    srcgen2/xats2cz/UTIL/*) kind=drv;;
    *) kind=fe;;
  esac
  frag="$SCMDIR/$(printf '%04d' "$idx")_${kind}_${base}.scm"
  errf="$SCMDIR/$(printf '%04d' "$idx")_${kind}_${base}.err"
  if [ ! -f "$pdats" ]; then echo "NOPDATS  $rel" >> "$REPORT"; fail=$((fail+1)); continue; fi
  if [ "$FORCE" -eq 0 ] && [ -s "$frag" ]; then pass=$((pass+1)); continue; fi
  raw="$SCMDIR/.raw_$idx"
  $NODE "$BUNDLE" "$pdats" < /dev/null > "$raw" 2>"$errf"
  rc=$?
  nerr=$(grep -oE "nerror \(after tread3a\) = [0-9]+" "$errf" 2>/dev/null | grep -oE "[0-9]+$" | tail -1)
  nerr=${nerr:-X}
  awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$raw" > "$frag"
  rm -f "$raw"
  body=$(wc -l < "$frag" | tr -d ' ')
  if [ "$rc" -ne 0 ]; then
    echo "CRASH    $rel (rc=$rc) -> $errf" >> "$REPORT"; fail=$((fail+1)); rm -f "$frag"
  elif [ "$nerr" != "0" ]; then
    echo "NERROR=$nerr $rel -> $errf" >> "$REPORT"; fail=$((fail+1)); rm -f "$frag"
  elif grep -q 'UNHANDLED\|BODILESS' "$frag"; then
    echo "UNHANDLED $rel ($body lines) -> $frag" >> "$REPORT"; fail=$((fail+1))
  else
    echo "PASS     $rel ($body lines)" >> "$REPORT"; pass=$((pass+1))
  fi
  [ $((n % 20)) -eq 0 ] && echo "   ... $n/$total (pass=$pass fail=$fail)"
done 3< "$DATSLIST"
rm -f "$SCMDIR"/.raw_*

echo "======================================================================"
echo ">> Phase C baseline: PASS=$pass  FAIL=$fail  (of $total)"
echo ">> report: $REPORT  — failures:"
grep -vE "^PASS" "$REPORT" | head -60
echo "======================================================================"
