#!/usr/bin/env bash
# selfhost_broad.sh — compile a broad set of compiler .dats (prelude + frontend)
# to Scheme and concatenate with the CATS runtime.  TWO PHASES so cross-file
# higher-order template continuations resolve:
#   phase 1: compile each file, collect its per-file lambda-lifting map (the
#            ";;LIFTED name conts" dump comments) into a GLOBAL map.
#   phase 2: recompile each file seeding that global map (--czmap NAME CONT), so
#            a call site whose callee is defined+lifted in another file injects
#            the right continuations.
#   tools/selfhost_broad.sh <unitlist-file> [driver.scm]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
BUNDLE="$HERE/srcgen2/BUILD/xats2chez-bundle.js"
CACHE="$HERE/srcgen2/BUILD/selfhost/cache"; mkdir -p "$CACHE"
RT="$HERE/../../srcgen1/prelude/DATS/CATS/CHEZ/xats2chez_cats.scm $HERE/../../srcgen1/prelude/DATS/CATS/CHEZ/xats2chez_runtime.scm $HERE/../../srcgen1/prelude/DATS/CATS/CHEZ/xats2chez_collrt.scm"
LIST="$1"; DRIVER="${2:-}"

srcof() { for d in "$XATSHOME/srcgen2/DATS" "$XATSHOME/prelude/DATS"; do
  [ -f "$d/$1.dats" ] && { echo "$d/$1.dats"; return; }; done; echo ""; }

UNITS="$(grep -vE '^\s*#|^\s*$' "$LIST")"
NU=$(echo "$UNITS" | wc -w | tr -d ' ')

# ---- phase 1: compile each unit (no seeding), extract Scheme to <u>.p1.scm ----
echo ">> phase 1: compiling $NU units..."
for u in $UNITS; do
  src="$(srcof "$u")"; [ -n "$src" ] || { echo "MISS-SRC $u" >&2; continue; }
  node --stack-size=8801 "$BUNDLE" "$src" 2>/dev/null > "$CACHE/$u.p1.raw"
  awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next}/^;;==XATS2CHEZ-END==/{f=0}f' "$CACHE/$u.p1.raw" > "$CACHE/$u.p1.scm"
  rm -f "$CACHE/$u.p1.raw"
done

# ---- build the GLOBAL lifting map from all ";;LIFTED name cont..." dumps ----
# emit "--czmap NAME CONT" pairs.  CRITICAL: the continuations of an instance must
# be seeded IN PARAM ORDER (the order they appear on the ;;LIFTED line = the order
# the emitter lifted them as trailing params); a sort would scramble them so the
# injected args bind to the wrong params.  So keep the FIRST LIFTED line per name
# (dedup by name) and emit its conts left-to-right, no sort.
GMAP="$CACHE/.global.czmap"
grep -hE '^;;LIFTED ' "$CACHE"/*.p1.scm 2>/dev/null \
  | awk '!seen[$2]++ {for(i=3;i<=NF;i++) print $2, $i}' > "$GMAP"
# bodyless higher-order prelude primitives (provided by the CATS runtime) whose
# continuation can't be discovered from a body -- seed them so call sites inject.
printf 'strx_vt_map0 map$fopr0\n' >> "$GMAP"
CZARGS=()
while read -r name cont; do [ -n "$name" ] && CZARGS+=(--czmap "$name" "$cont"); done < "$GMAP"
echo ">> global map: $(wc -l < "$GMAP" | tr -d ' ') (instance,continuation) pairs"

# ---- phase 2: recompile each unit seeding the global map ----
echo ">> phase 2: recompiling with global map..."
for u in $UNITS; do
  src="$(srcof "$u")"; [ -n "$src" ] || continue
  node --stack-size=8801 "$BUNDLE" "$src" "${CZARGS[@]}" 2>/dev/null > "$CACHE/$u.raw"
  awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next}/^;;==XATS2CHEZ-END==/{f=0}f' "$CACHE/$u.raw" > "$CACHE/$u.scm"
  rm -f "$CACHE/$u.raw"
done

# ---- assemble the image ----
# Order: runtime floor (cats/runtime/collrt) -> compiled units -> GENERICS layer
# (loaded LAST so its correct polymorphic g_cmp/char_eq/strn_make_llist win over
# the type-erased per-unit instances that clobber each other) -> driver.
GENRT="$HERE/../../srcgen1/prelude/DATS/CATS/CHEZ/xats2chez_generics.scm"
IMG="$HERE/srcgen2/BUILD/selfhost/broad.scm"
cat $RT > "$IMG"
for u in $UNITS; do [ -f "$CACHE/$u.scm" ] && cat "$CACHE/$u.scm" >> "$IMG"; done
cat "$GENRT" >> "$IMG"
[ -n "$DRIVER" ] && [ -f "$DRIVER" ] && cat "$DRIVER" >> "$IMG"
echo ">> image: $(grep -c '(define' "$IMG") defines"
