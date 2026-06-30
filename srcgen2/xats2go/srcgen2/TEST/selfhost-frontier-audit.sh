#!/usr/bin/env bash
# selfhost-frontier-audit.sh — map the self-hosting frontier of the go-emitter.
#
# Runs the (non-go-arm) go-emitter on EACH of its OWN srcgen2/DATS source
# modules and reports, per module:
#   FUNCS     package-level Go funcs emitted (real emission, not vacuous)
#   REAL_UNH  genuine `/* UNHANDLED: */` markers (string-literal occurrences of
#             the word UNHANDLED in the emitter's own source are excluded — they
#             are the emitter's fallback strings, faithfully reproduced)
#   INT_ROUTE compiler-internal frontend names routed through the xatsgo runtime
#             (d2cst/d2var/token_get_node/fprint_loctn_as_stamp) — the genuine
#             FRONTEND-coupling boundary that emitter self-hosting bottoms out at
#
# A module is "self-hosting-clean" when REAL_UNH = 0 AND INT_ROUTE = 0.
#
# Usage:  bash srcgen2/TEST/selfhost-frontier-audit.sh
# Run from the xats2go dir (srcgen2/xats2go).  Needs XATSHOME exported or the
# default repo layout.
set -uo pipefail

X="${XATSHOME:-/home/user/ATS-Xanadu}"
export XATSHOME="$X"
GOPATCHED="srcgen2/BUILD/xats2go-bundle.patched.js"
[ -f "$GOPATCHED" ] || { echo "!! emitter bundle missing: $GOPATCHED (run: make bundle)"; exit 2; }

W="$(mktemp -d)"
ROUTE_RE='xatsgo\.Xats_(d2cst|d2var|token_get_node|fprint_loctn_as_stamp)'
UNH_RE='(^|[^"])/\*[[:space:]]*UNHANDLED:|^[[:space:]]*//[[:space:]]*UNHANDLED:'

printf "%-26s %6s %8s %9s\n" MODULE FUNCS REAL_UNH INT_ROUTE
clean=0; total=0; route_total=0
for f in srcgen2/DATS/*.dats; do
  n="$(basename "$f" .dats)"; total=$((total+1))
  node --stack-size=8801 "$GOPATCHED" "$f" > "$W/$n.raw" 2>"$W/$n.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$W/$n.raw" > "$W/$n.go"
  funcs="$(grep -cE '^func[ \t]+[A-Za-z_]' "$W/$n.go")"
  unh="$(grep -cE "$UNH_RE" "$W/$n.go")"
  rt="$(grep -cE "$ROUTE_RE" "$W/$n.go")"
  route_total=$((route_total+rt))
  [ "$unh" -eq 0 ] && [ "$rt" -eq 0 ] && clean=$((clean+1))
  printf "%-26s %6s %8s %9s\n" "$n" "$funcs" "$unh" "$rt"
done
echo "----------------------------------------------------------------------"
echo ">> $clean/$total modules self-hosting-clean; $route_total frontend-accessor routing site(s) remain"
rm -rf "$W"
