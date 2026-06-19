#!/usr/bin/env bash
########################################################################
# build-lib2xatsopt-par.sh  —  PARALLEL build of srcgen2/lib/lib2xatsopt.js
#
# Identical OUTPUT to build-lib2xatsopt.sh (byte-for-byte), but transpiles
# the ~162 compiler .dats files concurrently instead of serially.
#
# Why this is safe to parallelize (unlike `make -j` on the stock Makefile):
# the per-file template namespace `jsx<N>tnm` uses N = the file's FIXED
# POSITION in the SRCDATS list, not a running counter. So each file's work
# (transpile + sed with its fixed N) is fully independent; only the final
# concatenation must be in list order.
#
# Concurrency is bounded to #cores (each transpile is a ~2.5MB node process,
# so unbounded fan-out would thrash memory).
#
# Usage:  XATSHOME=/path bash build-lib2xatsopt-par.sh [JOBS]
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
SRCGEN2="$XATSHOME/srcgen2"
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
BUILD="$SRCGEN2/BUILD/JS"
OUTLIB="$SRCGEN2/lib/lib2xatsopt.js"
JOBS="${1:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"
mkdir -p "$BUILD" "$SRCGEN2/lib"

# Same authoritative SRCDATS list/ordering as the serial script (from the Makefile).
DATS_LIST="$(awk '/^SRCDATS :=/{f=1;next} f&&/^$/{f=0} f{gsub(/\\/,"");for(i=1;i<=NF;i++) if($i ~ /\.dats$/) print $i}' "$SRCGEN2/Makefile_xjsemit")"
NTOTAL="$(printf '%s\n' "$DATS_LIST" | grep -c .)"

echo ">> [parallel, $JOBS jobs] transpiling $NTOTAL .dats files"
export XATSHOME JSEMIT BUILD SRCGEN2

# Phase 1 (parallel): each "N file" -> out0 (transpile) -> out1 (sed jsxNtnm).
# N is the list position (awk NR), identical to the serial loop's counter.
printf '%s\n' "$DATS_LIST" | grep . | awk '{print NR, $0}' \
| xargs -P "$JOBS" -L1 bash -c '
    n="$1"; f="$2"
    src="$SRCGEN2/DATS/$f"; base="${f%.dats}"
    out0="$BUILD/${base}_dats_out0.js"; out1="$BUILD/${base}_dats_out1.js"
    if [ ! -f "$src" ]; then echo "   !! MISSING $src" >&2; exit 0; fi
    node --stack-size=8801 "$JSEMIT" "$src" > "$out0" 2>/dev/null
    sed -e "s/jsxtnm/jsx${n}tnm/g" "$out0" > "$out1"
    printf "   [%3d] %s\n" "$n" "$f"
  ' _

# Phase 2 (serial, fast): concatenate out1 files in list order -> the lib.
echo ">> concatenating in list order -> $OUTLIB"
: > "$OUTLIB"
for f in $DATS_LIST; do
  base="${f%.dats}"; out1="$BUILD/${base}_dats_out1.js"
  if [ -f "$out1" ]; then cat "$out1" >> "$OUTLIB"; else echo "   !! missing out1 for $f" >&2; fi
done
echo ">> done: $OUTLIB ($(wc -l < "$OUTLIB") lines)"
# Verify identical to the serial build with:
#   diff <(bash build-lib2xatsopt.sh >/dev/null; cat $OUTLIB) <(bash build-lib2xatsopt-par.sh >/dev/null; cat $OUTLIB)
