#!/bin/bash
# run-bench.sh — micro-benchmarks of EMITTED-CODE performance: the same ATS3
# source compiled by the Go backend (xats2go, self-hosted binary) and by the
# Chez backend (xats2cz, node-hosted seed bundle), then RUN and timed.
#
#   Go side:   the CATS/GO prelude arm (each backend on its own native arm):
#              swap prelude_JS_dats.hats -> prelude_GO_dats.hats in the
#              source, xats2go-selfhost --go-arm -o b.go, splice the CATS/GO
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
CZBUNDLE=$X/srcgen2/xats2cz/BUILD/xats2cz-bundle.js
CZRT=$X/srcgen2/xats2cz/runtime/xats2cz_runtime.scm
RUNTIMEGO=$X/srcgen2/xats2go/runtime/xatsgo

now() { python3 -c 'import time;print(time.monotonic())'; }

# the CATS/GO floor modules (mirror run-goarm.sh; extend as modules are added).
GO_CATS="xtop000 gint000 bool000 char000 gflt000 axrf000 unsfx00 strn000"

build_one() { # build_one <name>
  local m=$1 src=$B/SRC/$1.dats d=$W/$1
  mkdir -p "$d"
  # -- Go side (GO arm) ------------------------------------------------
  if [ ! -x "$d/$m.gobin" ] || [ "$src" -nt "$d/$m.gobin" ] || [ "$GOBIN" -nt "$d/$m.gobin" ]; then
    sed 's/prelude_JS_dats\.hats/prelude_GO_dats.hats/' "$src" > "$d/$m.goarm.dats"
    "$GOBIN" -o "$d/$m.go" "$d/$m.goarm.dats" --go-arm > /dev/null 2> "$d/$m.go.err" || { echo "!! go-emit $m"; return 1; }
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
# (raw minus that floor) and the chez/go ratio on the net (>1 = Go faster).
gbase=0; cbase=0
echo "bench           go-net(s) chez-net(s) chez/go  output"
fail=0
for src in "$B"/SRC/b*.dats; do
  m=$(basename "$src" .dats); d=$W/$m
  build_one "$m" || { fail=1; continue; }
  gt=$(time_cmd "$d/$m.go.out"  "$d/$m.gobin")
  ct=$(time_cmd "$d/$m.cz.out"  chez --script "$d/$m.so")
  if cmp -s "$d/$m.go.out" "$d/$m.cz.out"; then okq=$(head -c 40 "$d/$m.go.out" | tr -d '\n'); else okq='!! OUTPUT MISMATCH'; fail=1; fi
  if [ "$m" = b00_null ]; then
    gbase=$gt; cbase=$ct
    printf '%-15s %8s %10s %8s  %s\n' "$m(startup)" "$gt" "$ct" "-" "$okq"
    continue
  fi
  gn=$(python3 -c "print(f'{max($gt-$gbase,0.0):.3f}')")
  cn=$(python3 -c "print(f'{max($ct-$cbase,0.0):.3f}')")
  ratio=$(python3 -c "print(f'{$cn/$gn:.1f}x' if $gn > 0 else '-')")
  printf '%-15s %8s %10s %8s  %s\n' "$m" "$gn" "$cn" "$ratio" "$okq"
done
exit $fail
