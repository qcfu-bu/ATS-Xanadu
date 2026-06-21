#!/usr/bin/env bash
########################################################################
# SYMIMP (bootstrap P1 GAP1 + GAP2) — the overload-ALIAS surface + import crash-safety.
#
# GAP1 — `@overload NAME = TARGET` ([+ @overload[N] precedence]) = the ATS-parity
#         `#symload NAME with TARGET [of N]` (2012× corpus-wide): re-export an ALREADY-EXISTING
#         function TARGET into the overload set of a DIFFERENT symbol NAME (NO def being defined).
#         The new surface lowers to PCCsymalias -> D2Csymload via the SAME build_overload recipe
#         the `@overload def` self-overload uses (precedence -> the d2ptm pval; READ at typecheck).
#
# GAP2 — `import` / `from … import *` is ENOENT-SAFE: a MISSING target yields a CLEAN counted
#         diagnostic + a survivable no-op (NOT an uncaught throw / a driver crash). The quoted
#         string-path form `from "x" import *` strips its quotes (no more `/"x".sats`).
#
# Fixtures (frontend/TEST/symimp/):
#   1. si_overload_alias.pdats  — `@overload is_nil = stamp_nilq` + a use `is_nil(x)`  => nerror=0
#   2. si_overload_prec.pdats   — `@overload[1000]` precedence payload variant            => nerror=0
#   3. si_missing_import.pdats  — `from NonexistentModule import *`  => NO crash, nerror>0 (a clean
#                                  diagnostic, NOT an ENOENT throw / SIGSEGV). Asserts rc != 139 +
#                                  the @missing-import errck + nerror>0.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse -> elab ->
# lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build (or reuse) the M3
# driver bundle, then run + assert each fixture. PURELY ADDITIVE; builds only into frontend/BUILD.
#
# Usage:
#   bash frontend/build-symimp.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-symimp.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/symimp"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the symalias lowering + import guard ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/symimp-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — SYMIMP cannot proceed (see BUILD/symimp-driverbuild.log)" >&2
    tail -40 "$BUILD/symimp-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/symimp-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — SYMIMP would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/symimp-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}
# run a fixture; return the process exit code (139 = SIGSEGV); stderr -> $2.
run_fixture() { local py="$1" err="$2"; $NODE "$BUNDLE" "$py" > /dev/null 2>"$err"; echo $?; }

########################################################################
echo ">> [2/2a] GAP1 — the overload-ALIAS fixtures must LOWER + TYPECHECK to nerror=0"
########################################################################
# ---- VALID programs: each must lower the `@overload NAME = TARGET` alias + resolve the use ----
VALID=(
  "si_overload_alias"   # @overload is_nil = stamp_nilq ; use is_nil(x)        (the alias form)
  "si_overload_prec"    # @overload[1000]\nis_nil = stamp_nilq ; use is_nil(x)  (precedence payload)
)
for base in "${VALID[@]}"; do
  py="$TESTDIR/${base}.pdats"
  echo "----------------------------------------------------------------------"
  echo ">> [valid] $py"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; continue; fi
  echo "-- source --"; cat "$py"
  n="$(nerror_of "$py")"
  echo ">> nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" = "0" ]; then
    echo ">> PASS  ($base: the overload-alias re-exports TARGET under NAME; the use resolves, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    echo "-- f3perr0 diagnostics (stock reporter) --" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR" | head -8 >&2
    FAIL=1
  fi
done

########################################################################
echo ">> [2/2b] GAP2 — a MISSING import must NOT crash; it degrades to a CLEAN diagnostic + nerror>0"
########################################################################
echo "----------------------------------------------------------------------"
B3="si_missing_import"
py="$TESTDIR/${B3}.pdats"; err="$BUILD/symimp_${B3}.stderr"
echo ">> [#crash-safety] $py  (from NonexistentModule import * — the target .sats does not exist)"
if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; else
  echo "-- source --"; cat "$py"
  rc="$(run_fixture "$py" "$err")"
  # an UNCAUGHT ENOENT throw is the bug we are fixing — it must NOT appear (and the run must not segv).
  enoent="$(grep -cE "ENOENT|Uncaught|at Object\.openSync" "$err" 2>/dev/null | head -1)"; enoent="${enoent:-0}"
  diags="$(grep -cE "@missing-import" "$err" 2>/dev/null | head -1)"; diags="${diags:-0}"
  nerr="$(grep -oE 'nerror \(after tread3a\) = [0-9]+' "$err" 2>/dev/null | grep -oE '[0-9]+$' | head -1)"
  echo ">> bundle exit code: $rc  (139 = SIGSEGV — a crash)"
  echo ">> ENOENT/uncaught-throw lines: $enoent ;  @missing-import errcks: $diags ;  nerror (after tread3a) = ${nerr:-<none>}"
  if [ "$rc" -eq 139 ]; then
    echo "!! FAIL ($B3 SEGFAULTED — exit 139; the import guard did not catch the missing file)" >&2; FAIL=1
  elif [ "${enoent:-0}" -gt 0 ]; then
    echo "!! FAIL ($B3 threw an uncaught ENOENT — the guard did not fire)" >&2
    grep -E "ENOENT|Uncaught" "$err" | head -4 >&2; FAIL=1
  elif [ -z "${nerr:-}" ]; then
    echo "!! FAIL ($B3 crashed before the type passes finished — no nerror line)" >&2
    tail -8 "$err" >&2; FAIL=1
  elif [ "${nerr}" = "0" ]; then
    echo "!! FAIL ($B3 expected nerror>0 — a missing import must report a diagnostic)" >&2; FAIL=1
  elif [ "${diags:-0}" -lt 1 ]; then
    echo "!! FAIL ($B3 did not emit the @missing-import diagnostic on the import span)" >&2; FAIL=1
  else
    echo ">> PASS  ($B3: no crash (rc=$rc != 139), no ENOENT throw; a clean @missing-import diagnostic + nerror=${nerr} > 0)"
  fi
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> SYMIMP: FAIL (see failures above)"; exit 1; fi
echo ">> SYMIMP: PASS (GAP1: @overload NAME = TARGET [+ @overload[N]] re-exports an existing fn under a"
echo "           new overloaded name, resolving at the use site, nerror=0. GAP2: a missing import is a"
echo "           clean counted diagnostic + survivable no-op — NOT an uncaught ENOENT/crash; quoted"
echo "           string paths are unquoted.)"
exit 0
