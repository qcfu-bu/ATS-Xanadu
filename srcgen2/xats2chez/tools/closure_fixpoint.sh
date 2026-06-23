#!/usr/bin/env bash
# closure_fixpoint.sh — compile EVERY listed unit (prelude+frontend) to Scheme in
# parallel (phase-1, no seeding -- this is a COVERAGE analysis, not a runnable
# image), concatenate with the CATS runtime, and report what is still globally
# undefined = the remaining primitive floor + emitter gaps.  Tracks compile fails.
#   tools/closure_fixpoint.sh <unitlist>
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
BUNDLE="$HERE/srcgen2/BUILD/xats2chez-bundle.js"
CACHE="$HERE/srcgen2/BUILD/selfhost/fxp"; mkdir -p "$CACHE"
RT="$HERE/runtime/scheme/xats2chez_cats.scm $HERE/runtime/scheme/xats2chez_runtime.scm $HERE/runtime/scheme/xats2chez_collrt.scm $HERE/runtime/scheme/xats2chez_generics.scm"
UNITS="$(grep -vE '^\s*#|^\s*$' "$1")"

srcof() { for d in "$XATSHOME/srcgen2/DATS" "$XATSHOME/prelude/DATS"; do
  [ -f "$d/$1.dats" ] && { echo "$d/$1.dats"; return; }; done; echo ""; }
export -f srcof; export XATSHOME BUNDLE CACHE

comp1() {
  local u="$1" src; src="$(srcof "$u")"; [ -n "$src" ] || { echo "MISS $u"; return; }
  local try n
  for try in 1 2 3; do
    node --stack-size=8801 "$BUNDLE" "$src" 2>"$CACHE/$u.err" > "$CACHE/$u.raw"
    awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next}/^;;==XATS2CHEZ-END==/{f=0}f' "$CACHE/$u.raw" > "$CACHE/$u.scm"
    n=$(grep -c '(define' "$CACHE/$u.scm"); rm -f "$CACHE/$u.raw"
    [ "$n" -gt 0 ] && break
  done
  # PANIC on real compile failures: a file with top-level implementations that
  # emits NOTHING failed silently.  Interface-only files (no impls) legitimately
  # emit 0 -- not a failure.
  if [ "$n" -eq 0 ]; then
    local impls; impls=$(grep -cE '^#implfun|^implement|^#impltmp|^val |^fun ' "$src" 2>/dev/null)
    if [ "$impls" -gt 0 ]; then
      local e1; e1=$(grep -m1 -oE '\(line=[0-9]+,offs=[0-9]+\):D[0-9][A-Za-z]+errck' "$CACHE/$u.err" 2>/dev/null | head -1)
      echo "FAIL $u ($impls impls, 0 emitted) $e1"
    fi
  fi
}
export -f comp1

echo ">> compiling $(echo "$UNITS"|wc -w|tr -d ' ') units (parallel -P6)..."
RES=$(echo "$UNITS" | xargs -P 6 -n 1 bash -c 'comp1 "$0"' 2>&1)
FAILS=$(echo "$RES" | grep -c '^FAIL ' || true)
if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "########################################################################"
  echo "## COMPILATION PANIC: $FAILS unit(s) FAILED (impls present, 0 emitted) ##"
  echo "########################################################################"
  echo "$RES" | grep '^FAIL '
  echo "########################################################################"
fi

IMG="$CACHE/all.scm"; cat $RT > "$IMG"
for u in $UNITS; do [ -f "$CACHE/$u.scm" ] && cat "$CACHE/$u.scm" >> "$IMG"; done
echo ">> image: $(grep -c '(define' "$IMG") defines"
python3 - "$IMG" <<'PY'
import re,sys
img=open(sys.argv[1]).read()
ld=set(re.findall(r'\(define\s+\(?([A-Za-z_][\w$]*)',img))
ld|=set(re.findall(r'\(\(([A-Za-z_][\w$]*)\s',img))
for p in re.findall(r'\(lambda \(([^)]*)\)',img): ld|=set(p.split())
ld|=set(re.findall(r'\(letrec \(\(([A-Za-z_][\w$]*)',img))
called=re.findall(r'\(([A-Za-z_][\w$]*)',img)
sb=set('define lambda let letrec letrec* if cond when unless begin case and or not set! quote vector vector-ref vector-set! vector-length make-vector box unbox set-box! display newline call/1cc call/cc dynamic-wind values call-with-values apply quotient remainder modulo string string-append string-length string-ref string=? string<? string>? substring string-set! make-string number->string string->number char->integer integer->char reverse list list->vector list->string vector->list append map for-each length null? pair? car cdr cons eq? eqv? equal? min max abs expt exact inexact floor error raise guard case-lambda make-parameter parameterize make-hashtable hashtable-ref hashtable-set! hashtable-delete! hashtable-size hashtable-contains? hashtable-keys equal-hash string-hash symbol-hash bitwise-and bitwise-ior bitwise-xor bitwise-not bitwise-arithmetic-shift fl+ fl- fl* fl/ fl< fl> fl<= fl>= fl= flonum? integer? infinite? nan? boolean? char? number? string? symbol? procedure? vector? void condition? display-condition condition/report-string call-with-string-output-port'.split())
und=sorted({c for c in called if c not in ld and c not in sb and ('_' in c or '$' in c) and not re.search(r'_\d+$',c) and not re.match(r'^cz',c)})
print(f">> GLOBALLY UNDEFINED ({len(und)}) -- the remaining floor + gaps:")
for i in range(0,len(und),6): print("   "+" ".join(und[i:i+6]))
PY
