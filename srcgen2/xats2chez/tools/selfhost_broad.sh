#!/usr/bin/env bash
# selfhost_broad.sh — compile a broad set of compiler .dats (prelude + frontend)
# to Scheme, cached + parallel, concatenate with the CATS runtime, and report
# the closure status (defines + undefined symbols).  Chez top-level allows
# forward refs, so concat order is irrelevant; we just need every called symbol
# defined SOMEWHERE in the image.
#   tools/selfhost_broad.sh <unitlist-file> [driver.scm]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
BUNDLE="$HERE/srcgen2/BUILD/xats2chez-bundle.js"
CACHE="$HERE/srcgen2/BUILD/selfhost/cache"; mkdir -p "$CACHE"
RT="$HERE/runtime/scheme/xats2chez_cats.scm $HERE/runtime/scheme/xats2chez_runtime.scm"
LIST="$1"; DRIVER="${2:-}"

# resolve a unit name to its .dats (prelude or frontend)
srcof() { for d in "$XATSHOME/srcgen2/DATS" "$XATSHOME/prelude/DATS"; do
  [ -f "$d/$1.dats" ] && { echo "$d/$1.dats"; return; }; done; echo ""; }

# compile one unit to cache (skip if cached & newer than source)
compile1() {
  local u="$1" src; src="$(srcof "$u")"
  [ -n "$src" ] || { echo "MISS-SRC $u" >&2; return; }
  local out="$CACHE/$u.scm"
  if [ -f "$out" ] && [ "$out" -nt "$src" ]; then return; fi
  node --stack-size=8801 "$BUNDLE" "$src" 2>/dev/null > "$out.raw"
  awk '/^;;==XATS2CHEZ-BEGIN==/{ff=1;next}/^;;==XATS2CHEZ-END==/{ff=0}ff' "$out.raw" > "$out"
  rm -f "$out.raw"
}
export -f compile1 srcof
export XATSHOME BUNDLE CACHE

UNITS="$(grep -vE '^\s*#|^\s*$' "$LIST")"
echo ">> compiling $(echo "$UNITS"|wc -w|tr -d ' ') units (parallel)..."
echo "$UNITS" | xargs -P 8 -n 1 bash -c 'compile1 "$0"'

IMG="$HERE/srcgen2/BUILD/selfhost/broad.scm"
cat $RT > "$IMG"
for u in $UNITS; do [ -f "$CACHE/$u.scm" ] && cat "$CACHE/$u.scm" >> "$IMG"; done
[ -n "$DRIVER" ] && [ -f "$DRIVER" ] && cat "$DRIVER" >> "$IMG"
echo ">> image: $(grep -c '(define' "$IMG") defines"
python3 - "$IMG" <<'PY'
import re,sys
img=open(sys.argv[1]).read()
ld=set(re.findall(r'\(define\s+\(?([A-Za-z_][\w$]*)',img))
ld|=set(re.findall(r'\(\(([A-Za-z_][\w$]*)\s',img))
for p in re.findall(r'\(lambda \(([^)]*)\)',img): ld|=set(p.split())
called=re.findall(r'\(([A-Za-z_][\w$]*)',img)
sb=set('define lambda let letrec if cond when begin case and or set! vector vector-ref vector-set! box unbox set-box! display call/1cc quotient remainder string string-append string-length string-ref string=? string<? string>? substring number->string char->integer integer->char reverse list->vector list->string make-string make-vector string-set! guard raise error eq? equal? not min max abs newline current-error-port make-hashtable hashtable-ref hashtable-set! hashtable-size hashtable-contains? equal-hash string-hash bitwise-and bitwise-ior bitwise-xor bitwise-arithmetic-shift'.split())
und=sorted({c for c in called if c not in ld and c not in sb and ('_' in c or '$' in c) and not re.match(r'^(czscrut|czret|czlz|czdv)',c)})
print(f">> undefined ({len(und)}):")
for i in range(0,len(und),6): print("   "+" ".join(und[i:i+6]))
PY
