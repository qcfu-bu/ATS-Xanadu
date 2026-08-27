#!/bin/bash
# run-bench.sh — micro-benchmarks of EMITTED-CODE performance: the same ATS3
# source compiled by the Go backend (xats2go, self-hosted binary) and by the
# Chez backend (xats2cz, node-hosted seed bundle), then RUN and timed.
#
#   Go side:   the CATS/GO prelude arm (each backend on its own native arm):
#              swap prelude_JS_dats.hats -> prelude_GO_dats.hats in the
#              source, xats2go-selfhost -o b.go, splice the CATS/GO
#              .cats floor into the module ($->_ mangled), go build, run.
#   Chez side: the JS prelude arm (the surface its runtime implements):
#              node cz-bundle b.dats -> body.scm; runtime ++ body -> b.scm;
#              chez compile-file -> b.so; chez --script b.so
#
# Compile/build time is EXCLUDED on both sides (both run precompiled native
# code; Chez compiles .scm -> .so ahead of the timed runs).  Each timed run
# is a whole process (startup included) — b00_null reports the startup floor.
# Correctness: Go stdout must be byte-equal to Chez stdout on every bench.
#
# usage: run-bench.sh [reps]      (default 3; min is reported)
set -u
ulimit -s 65520 2>/dev/null || true
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X NODE_COMPILE_CACHE=$X/srcgen2/xats2go/srcgen2/BUILD/.v8cache
B=$X/srcgen2/xats2go/bench
W=$B/BUILD
REPS="${1:-3}"

GOBIN=$X/srcgen2/xats2go/selfhost-build/src/xats2go-selfhost
GOBUNDLE=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
CZBUNDLE=$X/srcgen2/xats2cz/BUILD/xats2cz-bundle.js
CZRT=$X/srcgen2/xats2cz/runtime/xats2cz_runtime.scm
RUNTIMEGO=$X/srcgen2/xats2go/runtime/xatsgo
# JS backend (xats2js): the RELEASED self-contained compiler (xassets).
# (Formerly the oracle's xats2js-ref.patched.js -- that bundle links
# frozen Aug-11 driver/cc caches whose frontend stamp references drift
# whenever a frontend SATS changes mid-file; the released jsemit00 bundle
# has no cross-cache stamp exposure.)
JSBUNDLE=$X/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js
NS2R=$X/srcgen2/xats2js/srcgen1/xshared/runtime
S2R=$X/srcgen2/xats2js/srcgenx/xshared/runtime

now() { python3 -c 'import time;print(time.monotonic())'; }

# the CATS/GO floor modules (mirror run-goarm.sh; extend as modules are added).
GO_CATS="xtop000 gint000 bool000 char000 gflt000 axrf000 unsfx00 strn000"

build_one() { # build_one <name>
  local m=$1 src=$B/SRC/$1.dats d=$W/$1
  mkdir -p "$d"
  # -- Go side (GO arm) ------------------------------------------------
  if [ ! -x "$d/$m.gobin" ] || [ "$src" -nt "$d/$m.gobin" ] || [ "$GOBUNDLE" -nt "$d/$m.gobin" ]; then
    sed 's/prelude_JS_dats\.hats/prelude_GO_dats.hats/' "$src" > "$d/$m.goarm.dats"
    # emit with the BUNDLE, not the selfhost binary: the bundle is rebuilt from
    # emitter sources on every `iterate.sh quick`, whereas the binary is only
    # refreshed by a full selfcycle — benching the binary silently measures an
    # OLD emitter (it hid a 2.6x datatype-representation win until caught).
    node --stack-size=50000 "$GOBUNDLE" "$d/$m.goarm.dats" 2> "$d/$m.go.err" \
      | awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' > "$d/$m.go"
    [ -s "$d/$m.go" ] || { echo "!! go-emit $m"; return 1; }
    grep -q 'ERROR' "$d/$m.go.err" && { echo "!! go-emit diagnostics for $m:"; grep 'ERROR' "$d/$m.go.err" | head -3; return 1; }
    # splice the CATS/GO floor: auto-detect the std imports it references
    # (Go errors on both a missing and an unused import).
    local catspaths="" c p impline=""
    for c in $GO_CATS; do catspaths="$catspaths $X/prelude/DATS/CATS/GO/$c.cats"; done
    for p in fmt math reflect strconv strings; do
      if grep -qhE "\b$p\." $catspaths 2>/dev/null; then impline="$impline \"$p\";"; fi
    done
    {
      echo 'package main'
      echo "import ($impline )"
      for c in $GO_CATS; do sed 's/\$/_/g' "$X/prelude/DATS/CATS/GO/$c.cats"; done
    } > "$d/zz_floor.go"
    printf 'module bench_%s\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' "$m" "$RUNTIMEGO" > "$d/go.mod"
    ( cd "$d" && gofmt -w . >/dev/null 2>&1; go build -o "$m.gobin" . 2> "$d/$m.build.err" ) \
      || { echo "!! go build $m"; head -5 "$d/$m.build.err"; return 1; }
  fi
  # -- JS side (xats2js; JS-arm source verbatim) -----------------------
  # NOTE the emitted JS has NO tail-call elimination: deep tail loops can
  # only run within the V8 stack; a stack overflow is reported as DNF.
  if [ ! -s "$d/$m.run.js" ] || [ "$src" -nt "$d/$m.run.js" ]; then
    node --stack-size=8801 "$JSBUNDLE" "$src" > "$d/$m.emit.js" 2> "$d/$m.js.err" \
      || { echo "!! js-emit $m"; tail -3 "$d/$m.js.err"; return 1; }
    awk -v n="$m" 'f||$0 ~ ("^// LCSRCsome1.*"n){f=1; print}' "$d/$m.emit.js" > "$d/$m.user.js"
    [ -s "$d/$m.user.js" ] || { echo "!! empty js emission for $m"; return 1; }
    cat "$NS2R/srcgen2_prelude.js" "$NS2R/srcgen2_prelude_node.js" \
        "$NS2R/srcgen2_precats.js" "$NS2R/srcgen2_xatslib.js" \
        "$S2R/xats2js_js1emit.js" "$d/$m.user.js" > "$d/$m.run.js"
  fi
  # -- Chez side -------------------------------------------------------
  if [ ! -s "$d/$m.so" ] || [ "$src" -nt "$d/$m.so" ]; then
    NODE_COMPILE_CACHE= node --stack-size=60000 "$CZBUNDLE" "$src" > "$d/$m.czraw" 2> "$d/$m.cz.err" \
      || { echo "!! cz-emit $m"; tail -3 "$d/$m.cz.err"; return 1; }
    awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$d/$m.czraw" > "$d/$m.body.scm"
    [ -s "$d/$m.body.scm" ] || { echo "!! empty cz emission for $m"; return 1; }
    cat "$CZRT" "$d/$m.body.scm" > "$d/$m.scm"
    ( cd "$d" && echo "(compile-file \"$m.scm\")" | chez -q ) > /dev/null || { echo "!! chez compile $m"; return 1; }
  fi
  return 0
}

