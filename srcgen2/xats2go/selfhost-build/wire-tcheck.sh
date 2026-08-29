#!/usr/bin/env bash
# wire-tcheck.sh — build the CHECK-ONLY driver (UTIL/xats2go_tcheck01.dats,
# for the ATS3 LSP server) as a SECOND main package over the already-built
# frontend packages: emit the driver with the bundle, process it exactly as
# wire-driver.sh processes the CLI driver, place it in src/tcheck/ together
# with a verbatim copy of zz_init.go (module inits + runtime hooks), and
# `go build ./tcheck` -> src/xats2go-tcheck.
#
# Run AFTER a full assembly exists (src/zz*/ packages present).  Symbol
# stamps are source-location-derived, so the check driver links against
# the same packages the CLI driver does.
set -uo pipefail
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X
ulimit -s 65520 2>/dev/null || true
NODESTK="${NODESTK:-50000}"
GOPATCHED=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
OUT=$X/srcgen2/xats2go/selfhost-build
EMIT="$OUT/emit"
SRC="$OUT/src"
mkdir -p "$EMIT" "$SRC/tcheck"

[ -d "$SRC/zzbase" ] || { echo "!! wire-tcheck: no assembled packages in src/ (run a full build first)"; exit 1; }
[ -s "$SRC/zz_init.go" ] || { echo "!! wire-tcheck: src/zz_init.go missing"; exit 1; }

SATSDEP=$X/srcgen2/xats2go/srcgen2/UTIL/xats2go_lspidx.sats
for m in xats2go_tcheck01 xats2go_lspidx; do
  f=$X/srcgen2/xats2go/srcgen2/UTIL/$m.dats
  if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] \
     || [ "$SATSDEP" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
    node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  [ -s "$EMIT/$m.go" ] || { echo "!! wire-tcheck: empty emission ($m)"; tail -5 "$EMIT/$m.err"; exit 1; }
done
m=xats2go_tcheck01

# driver file: keep EVERYTHING including func main; rename temps godrvtnm
# (the same processing as wire-driver.sh, plus the package-path imports the
# root drivers carry — copied from the generated zz_init.go header).  Layout
# structs (Zzs_*/ZzpZzs_*) are STRIPPED like assemble.sh strips them per
# module: zzbase already declares the deduplicated union (a layout only the
# driver touches would surface as a loud undefined-identifier error).
{
  sed -n '1,/^func init/p' "$SRC/zz_init.go" | sed '$d' | sed '/^func /d'
  awk 'BEGIN{started=0}
       /^type Zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func ZzpZzs_/{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed -E "s/goxtnm([0-9])/godrvtnm\\1/g" \
    | sed -E "s/goxtmpl([0-9])/godrvtmpl\\1/g"
} > "$SRC/tcheck/zz_tcheck.go"

# the lspidx module: processed like an assemble.sh module (strip layouts +
# header, rename temps, rename its trivial main out of the way — it has no
# top-level effects, so it is never called).
{
  sed -n '1,/^func init/p' "$SRC/zz_init.go" | sed '$d' | sed '/^func /d'
  awk 'BEGIN{started=0}
       /^type Zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func ZzpZzs_/{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/xats2go_lspidx.go" \
    | sed -E "s/goxtnm([0-9])/goidxtnm\\1/g" \
    | sed -E "s/goxtmpl([0-9])/goidxtmpl\\1/g" \
    | sed "s/^func main() {\$/func Zzmodinit_lspidx() {/"
  printf '\nvar _ = Zzmodinit_lspidx\n'
} > "$SRC/tcheck/zz_lspidx.go"

# module inits + runtime hooks: verbatim (same package main content).
cp "$SRC/zz_init.go" "$SRC/tcheck/zz_init.go"

( cd "$SRC" && gofmt -w tcheck >/dev/null 2>&1
  go build -o "$SRC/xats2go-tcheck" ./tcheck 2> "$SRC/tcheck/build.err" ) \
  || { echo "!! wire-tcheck: go build FAILED"; head -20 "$SRC/tcheck/build.err"; exit 1; }
echo ">> built $SRC/xats2go-tcheck"
