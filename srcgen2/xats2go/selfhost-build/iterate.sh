#!/usr/bin/env bash
# iterate.sh — TIERED fast loop for selfhost fixpoint work.
#
# The old loop (rebuild lib2xatsopt -> bundle -> re-emit 194 modules ->
# assemble -> go build -> probe) costs ~12 min and is only needed when the
# BUNDLE's emission behavior changes (emitter/resolver edits).  Most fixpoint
# iterations are cheaper classes; pick the lowest tier that matches the edit:
#
#   iterate.sh probe [file.dats]   ~3s   run the EXISTING binary on a probe
#                                        file (default: probe/zzprobe.dats),
#                                        report F3PERR/TREAD error counts.
#   iterate.sh runtime             ~10s  runtime/xatsgo edit: go build + probe.
#   iterate.sh frontend            ~60s  srcgen2/DATS *.dats edit (frontend
#                                        BEHAVIOR change): the OLD bundle
#                                        re-emits just the stale modules
#                                        (assemble.sh mtime check), rewire,
#                                        go build, probe.  NO bundle rebuild:
#                                        the bundle only needs rebuilding when
#                                        the EMITTED-CODE-SHAPE must change.
#   iterate.sh bridges <module>    ~20s  emit ONE module with the CURRENT
#                                        bundle and count semantic runtime
#                                        bridges (Xats_g_eq / Xats_gs_print_n*)
#                                        — the resolver-fix success metric,
#                                        with NO Go build in the loop.
#   iterate.sh bundle              ~3m   resolver/emitter edit: incremental
#                                        lib2xatsopt (make, per-module mtimes)
#                                        + xats2go bundle relink.  Pair with
#                                        `bridges` to validate, THEN run
#                                        `full` once when the metric is green.
#   iterate.sh full                ~10m  re-emit ALL stale modules (after a
#                                        bundle rebuild everything is stale),
#                                        assemble, build, probe.
#
# Pre-commit gate stays unchanged and is NOT this script's job:
#   run-goarm.sh rungs (12/12 byte-equal) + make -j8 psuite (75/75).
#
# CAUTION (mangling): .dats-only edits keep cross-module names stable (they
# come from the .sats).  After ANY .sats edit, do a CLEAN lib2xatsopt rebuild
# (see memory: stale JS cache -> silently broken compiler) and a `full` pass.
set -uo pipefail
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME="$X"
ulimit -s 65520 2>/dev/null || true
NODESTK="${NODESTK:-50000}"
OUT="$X/srcgen2/xats2go/selfhost-build"
EMIT="$OUT/emit"
GOPATCHED="$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js"
export NODE_COMPILE_CACHE="$X/srcgen2/xats2go/srcgen2/BUILD/.v8cache"
BIN="$OUT/src/xats2go-selfhost"
PROBEDIR="$OUT/probe"; mkdir -p "$PROBEDIR"

die() { echo "!! $*" >&2; exit 1; }

# default probe: the vt-signature template impl (gseq000's gseq_istrmize,
# VERBATIM including the strm_vt_istrmize0 wrapper) — the minimal decl that
# errored in the selfhost binary while checking CLEAN under the JS bundle.
# NB the earlier zzprobe9 variant DROPPED the wrapper and was ill-typed on
# BOTH sides — always validate a repro differentially before trusting it.
default_probe() {
  local p="$X/srcgen2/DATS/zzprobe10.dats"
  if [ ! -f "$p" ]; then
    cat > "$p" <<'EOF'
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
#include
"./../HATS/xatsopt_sats.hats"
//
#impltmp
<xs><x0>
gseq_istrmize
  ( xs ) =
(
  strm_vt_istrmize0
  (gseq_strmize<xs><x0>(xs)) )
//
EOF
  fi
  echo "$p"
}

