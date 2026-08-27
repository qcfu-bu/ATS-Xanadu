#!/usr/bin/env bash
# dev.sh — TIERED fast loop for selfhost fixpoint work.
#
# The old loop (rebuild lib2xatsopt -> bundle -> re-emit 194 modules ->
# assemble -> go build -> probe) costs ~12 min and is only needed when the
# BUNDLE's emission behavior changes (emitter/resolver edits).  Most fixpoint
# iterations are cheaper classes; pick the lowest tier that matches the edit:
#
#   dev.sh probe [file.dats]   ~3s   run the EXISTING binary on a probe
#                                        file (default: probe/zzprobe.dats),
#                                        report F3PERR/TREAD error counts.
#   dev.sh runtime             ~10s  runtime/xatsgo edit: go build + probe.
#   dev.sh frontend            ~60s  srcgen2/DATS *.dats edit (frontend
#                                        BEHAVIOR change): the OLD bundle
#                                        re-emits just the stale modules
#                                        (assemble.sh mtime check), rewire,
#                                        go build, probe.  NO bundle rebuild:
#                                        the bundle only needs rebuilding when
#                                        the EMITTED-CODE-SHAPE must change.
#   dev.sh bridges <module>    ~20s  emit ONE module with the CURRENT
#                                        bundle and count semantic runtime
#                                        bridges (Xats_g_eq / Xats_gs_print_n*)
#                                        — the resolver-fix success metric,
#                                        with NO Go build in the loop.
#   dev.sh bundle              ~3m   resolver/emitter edit: incremental
#                                        lib2xatsopt (make, per-module mtimes)
#                                        + xats2go bundle relink.  Pair with
#                                        `bridges` to validate, THEN run
#                                        `full` once when the metric is green.
#   dev.sh full                ~10m  re-emit ALL stale modules (after a
#                                        bundle rebuild everything is stale),
#                                        assemble, build, probe.
#
# ===== LOOPS FOR BACKEND (Go-centric emitter) WORK =====
#   dev.sh quick [bench]       ~1m   INNER LOOP: bundle relink + psuite
#                                        (75 programs emit/build/run/byte-cmp
#                                        vs the JS backend).  No selfhost
#                                        rebuild — an emitter change is judged
#                                        by what it EMITS.  `quick bench` adds
#                                        the perf suite.
#   dev.sh selfcycle           ~55m  NODE-FREE BUILD: the selfhost binary
#                                        bootstraps ITSELF (prewarm-self ->
#                                        assemble -> go build), iterating to a
#                                        `fixpoint`, then census/regress/gate.
#                                        MEASURED: 193 modules at P3 = 3276s.
#   dev.sh full-verify         ~55m  PRE-COMMIT with the JS ORACLE: same,
#                                        but emissions come from the BUNDLE and
#                                        `sweep` proves binary == bundle.
#
# HONEST NUMBERS (measured 2026-08-21, do not repeat the guesses this replaced):
#   per-module emit: selfhost binary 8.7s vs node bundle 9.5s (xsymbol).  The
#   binary is only ~1.1x faster — NOT the ~2x that "native beats node" suggests,
#   because both run the SAME emitted-Go/JS algorithm and both are dominated by
#   allocation.  So `selfcycle` is not a speed win over the bundle path; its
#   value is TOOLCHAIN INDEPENDENCE (no 216MB JS bundle, no jsemit transpile in
#   the build) as the backend moves away from the JS model.
#   A full 194-module build is ~55min of essentially IRREDUCIBLE compute at
#   today's per-module cost.  The levers that actually matter, in order:
#     1. DON'T rebuild what did not change  -> prewarm-dirty / prewarm-self
#        (a frontend edit re-emits 1 module, not 193).
#     2. Make each compile cheaper.  ~3.3s of every compile re-parses the SAME
#        424 prelude/SATS files (~11min per full build); the rest is
#        allocation-heavy template resolution.  Interface caching and the
#        Go-centric backend items (unboxed cons, fewer `any`) attack this — and
#        the compiler IS emitted Go, so backend wins compound here.
#     3. NOT -j: see PARALLELISM below.
#
# TWO KINDS OF FIXPOINT — keep both, know which you are running:
#   sweep     binary emissions vs BUNDLE-produced emit/  => "reproduces the JS
#             reference".  Needs node; run before committing.
#   fixpoint  binary emissions vs the SELF-produced emit/ it was built from
#             => "reproduces itself" (the classic bootstrap).  No node.
# Mechanically identical comparisons; only the PROVENANCE of emit/ differs.
# Never point `sweep` at self-produced emit/ — that silently degrades the JS
# cross-check into a circular self-comparison.
#
# GC: emission runs with GOGC=400 (measured 5% faster at P3: 56s vs 59s per
# 8 modules; the compiler allocates ~2.9GB per module so a laxer GC trades
# memory we have for collector work we do not need).  Override with XGOGC.
#
# PARALLELISM: 3.  The compiler is MEMORY-BANDWIDTH bound (~850MB RSS/process,
# continuous allocation): 8 modules take 81s serial, 59s at P3, 111s at P8 —
# past P3 it is worse than serial.  Real build speedups must come from making
# the compiler ALLOCATE LESS (= the Go-centric backend work), not from -j.
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
  [ -x "$BIN" ] || die "no binary at $BIN (run: dev.sh frontend | full)"
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
  # -l REQUIRED (2026-08-26): with INLINING enabled, compiling the 450k-line
  # single-package assembly produces a >5GB package object (the inliner
  # flattens ~42k nested instantiation closures into giant functions whose
  # liveness/stack-map metadata explodes) -> the go1.26 LINKER panics
  # (goobj uint32 offset overflow; looks like corruption).  `all=-l` keeps
  # every other optimization and yields a 129MB object, 8.5s build.
  # Override via XGCFLAGS (e.g. 'all=-N -l' for fastest builds).
  # PACKAGE SPLIT (2026-08-26, shell-native 2026-08-27): when a fresh
  # assembly exists, route it into multiple Go packages
  # (zzbase/zzfe2/zzfe3/zzcc/zzgo + main) so no package object can
  # approach the 4GB goobj limit; see split-src.sh (pure file routing --
  # crossing symbols are exported at birth by the emitter).  When no
  # emitter_all.go is present (binary-only rebuilds) the existing split
  # packages are reused as-is.
  bash "$OUT/split-src.sh" || die "split-src failed"
  # INLINING ON (2026-08-27): with the instance cache + lifting + dedup the
  # per-package objects are far under the 4GB goobj limit, so the standing
  # `all=-l` workaround is retired.  Measured: build 8.5s -> ~61s, binary
  # 21MB -> 192MB, compile RUNTIME 1.8x faster (trans12 3.23s -> 1.80s --
  # faster than the node bundle).  Override via XGCFLAGS ('all=-l' for the
  # fastest dev loop).
  ( cd "$OUT/src" && go build -gcflags "${XGCFLAGS:-}" -o xats2go-selfhost . ) || die "go build failed"
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
  #     dev.sh frontend trans2a_utils0 trans23_utils0 [probe.dats]
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
  m="${2:-}"; [ -n "$m" ] || die "usage: dev.sh bridges <module> (e.g. trans12_dynexp | xsymmap_stkmap)"
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
  echo ">> validate with: dev.sh bridges <module>; then dev.sh full"
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
  # bundle-side rungs in PARALLEL (P3 -- each holds a 216MB node bundle);
  # each run-goarm has its own goarm_<name> work dir so they don't collide.
  n=0
  for t in "$XGO"/srcgen2/TEST/test_goarm*_xats2go.dats; do
    nm="$(basename "$t" .dats)"
    ( cd "$XGO" && bash run-goarm.sh "srcgen2/TEST/$nm.dats" ) > "$G/$nm.log" 2>&1 &
    n=$((n+1)); [ $((n % 3)) -eq 0 ] && wait
  done
  wait
  for t in "$XGO"/srcgen2/TEST/test_goarm*_xats2go.dats; do
    nm="$(basename "$t" .dats)"
    if ! grep -q "GOARM PASS" "$G/$nm.log"; then echo "!! RUNG FAIL(bundle): $nm (see $G/$nm.log)"; fail=1; continue; fi
    ( cd "$XGO" && "$BIN" "srcgen2/TEST/$nm.dats" ) > "$G/$nm.self.raw" 2> "$G/$nm.self.err"
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
  # invoked identically; path text embeds in location comments).  Results in
  # probe/sweep/: PASS/DIFF/ERR per module.
  #
  # PARALLELISM (measured 2026-08-21, 18 cores / 48GB): the compiler is
  # MEMORY-BANDWIDTH bound, not CPU bound — peak RSS ~850MB per process with
  # near-continuous allocation.  8 identical modules: serial 81s, P2 62s,
  # P3 59s, P4 73s, P8 111s.  Past P3 throughput gets WORSE THAN SERIAL.
  # The old default of 8 made a full sweep ~2x slower than necessary (~60min
  # vs ~30min).  Do not raise this without re-measuring.
  PAR="${2:-3}"
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
    GOGC=${XGOGC:-400} "$BIN" "$f" > "$SW/$m.raw" 2> "$SW/$m.err"; rc=$?
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
prewarm)
  # Parallel re-emit of ALL module references via the bundle (default P=3 —
  # node bundle processes are memory-heavy; P6 has produced silent empty
  # emits on 48GB).  Writes emit/<m>.raw + emit/<m>.go so a following
  # assemble.sh run's mtime check skips re-emitting.  Needed after a bundle
  # rebuild (GOPATCHED newer than every emit/<m>.go) or template-source edits.
  PAR="${2:-3}"
  eval "$(grep '^FRONTEND=' "$OUT/assemble.sh")"
  eval "$(grep '^CCMODS=' "$OUT/assemble.sh")"
  JOBS="$PROBEDIR/prewarm.jobs"; : > "$JOBS"
  for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
    echo "$(basename "$f" .dats) $f" >> "$JOBS"; done
  for m in $FRONTEND; do echo "$m $X/srcgen2/DATS/$m.dats" >> "$JOBS"; done
  for m in $CCMODS; do echo "$m $X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats" >> "$JOBS"; done
  emit_one() {
    m="$1"; f="$2"
    node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
    [ -s "$EMIT/$m.go" ] || echo "!! EMPTY EMIT: $m" >&2
  }
  n=0
  while read -r m f; do
    emit_one "$m" "$f" &
    n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait
  done < "$JOBS"
  wait
  empty=$(for g in "$EMIT"/*.go; do [ -s "$g" ] || basename "$g"; done | wc -l | tr -d ' ')
  echo ">> PREWARM: $n modules re-emitted (P=$PAR); empty emissions: $empty"
  [ "$empty" = 0 ] || exit 1
  ;;
prewarm-touching)
  # TARGETED re-emit: `dev.sh prewarm-touching <regex> [P]`
  #
  # WHY: mtime invalidation is CONTENT-BLIND.  Relinking the bundle (any
  # emitter OR frontend edit) makes all 194 emissions "stale", so we re-emit
  # 194 modules — but a typical emitter fix changes only a few.  Measured
  # blast radius of real changes from this campaign (modules whose emission
  # even CONTAINS the affected construct):
  #     TCO byref rebind (goxtco)        2/194   1.0%
  #     jshmap leaf typing               5/194   2.6%
  #     float64 coercer (Xats_as_dflt)  12/194   6.2%
  #     return func-adapter (func(zza0) 14/194   7.2%
  #     addr-of-field (&Xats_as_con)    53/194  27.3%
  # So the usual over-invalidation is 4x-100x.
  #
  # Give a regex matching the construct your emitter change affects; only
  # modules whose CURRENT emission contains it (plus any module whose own
  # source changed) are re-emitted.  This is a HEURISTIC fast path: it is
  # backstopped by `fixpoint`/`sweep`, which re-emit everything and byte-
  # compare, so a missed module turns the pre-commit verify red rather than
  # silently shipping.  When in doubt, use plain prewarm-self.
  RE="${2:-}"; [ -n "$RE" ] || die "usage: dev.sh prewarm-touching <regex> [P]"
  PAR="${3:-3}"
  [ -x "$BIN" ] || die "no selfhost binary"
  eval "$(grep '^FRONTEND=' "$OUT/assemble.sh")"
  eval "$(grep '^CCMODS=' "$OUT/assemble.sh")"
  JOBS="$PROBEDIR/prewarm.jobs"; : > "$JOBS"
  for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
    echo "$(basename "$f" .dats) $f" >> "$JOBS"; done
  for m in $FRONTEND; do echo "$m $X/srcgen2/DATS/$m.dats" >> "$JOBS"; done
  for m in $CCMODS; do echo "$m $X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats" >> "$JOBS"; done
  n=0; skipped=0
  while read -r m f; do
    g="$EMIT/$m.go"
    hit=0
    [ -s "$g" ] || hit=1                              # never emitted
    [ "$f" -nt "$g" ] && hit=1                        # its own source changed
    if [ "$hit" = 0 ] && grep -qE -- "$RE" "$g" 2>/dev/null; then hit=1; fi
    if [ "$hit" = 0 ]; then skipped=$((skipped+1)); continue; fi
    ( GOGC=${XGOGC:-400} "$BIN" -o "$g" "$f" > /dev/null 2>"$EMIT/$m.err"
      [ -s "$g" ] || echo "!! EMPTY EMIT: $m" >&2 ) &
    n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait
  done < "$JOBS"
  wait
  echo ">> PREWARM-TOUCHING /$RE/: $n re-emitted, $skipped skipped (P=$PAR)"
  echo ">> heuristic path — fixpoint/sweep still verify all 194 before commit"
  ;;
prewarm-self)
  # BINARY-HOSTED prewarm: the SELFHOST BINARY re-emits the modules (dirty-
  # aware), replacing the node bundle in the build hot path.
  #   node bundle: ~20s/module, P3 (each process holds a 216MB JS heap) ~21min
  #   selfhost bin: ~8s/module, P12 (native, ~10x less memory)          ~2min
  # Safe to bootstrap from TODAY because the sweep is green: the binary's
  # emissions are byte-identical to the bundle's for all 193 modules.  The
  # ongoing proof shifts to `fixpoint` (gen-N vs gen-N+1, node-free); `sweep`
  # remains as the periodic JS-oracle cross-check.
  PAR="${2:-3}"   # memory-bandwidth bound; see the sweep tier
  [ -x "$BIN" ] || die "no selfhost binary yet — bootstrap once with: dev.sh prewarm"
  eval "$(grep '^FRONTEND=' "$OUT/assemble.sh")"
  eval "$(grep '^CCMODS=' "$OUT/assemble.sh")"
  JOBS="$PROBEDIR/prewarm.jobs"; : > "$JOBS"
  # an EMITTER-source change invalidates every emission; a frontend-source
  # change invalidates only its own module.  [BIN] itself is the emitter here,
  # so its mtime is the invalidation stamp.
  for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
    echo "$(basename "$f" .dats) $f" >> "$JOBS"; done
  for m in $FRONTEND; do echo "$m $X/srcgen2/DATS/$m.dats" >> "$JOBS"; done
  for m in $CCMODS; do echo "$m $X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats" >> "$JOBS"; done
  emit_self() {
    m="$1"; f="$2"
    GOGC=${XGOGC:-400} "$BIN" -o "$EMIT/$m.go" "$f" > /dev/null 2>"$EMIT/$m.err"
    [ -s "$EMIT/$m.go" ] || echo "!! EMPTY EMIT: $m" >&2
  }
  n=0; skipped=0
  while read -r m f; do
    g="$EMIT/$m.go"
    if [ -s "$g" ] && [ ! "$f" -nt "$g" ] && [ ! "$BIN" -nt "$g" ]; then
      skipped=$((skipped+1)); continue
    fi
    emit_self "$m" "$f" &
    n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait
  done < "$JOBS"
  wait
  empty=$(for g in "$EMIT"/*.go; do [ -s "$g" ] || basename "$g"; done | wc -l | tr -d ' ')
  echo ">> PREWARM-SELF: $n re-emitted, $skipped kept (P=$PAR); empty emissions: $empty"
  [ "$empty" = 0 ] || exit 1
  ;;
fixpoint)
  # NODE-FREE SELF-HOSTING PROOF.  Compares what the binary EMITS against the
  # emissions the binary was BUILT FROM (emit/): equal => rebuilding would
  # yield the identical binary, i.e. a true fixpoint.  (Mechanically the same
  # comparison as `sweep`; the difference is the PROVENANCE of emit/ — from
  # the JS bundle it proves "reproduces the JS reference", self-produced it
  # proves "reproduces itself".)
  # PRECONDITION: emit/ is what $BIN was built from — run after a
  # prewarm-self + assemble + build (that is what `selfcycle` does).
  # NOTE an EMITTER change needs TWO bootstrap rounds to converge: round 1
  # emits the new emitter SOURCE using the OLD emitter LOGIC, so the binary
  # built from it emits differently; `selfcycle` iterates until stable.
  PAR="${2:-3}"   # memory-bandwidth bound; see the sweep tier
  [ -x "$BIN" ] || die "no selfhost binary"
  G2="$PROBEDIR/gen2"; rm -rf "$G2"; mkdir -p "$G2"
  eval "$(grep '^FRONTEND=' "$OUT/assemble.sh")"
  eval "$(grep '^CCMODS=' "$OUT/assemble.sh")"
  : > "$G2/joblist"
  for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
    echo "$(basename "$f" .dats) $f" >> "$G2/joblist"; done
  for m in $FRONTEND; do echo "$m $X/srcgen2/DATS/$m.dats" >> "$G2/joblist"; done
  for m in $CCMODS; do echo "$m $X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats" >> "$G2/joblist"; done
  gen2_one() {
    m="$1"; f="$2"
    GOGC=${XGOGC:-400} "$BIN" -o "$G2/$m.go" "$f" > /dev/null 2>"$G2/$m.err"
    if [ ! -s "$G2/$m.go" ]; then echo "ERR $m (empty)" > "$G2/$m.verdict"
    elif cmp -s "$G2/$m.go" "$EMIT/$m.go"; then echo "PASS $m" > "$G2/$m.verdict"
    else echo "DIFF $m" > "$G2/$m.verdict"; fi
  }
  n=0
  while read -r m f; do
    gen2_one "$m" "$f" &
    n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait
  done < "$G2/joblist"
  wait
  cat "$G2"/*.verdict | sort > "$G2/RESULTS"
  p=$(grep -c '^PASS' "$G2/RESULTS"); d=$(grep -c '^DIFF' "$G2/RESULTS"); e=$(grep -c '^ERR' "$G2/RESULTS")
  echo ">> FIXPOINT: $p PASS / $d DIFF / $e ERR of $((p+d+e))"
  grep -v '^PASS' "$G2/RESULTS" | head -10 || true
  [ "$d" = 0 ] && [ "$e" = 0 ] || exit 1
  ;;
selfcycle)
  # THE NODE-FREE BUILD: bootstrap the selfhost binary with ITSELF, iterating
  # until the emissions stop changing (fixpoint), then run the test tiers.
  # No node, no 216MB bundle, no JS transpile anywhere in this path.
  #   round: prewarm-self (P12) -> assemble -> wire -> go build -> fixpoint?
  # An emitter change converges in 2 rounds (round 1 emits the new emitter
  # source with the old emitter logic; round 2 re-emits with the new logic).
  PAR="${2:-3}"   # memory-bandwidth bound; see the sweep tier
  t0=$(date +%s)
  for round in 1 2 3; do
    echo ">> --- selfcycle round $round ---"
    "$0" prewarm-self "$PAR" 2>&1 | tail -1
    bash "$OUT/assemble.sh" 2>&1 | tail -1 || die "assemble failed"
    bash "$OUT/wire-driver.sh" >/dev/null 2>&1 || die "wire-driver failed"
    do_build
    echo ">> BUILD OK ($(( $(date +%s) - t0 ))s elapsed)"
    if "$0" fixpoint "$PAR" 2>&1 | tail -2 | grep -q 'FIXPOINT: .* 0 DIFF / 0 ERR'; then
      echo ">> FIXPOINT REACHED in round $round"
      break
    fi
    [ "$round" = 3 ] && die "no fixpoint after 3 rounds — emitter is not converging"
    # not converged: the new binary emits differently, so force a full re-emit
    # with it (touch the binary's stamp by re-running prewarm-self, which sees
    # $BIN newer than every emission).
  done
  "$0" census 2>&1 | tail -1
  "$0" regress 2>&1 | tail -1
  "$0" gate 2>&1 | tail -2
  echo ">> SELFCYCLE: $(( $(date +%s) - t0 ))s total"
  ;;
quick)
  # THE INNER LOOP for BACKEND (emitter) work — ~1 minute, no selfhost rebuild.
  #   bundle relink (~3s: only the edited emitter module re-transpiles)
  # + psuite (75 programs: emit -> go build -> run -> byte-compare vs the JS
  #   backend, -j8, ~50s)
  # + optional bench (`dev.sh quick bench`) for perf-sensitive changes.
  #
  # WHY this is the right loop: an emitter change is validated by what it
  # EMITS, and psuite is 75 real programs checked byte-for-byte against the
  # JS reference.  Re-emitting the 193 compiler modules and rebuilding the
  # selfhost binary proves something DIFFERENT — that the compiler still
  # reproduces itself (the fixpoint) — which is a PRE-COMMIT concern, not a
  # per-edit one.  Run `dev.sh full-verify` before committing.
  t0=$(date +%s)
  ( cd "$X/srcgen2" && make -f Makefile_xjsemit lib2xatsopt ) >/dev/null 2>&1 || die "lib rebuild failed"
  ( cd "$X/srcgen2/xats2go" && make bundle ) >/dev/null 2>&1 || die "bundle relink failed"
  echo ">> bundle: $(( $(date +%s) - t0 ))s"
  ( cd "$X/srcgen2/xats2go" && make -j8 psuite ) 2>&1 | tail -3
  if [ "${2:-}" = bench ]; then bash "$X/srcgen2/xats2go/bench/run-bench.sh" 3; fi
  echo ">> QUICK: $(( $(date +%s) - t0 ))s total"
  ;;
full-verify)
  # PRE-COMMIT: the self-hosting fixpoint + everything else.  Uses
  # prewarm-dirty (safe: the sweep byte-checks every kept emission) and the
  # BUNDLE as the emission reference, so the sweep stays a real
  # binary-vs-bundle fixpoint proof rather than a circular self-comparison.
  "$0" bundle >/dev/null 2>&1 || die "bundle failed"
  "$0" prewarm-dirty 3 2>&1 | tail -1
  bash "$OUT/assemble.sh" 2>&1 | tail -1 || die "assemble failed"
  bash "$OUT/wire-driver.sh" >/dev/null 2>&1 || die "wire-driver failed"
  do_build
  echo ">> BUILD OK"
  "$0" census 2>&1 | tail -1
  "$0" regress 2>&1 | tail -1
  "$0" sweep 3 2>&1 | tail -1
  "$0" gate 2>&1 | tail -2
  ;;
prewarm-dirty)
  # DIRTY-ONLY prewarm: re-emit module m ONLY when (a) its own SOURCE is
  # newer than its emission, or (b) the EMITTER changed (any emitter-module
  # JS in the bundle's BUILD/JS is newer than the emission — an emitter edit
  # invalidates every module).  A FRONTEND-only edit therefore re-emits just
  # the edited modules (seconds, not ~45 min).  SAFETY: the sweep's 193-module
  # binary-vs-bundle byte-comparison independently verifies every emission
  # this tier chose to keep — a wrong "unchanged" call turns the sweep red.
  PAR="${2:-3}"
  eval "$(grep '^FRONTEND=' "$OUT/assemble.sh")"
  eval "$(grep '^CCMODS=' "$OUT/assemble.sh")"
  JOBS="$PROBEDIR/prewarm.jobs"; : > "$JOBS"
  EMJS_NEWEST=$(ls -t "$X"/srcgen2/xats2go/srcgen2/BUILD/JS/*_dats_out0.js 2>/dev/null | head -1)
  for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
    echo "$(basename "$f" .dats) $f" >> "$JOBS"; done
  for m in $FRONTEND; do echo "$m $X/srcgen2/DATS/$m.dats" >> "$JOBS"; done
  for m in $CCMODS; do echo "$m $X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats" >> "$JOBS"; done
  emit_one() {
    m="$1"; f="$2"
    node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
    [ -s "$EMIT/$m.go" ] || echo "!! EMPTY EMIT: $m" >&2
  }
  n=0; skipped=0
  while read -r m f; do
    g="$EMIT/$m.go"
    if [ -s "$g" ] && [ ! "$f" -nt "$g" ] && { [ -z "$EMJS_NEWEST" ] || [ ! "$EMJS_NEWEST" -nt "$g" ]; }; then
      skipped=$((skipped+1)); continue
    fi
    emit_one "$m" "$f" &
    n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait
  done < "$JOBS"
  wait
  empty=$(for g in "$EMIT"/*.go; do [ -s "$g" ] || basename "$g"; done | wc -l | tr -d ' ')
  echo ">> PREWARM-DIRTY: $n re-emitted, $skipped kept (P=$PAR); empty emissions: $empty"
  [ "$empty" = 0 ] || exit 1
  ;;
census)
  # Equality-bridge census over the emitted modules: every xatsgo.Xats_g_eq /
  # Xats_g_neq call is a frontend `=`/`!=` the resolver bridged to POINTER
  # identity — a stamp-vs-pointer hazard (see docs/02).  The ratchet file
  # tests/bridge-census.max pins the allowed count; the campaign drives it to
  # 0 and any NEW bridge fails the check.  Reports per-module counts + the
  # source sites (nearest location comment).
  MAX=$(cat "$OUT/tests/bridge-census.max" 2>/dev/null || echo 999)
  total=0
  for f in "$EMIT"/*.go; do
    n=$(grep -c "xatsgo\.Xats_g_eq\|xatsgo\.Xats_g_neq" "$f"); total=$((total+n))
    [ "$n" -gt 0 ] && echo "  $n $(basename "$f" .go)"
  done
  echo ">> CENSUS: $total equality bridges (ratchet max: $MAX)"
  if [ "$total" -gt "$MAX" ]; then echo "!! CENSUS RED: $total > $MAX"; exit 1; fi
  echo ">> CENSUS GREEN"
  ;;
regress)
  # DIFFERENTIAL REGRESSION SUITE — pins the closed gaps:
  #  * tests/ok*.dats  : must compile CLEAN on BOTH sides (F3PERR=0) with
  #                      BYTE-EQUAL emitted Go (pins checking-layer fidelity,
  #                      e.g. the unifier stamp-equality fix).
  #  * tests/err*.dats : must error IDENTICALLY on both sides — equal F3PERR
  #                      counts AND byte-equal stdout+stderr after path
  #                      normalization (pins the diagnostic-printer fidelity).
  #  * census ratchet  : no NEW pointer-identity equality bridges.
  # Probes are compiled from srcgen2/DATS (staload-relative paths), copied in.
  R="$PROBEDIR/regress"; rm -rf "$R"; mkdir -p "$R"
  rfail=0
  for t in "$OUT"/tests/ok*.dats "$OUT"/tests/err*.dats; do
    [ -f "$t" ] || continue
    nm="$(basename "$t" .dats)"
    cp "$t" "$X/srcgen2/DATS/zz_$nm.dats"
    rel="srcgen2/DATS/zz_$nm.dats"
    ( cd "$X" && "$BIN" "$rel" ) > "$R/$nm.go.out" 2> "$R/$nm.go.err"
    ( cd "$X" && node --stack-size=$NODESTK "$GOPATCHED" "$rel" ) > "$R/$nm.js.out" 2> "$R/$nm.js.err"
    rm -f "$X/srcgen2/DATS/zz_$nm.dats"
    gof=$(cat "$R/$nm.go.out" "$R/$nm.go.err" | grep -c 'F3PERR0-ERROR')
    jsf=$(cat "$R/$nm.js.out" "$R/$nm.js.err" | grep -c 'F3PERR0-ERROR')
    for s in out err; do
      sed "s|$X/||g" "$R/$nm.go.$s" > "$R/$nm.go.$s.n"
      sed "s|$X/||g" "$R/$nm.js.$s" > "$R/$nm.js.$s.n"
    done
    case "$nm" in
    ok*)
      if [ "$gof" = 0 ] && [ "$jsf" = 0 ] && cmp -s "$R/$nm.go.out.n" "$R/$nm.js.out.n"; then
        echo ">> REGRESS OK: $nm (clean both sides, byte-equal emission)"
      else echo "!! REGRESS FAIL: $nm (goF3PERR=$gof jsF3PERR=$jsf; diff $R/$nm.go.out.n $R/$nm.js.out.n)"; rfail=1; fi
      ;;
    err*)
      if [ "$gof" = "$jsf" ] && [ "$gof" -gt 0 ] \
         && cmp -s "$R/$nm.go.out.n" "$R/$nm.js.out.n" \
         && cmp -s "$R/$nm.go.err.n" "$R/$nm.js.err.n"; then
        echo ">> REGRESS OK: $nm (F3PERR=$gof both sides, identical diagnostics)"
      else echo "!! REGRESS FAIL: $nm (goF3PERR=$gof jsF3PERR=$jsf; diff $R/$nm.go.out.n $R/$nm.js.out.n; diff $R/$nm.go.err.n $R/$nm.js.err.n)"; rfail=1; fi
      ;;
    esac
  done
  "$0" census | tail -2 | grep -q "CENSUS GREEN" && echo ">> REGRESS census: GREEN" || { echo "!! REGRESS census: RED"; rfail=1; }
  [ "$rfail" = 0 ] && echo ">> REGRESS GREEN" || { echo "!! REGRESS RED"; exit 1; }
  ;;
sites)
  # Map every bridged equality call to its SOURCE declaration via the
  # location comments — the work-list for the closure campaign.
  for f in "$EMIT"/*.go; do
    awk -v M=$(basename "$f" .go) '/LCSRCsome1/{loc=$0}
      /xatsgo\.Xats_g_eq|xatsgo\.Xats_g_neq/{
        match(loc, /[A-Za-z0-9_\/.-]*\.(dats|sats|hats)\)@\([0-9]*\(line=[0-9]*/);
        print M"|"substr(loc,RSTART,RLENGTH)}' "$f"
  done | sed 's|/Users/[A-Za-z0-9_/.-]*/ATS-Xanadu/||;s/)@(/@/;s/(line=/:L/' | sort | uniq -c | sort -k2
  ;;
*)
  sed -n '2,40p' "$0"; exit 2
  ;;
esac
