#!/bin/bash
# typecheck-sample.sh — FAST emitter typecheck against COMPILER-GRADE code.
#
# The problem this solves: psuite programs are small and miss whole construct
# classes (datacon mutation, tuple repack, byref fields, exceptions in anger).
# Those only showed up in `full-verify`, whose 194-module re-emission makes it
# a ~45min debugger.  This emits a DIVERSE SAMPLE of real compiler modules,
# concatenates them into one package, and runs `go build`, then FILTERS OUT
# the unavoidable cross-module `undefined:` errors — everything that remains
# is a genuine emitter type error, found in ~4 minutes instead of ~45.
#
#   usage: typecheck-sample.sh [N]     (default: the curated 12-module set)
set -u
ulimit -s 65520 2>/dev/null || true
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X NODE_COMPILE_CACHE=$X/srcgen2/xats2go/srcgen2/BUILD/.v8cache
BUNDLE=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
W=$X/srcgen2/xats2go/selfhost-build/probe/tcsample
# emissions in $W (CACHED: re-emitted only when the bundle is newer), the Go
# package in $W/pkg containing ONLY the concatenation — keeping the per-module
# files out of the package dir, or Go compiles both and everything redeclares.
mkdir -p "$W" "$W/pkg"

# curated for CONSTRUCT COVERAGE, not size:
#   list000_vt   destination-passing $addr(field) + byref cells   (found 3 bugs)
#   dynexp2      record field setters (root is a PARAMETER)
#   intrep0      i0pat nodes the hand-written shims destructure
#   lexing0_token0 / trans12_dynexp  tuple repack + heavy matching
#   xatsopt_tmplib exception raise/catch;  statyp2_utils2 deep datatypes
MODS=(
  "$X/srcgen1/prelude/DATS/VT/list000_vt.dats"
  "$X/srcgen2/DATS/dynexp2.dats"
  "$X/srcgen2/DATS/dynexp3_utils0.dats"
  "$X/srcgen2/DATS/lexing0_token0.dats"
  "$X/srcgen2/DATS/trans12_dynexp.dats"
  "$X/srcgen2/DATS/trans2a_dynexp.dats"
  "$X/srcgen2/DATS/statyp2_utils2.dats"
  "$X/srcgen2/DATS/xatsopt_tmplib.dats"
  "$X/srcgen2/DATS/trtmp3c_dynexp.dats"
  "$X/srcgen2/DATS/f3perr0_dynexp.dats"
  "$X/srcgen2/xats2go/srcgen2/DATS/go1emit_dynexp.dats"
  "$X/srcgen2/xats2go/xats2cc/srcgen1/DATS/intrep0.dats"
  # ABSIMPL-BEARING modules: a local `datavwtp` assumed to a SATS `#absvtbx`
  # gives the SAME value two views -- concrete datatype at a constructor
  # field, abstract box at a SATS-declared signature.  full-verify caught 36
  # byref shape errors here that the curated set above could not see.
  "$X/srcgen2/xats2go/srcgen2/DATS/trxi0i1_myenv0.dats"
  "$X/srcgen2/DATS/trtmp3b_myenv0.dats"
  "$X/srcgen2/DATS/trtmp3c_myenv0.dats"
)

t0=$(date +%s)
n=0
for f in "${MODS[@]}"; do
  [ -f "$f" ] || { echo "!! missing: $f"; continue; }
  m=$(basename "$f" .dats)
  if [ -s "$W/$m.go" ] && [ ! "$BUNDLE" -nt "$W/$m.go" ] && [ ! "$f" -nt "$W/$m.go" ]; then continue; fi
  ( node --stack-size=50000 "$BUNDLE" "$f" 2>"$W/$m.err" \
      | awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' > "$W/$m.go" ) &
  n=$((n+1)); [ $((n % 3)) -eq 0 ] && wait
done
wait
echo ">> emitted $n modules (cached: $(( ${#MODS[@]} - n ))) in $(( $(date +%s) - t0 ))s"

# one package: shared preamble + each module's body, layout blocks deduped
{
  printf 'package main\n\nimport "xatsgo"\nimport "unsafe"\n\nvar _ = xatsgo.XATSNIL\nvar _ unsafe.Pointer\n\n'
  i=0
  for f in "${MODS[@]}"; do
    m=$(basename "$f" .dats); [ -s "$W/$m.go" ] || continue
    i=$((i+1))
    awk 'BEGIN{started=0}
         /^type zzs_[a-z]* struct \{$/{lay=1}
         lay{if($0=="}"){lay=0}; next}
         /^func zzpzzs_/{next}
         /^func /{started=1}
         /^var [^_]/{started=1}
         started{print}' "$W/$m.go" \
      | sed -E "s/goxtnm([0-9])/gs${i}tnm\1/g" \
      | sed "s/^func main() {\$/func zzsmain_${i}() {/"
    printf '\n'
  done
  # layouts: union, deduped by name (same rule as assemble.sh)
  for f in "${MODS[@]}"; do
    m=$(basename "$f" .dats); [ -s "$W/$m.go" ] || continue
    awk '/^type zzs_[a-z]* struct \{$/{lay=1} lay{print; if($0=="}"){lay=0}; next} /^func zzpzzs_/{print}' "$W/$m.go"
  done | awk '/^type (zzs_[a-z]*) struct \{$/{nm=$2; if(nm in seen){skip=1} else {seen[nm]=1; skip=0}; if(!skip)print; next}
              /^func zzpzzs_/{fn=$2; sub(/\(.*/,"",fn); if(fn in seenf)next; seenf[fn]=1; print; next}
              !skip{print} /^\}$/{skip=0}'
} > "$W/pkg/all.go"

printf 'module tcsample\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' \
  "$X/srcgen2/xats2go/runtime/xatsgo" > "$W/pkg/go.mod"

( cd "$W/pkg" && go build -gcflags=-e -o /dev/null . 2> "$W/build.err" )
# cross-module references are EXPECTED to be undefined here; anything else is real
# a MANGLED cross-module name ends in _<stamp>; those are expected to be
# undefined in a sample build.  Anything else is a genuine emitter defect.
grep -vE 'undefined: [A-Za-z_][A-Za-z0-9_]*_[0-9]+$|^#|^\s' "$W/build.err" > "$W/real.err" || true
real=$(grep -c . "$W/real.err" || true)
echo ">> TYPECHECK-SAMPLE: $(grep -c . "$W/build.err" || true) raw errors, $real REAL (cross-module undefined filtered)"
head -20 "$W/real.err"
echo ">> total $(( $(date +%s) - t0 ))s"
[ "$real" = 0 ]
