#!/usr/bin/env bash
# assemble.sh — emit all emitter modules to Go and assemble them into one
# package, to drive a multi-module `go build` toward self-hosting.
set -uo pipefail
X=/home/user/ATS-Xanadu
export XATSHOME=$X
GOPATCHED=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
OUT=$X/srcgen2/xats2go/selfhost-build
RUNTIME=$X/srcgen2/xats2go/runtime/xatsgo
mkdir -p "$OUT/src"
EMIT="$OUT/emit"; mkdir -p "$EMIT"

# 1. emit each module to Go (between sentinels), strip header (first 6 lines) +
#    the trailing trivial `func main(){...}`.
: > "$OUT/src/emitter_all.go"
printf 'package main\n\nimport "xatsgo"\n\nvar _ = xatsgo.XATSNIL\n\n' > "$OUT/src/emitter_all.go"
n=0
for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
  m="$(basename "$f" .dats)"
  node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  # strip header (package/import/keepalive — up to first `func `) and the final main.
  awk 'BEGIN{started=0}
       /^func main\(\) \{/{inmain=1}
       inmain{next}
       /^func /{started=1}
       started{print}' "$EMIT/$m.go" >> "$OUT/src/emitter_all.go"
  printf "\n" >> "$OUT/src/emitter_all.go"
  n=$((n+1))
done
printf '\nfunc main() { xatsgo.XATS2GO_flush_pending() }\n' >> "$OUT/src/emitter_all.go"
echo ">> assembled $n modules -> $OUT/src/emitter_all.go ($(wc -l < "$OUT/src/emitter_all.go") lines)"

# 2. go module
printf 'module selfhostemit\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' "$RUNTIME" > "$OUT/src/go.mod"