do_probe() {
  local src="${1:-$(default_probe)}"
  [ -x "$BIN" ] || die "no binary at $BIN (run: iterate.sh frontend | full)"
  local o="$PROBEDIR/probe.out" e="$PROBEDIR/probe.err"
  ( cd "$X" && "$BIN" "${src#$X/}" > "$o" 2> "$e" ); local rc=$?
  local f3 t12 t23
  f3=$(grep -c 'F3PERR0-ERROR' "$o" "$e" | awk -F: '{s+=$NF} END{print s}')
  t12=$(grep -c 'TREAD12-ERROR' "$o" "$e" | awk -F: '{s+=$NF} END{print s}')
  t23=$(grep -c 'TREAD23-ERROR' "$o" "$e" | awk -F: '{s+=$NF} END{print s}')
  echo ">> probe ${src#$X/}: exit=$rc F3PERR=$f3 TREAD12=$t12 TREAD23=$t23  (out: $o)"
  grep -m4 -E 'F3PERR0-ERROR|TREAD12-ERROR|TREAD23-ERROR' "$o" "$e" | head -8
  [ "$f3" = 0 ] && [ "$rc" = 0 ]
}

do_build() {
  ( cd "$OUT/src" && go build -o xats2go-selfhost . ) || die "go build failed"
  echo ">> built $BIN"
}

case "${1:-}" in
probe)
  do_probe "${2:-}"
  ;;
runtime)
  do_build
  do_probe "${2:-}"
  ;;
frontend)
  # assemble.sh re-emits ONLY modules whose .dats is newer than emit/<m>.go
  # (or than the bundle) and always re-concats; wire-driver restores main.
  #
  # TEMPLATE-DEPENDENCY TRAP: editing a TEMPLATE BODY (e.g. statyp2_tmplib's
  # unify00_s2typ) changes the INSTANTIATIONS embedded in every USING module,
  # whose own .dats mtimes are unchanged — mtime tracking misses them.  Name
  # those modules as extra args to force their re-emit:
  #     iterate.sh frontend trans2a_utils0 trans23_utils0 [probe.dats]
  # Find the dependent set with:  grep -l <template_name> emit/*.go
  shift
  probearg=""
  for a in "$@"; do
    if [ -f "$EMIT/$a.go" ]; then rm -f "$EMIT/$a.go"; echo ">> forced re-emit: $a"
    else probearg="$a"; fi
  done
  bash "$OUT/assemble.sh" || die "assemble failed"
  bash "$OUT/wire-driver.sh" || die "wire-driver failed"
  do_build
  do_probe "$probearg"
  ;;
bridges)
  m="${2:-}"; [ -n "$m" ] || die "usage: iterate.sh bridges <module> (e.g. trans12_dynexp | xsymmap_stkmap)"
  f="$X/srcgen2/DATS/$m.dats"; [ -f "$f" ] || die "no such module: $f"
  raw="$PROBEDIR/$m.bridges.raw"
  node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$raw" 2> "$raw.err" || die "emit failed (see $raw.err)"
  geq=$(grep -c 'Xats_g_eq' "$raw"); gsp=$(grep -c 'Xats_gs_print_n' "$raw")
  f3=$(grep -c 'F3PERR0-ERROR' "$raw" "$raw.err" | awk -F: '{s+=$NF} END{print s}')
  echo ">> $m: Xats_g_eq=$geq Xats_gs_print_nN=$gsp F3PERR=$f3  (raw: $raw)"
  ;;
bundle)
  # incremental frontend lib rebuild (per-module mtimes) + bundle relink.
  ( cd "$X/srcgen2" && make -f Makefile_xjsemit lib2xatsopt ) || die "lib2xatsopt rebuild failed"
  ( cd "$X/srcgen2/xats2go" && make bundle ) || die "bundle relink failed"
  echo ">> bundle rebuilt: $GOPATCHED"
  echo ">> validate with: iterate.sh bridges <module>; then iterate.sh full"
  ;;
full)
  bash "$OUT/assemble.sh" || die "assemble failed"
  bash "$OUT/wire-driver.sh" || die "wire-driver failed"
  do_build
  do_probe "${2:-}"
  ;;