time_cmd() { # time_cmd <outfile> <cmd...> -> echoes best seconds
  local out=$1; shift
  local best=999999 t0 t1 dt r
  for r in $(seq "$REPS"); do
    t0=$(now); "$@" > "$out" 2>/dev/null; t1=$(now)
    dt=$(python3 -c "print(f'{$t1-$t0:.3f}')")
    best=$(python3 -c "print(min($best,$dt))")
  done
  echo "$best"
}

# b00_null is the per-backend startup floor; kernel rows report NET time
# (raw minus that floor) and the <backend>/go ratios on the net (>1 = Go
# faster).  A JS run that dies (stack overflow: no TCO in emitted JS) or
# mismatches shows DNF.
gbase=0; cbase=0; jbase=0
echo "bench           go-net(s) chez-net(s) js-net(s) chez/go js/go  output"
fail=0
for src in "$B"/SRC/b*.dats; do
  m=$(basename "$src" .dats); d=$W/$m
  build_one "$m" || { fail=1; continue; }
  gt=$(time_cmd "$d/$m.go.out"  "$d/$m.gobin")
  ct=$(time_cmd "$d/$m.cz.out"  chez --script "$d/$m.so")
  jt=$(time_cmd "$d/$m.js.out"  node --stack-size=60000 "$d/$m.run.js")
  if cmp -s "$d/$m.go.out" "$d/$m.cz.out"; then okq=$(head -c 32 "$d/$m.go.out" | tr -d '\n'); else okq='!! GO/CZ MISMATCH'; fail=1; fi
  jok=1; cmp -s "$d/$m.go.out" "$d/$m.js.out" || jok=0
  if [ "$m" = b00_null ]; then
    gbase=$gt; cbase=$ct; jbase=$jt
    printf '%-15s %8s %10s %9s %7s %5s  %s\n' "$m(startup)" "$gt" "$ct" "$jt" "-" "-" "$okq"
    continue
  fi
  gn=$(python3 -c "print(f'{max($gt-$gbase,0.0):.3f}')")
  cn=$(python3 -c "print(f'{max($ct-$cbase,0.0):.3f}')")
  cratio=$(python3 -c "print(f'{$cn/$gn:.1f}x' if $gn > 0 else '-')")
  if [ "$jok" = 1 ]; then
    jn=$(python3 -c "print(f'{max($jt-$jbase,0.0):.3f}')")
    jratio=$(python3 -c "print(f'{$jn/$gn:.1f}x' if $gn > 0 else '-')")
  else
    jn=DNF; jratio=-
  fi
  printf '%-15s %8s %10s %9s %7s %5s  %s\n' "$m" "$gn" "$cn" "$jn" "$cratio" "$jratio" "$okq"
done
exit $fail
