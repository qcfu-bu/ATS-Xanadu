#!/bin/bash
# leaf-census: the CATS-LEAF RATCHET for the fallback-removal architecture.
#
# Under universal resolved-prelude emission, every `xatsgo.Xats_*` reference
# in the assembled selfhost source is a RUNTIME LEAF BINDING: a primitive the
# frontend's prelude source binds by extern name at the CATS boundary.  This
# script lists the referenced set, diffs it against the runtime package's
# defined set, and (with a baseline file) ratchets the referenced set so a
# resolver regression -- an instance silently falling back to a runtime name
# instead of resolving to compiled ATS source -- shows up as a NEW name here
# even before the go build fails on it.
#
# usage: leaf-census.sh          # report + diff against baseline if present
#        leaf-census.sh --pin    # (re)write the baseline from current state
set -u
X=${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}
O=$X/srcgen2/xats2go/selfhost-build
RT=$X/srcgen2/xats2go/runtime/xatsgo/xatsgo.go
BASE=$O/tests/leaf-census.base

# the assembly may be the single emitter_all.go OR the split packages
# (zzbase/zzfe*/zzcc/zzgo + main files) — scan whichever exists.
refs=$(grep -rhoE --include='*.go' 'xatsgo\.Xats_[A-Za-z0-9_]+' "$O/src" | sed 's/^xatsgo\.//' | sort -u)
defs=$( (grep -oE '^func (Xats_[A-Za-z0-9_]+)' "$RT" | awk '{print $2}';
         grep -oE '^var (Xats_[A-Za-z0-9_]+)' "$RT" | awk '{print $2}';
         grep -oE '^func (Xats_[A-Za-z0-9_]+)' "$O"/src/zz_*.go | awk '{print $2}';
         grep -oE '^var (Xats_[A-Za-z0-9_]+)' "$O"/src/zz_*.go | awk '{print $2}') | sort -u)

nref=$(echo "$refs" | grep -c .)
undef=$(comm -23 <(echo "$refs") <(echo "$defs"))
unused=$(comm -13 <(echo "$refs") <(echo "$defs"))

echo ">> LEAF CENSUS: $nref distinct runtime names referenced by the assembly"
if [ -n "$undef" ]; then
  echo "!! UNDEFINED (referenced but not in runtime -- resolver gap or missing leaf):"
  echo "$undef" | sed 's/^/     /'
fi
echo ">> unreferenced runtime definitions (deletion candidates): $(echo "$unused" | grep -c .)"

if [ "${1:-}" = "--pin" ]; then
  echo "$refs" > "$BASE"
  echo ">> baseline pinned: $BASE ($nref names)"
  exit 0
fi

if [ -f "$BASE" ]; then
  new=$(comm -23 <(echo "$refs") <(sort -u "$BASE"))
  if [ -n "$new" ]; then
    echo "!! LEAF RATCHET RED: names NOT in the pinned baseline (new fallback?):"
    echo "$new" | sed 's/^/     /'
    exit 1
  fi
  echo ">> LEAF RATCHET GREEN (no names beyond the pinned baseline)"
else
  echo ">> no baseline yet (pin with: leaf-census.sh --pin)"
fi