gate)
  # PRE-COMMIT gate: 12 go-arm rungs through run-goarm.sh (bundle-side golden
  # check) + the SELFHOST BINARY re-emitting each rung byte-equal to the
  # bundle's emission + make -j8 psuite.  Traps encoded here: capture FULL
  # output then grep (never tail -1: GOARM PASS prints before program
  # stdout; pipefail+grep -q SIGPIPEs the runner), and invoke the binary
  # with the SAME relative path run-goarm.sh uses (path text is embedded
  # in location comments).
  XGO="$X/srcgen2/xats2go"
  G="$PROBEDIR/gate"; mkdir -p "$G"
  fail=0
  for t in "$XGO"/srcgen2/TEST/test_goarm*_xats2go.dats; do
    nm="$(basename "$t" .dats)"
    ( cd "$XGO" && bash run-goarm.sh "srcgen2/TEST/$nm.dats" ) > "$G/$nm.log" 2>&1
    if ! grep -q "GOARM PASS" "$G/$nm.log"; then echo "!! RUNG FAIL(bundle): $nm (see $G/$nm.log)"; fail=1; continue; fi
    ( cd "$XGO" && "$BIN" "srcgen2/TEST/$nm.dats" --go-arm ) > "$G/$nm.self.raw" 2> "$G/$nm.self.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$G/$nm.self.raw" > "$G/$nm.self.go"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$XGO/srcgen2/BUILD/goarm_$nm/raw.txt" > "$G/$nm.ref.go"
    if cmp -s "$G/$nm.self.go" "$G/$nm.ref.go"; then echo ">> RUNG OK: $nm (bundle golden + binary byte-equal)"
    else echo "!! RUNG FAIL(binary-diff): $nm (diff $G/$nm.self.go $G/$nm.ref.go)"; fail=1; fi
  done
  ( cd "$XGO" && make -j8 psuite ) > "$G/psuite.log" 2>&1
  if grep -q "ALL GREEN" "$G/psuite.log"; then echo ">> PSUITE OK: $(grep 'SUMMARY:' "$G/psuite.log" | tail -1)"
  else echo "!! PSUITE FAIL (see $G/psuite.log)"; tail -5 "$G/psuite.log"; fail=1; fi
  [ "$fail" = 0 ] && echo ">> GATE GREEN" || { echo "!! GATE RED"; exit 1; }
  ;;
sweep)
  # FIXPOINT METRIC: run the SELFHOST BINARY over every assemble.sh module and
  # byte-compare its emission against emit/<m>.go (the bundle's reference,
  # which assemble.sh produced with ABSOLUTE source paths — the binary must be
  # invoked identically; path text embeds in location comments).  Parallel:
  # sweep [P] (default 8).  Results in probe/sweep/: PASS/DIFF/ERR per module.
  PAR="${2:-8}"
  SW="$PROBEDIR/sweep"; rm -rf "$SW"; mkdir -p "$SW"
  eval "$(grep '^FRONTEND=' "$OUT/assemble.sh")"
  eval "$(grep '^CCMODS=' "$OUT/assemble.sh")"
  : > "$SW/joblist"
  for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
    echo "$(basename "$f" .dats) $f" >> "$SW/joblist"; done
  for m in $FRONTEND; do
    echo "$m $X/srcgen2/DATS/$m.dats" >> "$SW/joblist"; done
  for m in $CCMODS; do
    echo "$m $X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats" >> "$SW/joblist"; done
  sweep_one() {
    m="$1"; f="$2"
    "$BIN" "$f" > "$SW/$m.raw" 2> "$SW/$m.err"; rc=$?
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$SW/$m.raw" > "$SW/$m.go"
    if [ $rc -ne 0 ]; then echo "ERR $m (exit $rc)" > "$SW/$m.verdict"
    elif cmp -s "$SW/$m.go" "$EMIT/$m.go"; then echo "PASS $m" > "$SW/$m.verdict"
    else echo "DIFF $m ($(wc -l < "$SW/$m.go") vs $(wc -l < "$EMIT/$m.go") lines)" > "$SW/$m.verdict"; fi
  }
  export -f sweep_one 2>/dev/null || true
  export BIN SW EMIT
  # portable parallel driver (zsh/bash without GNU parallel): background jobs
  n=0
  while read -r m f; do
    sweep_one "$m" "$f" &
    n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait
  done < "$SW/joblist"
  wait
  cat "$SW"/*.verdict | sort > "$SW/RESULTS"
  p=$(grep -c '^PASS' "$SW/RESULTS"); d=$(grep -c '^DIFF' "$SW/RESULTS"); e=$(grep -c '^ERR' "$SW/RESULTS")
  echo ">> SWEEP: $p PASS / $d DIFF / $e ERR of $((p+d+e))  (details: $SW/RESULTS)"
  grep -v '^PASS' "$SW/RESULTS" | head -20 || true
  ;;
*)
  sed -n '2,40p' "$0"; exit 2
  ;;
esac
