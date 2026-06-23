#!/usr/bin/env bash
########################################################################
# L0 CONSTRUCT-COVERAGE AUDIT  (the proactive, grammar-derived gap check)
#
# Enumerates every L0 AST variant from the stock datatype definitions
# (srcgen2/SATS/{dynexp0,staexp0}.sats) and checks whether the pretty-printer
# (frontend/DATS/pyprint.dats) has an emitter for it. A MISSing emitter is a
# definite ATS->pythonic round-trip gap, independent of which corpus file
# happens to exercise it.
#
# Run after each construct-class feature lands to confirm coverage grows and no
# new construct slipped through. See frontend/docs/CONSTRUCT-COVERAGE.md.
#
# Usage:  bash frontend/build-construct-coverage.sh [--all]
#   (default) print only MISSING emitters, grouped by datatype
#   --all     print OK + MISS for every construct
########################################################################
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XATSHOME="${XATSHOME:-$(cd "$HERE/.." && pwd)}"
PP="$HERE/DATS/pyprint.dats"
DYN="$XATSHOME/srcgen2/SATS/dynexp0.sats"
STA="$XATSHOME/srcgen2/SATS/staexp0.sats"
SHOW_ALL=0; [ "${1:-}" = "--all" ] && SHOW_ALL=1

is_recovery() { case "$1" in *errck|*tkerr|*tkskp|*synext) return 0;; *) return 1;; esac; }

audit_group() {
  local label="$1" pref="$2" file="$3" dtype="$4"
  local miss=0 total=0
  echo "=== $label ($pref) ==="
  # Scope to this datatype's definition block (`<dtype> = … ` up to the next
  # top-level `<name> =` def) so we count the datatype's VARIANTS, not constructor
  # USES elsewhere. Constructors appear at line-start or after a `|`, with `of`.
  local block
  block="$(awk -v d="$dtype" '
    $0 ~ ("^"d" =") {p=1}
    p && /^[a-z][A-Za-z0-9_]* =/ && $0 !~ ("^"d" =") {exit}
    p {print}' "$file")"
  for c in $(echo "$block" | grep -oE "${pref}[A-Za-z0-9_]+" | sort -u); do
    is_recovery "$c" && continue
    total=$((total+1))
    if grep -qE "$c" "$PP"; then
      [ "$SHOW_ALL" = 1 ] && echo "  OK   $c"
    else
      echo "  MISS $c"; miss=$((miss+1))
    fi
  done
  echo "  -> $((total-miss))/$total emitted; $miss missing"
}

echo ">> pyprint emitter coverage vs the L0 grammar"
audit_group "d0ecl (declarations)"      D0C "$DYN" d0ecl_node
audit_group "d0exp (dyn expressions)"   D0E "$DYN" d0exp_node
audit_group "d0pat (patterns)"          D0P "$DYN" d0pat_node
audit_group "s0exp (static/type exprs)" S0E "$STA" s0exp_node
audit_group "g0exp (static/guard exprs)" G0E "$STA" g0exp_node
echo ">> done. Missing emitters are the grammar-derived backlog (see docs/CONSTRUCT-COVERAGE.md)."
