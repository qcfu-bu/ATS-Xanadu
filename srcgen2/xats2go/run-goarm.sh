#!/usr/bin/env bash
########################################################################
# run-goarm.sh <test.dats> — compile a program through the CATS/GO prelude
# arm and run it, comparing to a golden.
#
# Uses the MAKEFILE's bundle (srcgen2/BUILD/xats2go-bundle.patched.js — the
# canonical builder with the correct local lib2xats2cc), run with --go-arm,
# then splices the self-contained CATS/GO .cats floor into the emitted Go
# module ($->_ mangled), go build + run, cmp vs golden.
#
# Run `make` first (or `make run/<anyjs test>`) if emitter sources changed so
# the bundle is current.
########################################################################
set -uo pipefail
export XATSHOME="${XATSHOME:-/home/user/ATS-Xanadu}"
X="$XATSHOME/srcgen2/xats2go"
SRC="$1"; [ -f "$SRC" ] || { echo "usage: run-goarm.sh <test.dats>"; exit 2; }
NAME="$(basename "$SRC" .dats)"
BUNDLE="$X/srcgen2/BUILD/xats2go-bundle.patched.js"
[ -f "$BUNDLE" ] || { echo "!! bundle missing: $BUNDLE (run 'make' in $X first)"; exit 1; }

# the CATS/GO modules that make up the floor (extend as modules are added).
GO_CATS="xtop000 gint000 bool000 char000 gflt000 axrf000 strn000"

WORK="$X/srcgen2/BUILD/goarm_$NAME"; rm -rf "$WORK"; mkdir -p "$WORK"

echo ">> [1/4] emit Go (--go-arm)"
node --stack-size=8801 "$BUNDLE" "$SRC" --go-arm > "$WORK/raw.txt" 2>"$WORK/err.txt"
RC=$?
awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$WORK/raw.txt" > "$WORK/main.go"
if [ "$RC" -ne 0 ] || [ ! -s "$WORK/main.go" ]; then
  echo "!! emitter failed (rc=$RC)"; grep -vE '^d0parsed_from_fpath' "$WORK/err.txt" | tail -25; exit 1
fi

echo ">> [2/4] assemble module (emitted + CATS/GO floor)"
# auto-detect the std imports the included floor actually references (Go errors
# on BOTH a missing import and an unused one, so the set must match exactly).
CATSPATHS=""; for c in $GO_CATS; do CATSPATHS="$CATSPATHS $XATSHOME/prelude/DATS/CATS/GO/$c.cats"; done
IMPLINE=""
for p in fmt math strconv strings; do
  if grep -qhE "\b$p\." $CATSPATHS 2>/dev/null; then IMPLINE="$IMPLINE \"$p\";"; fi
done
{
  echo 'package main'
  echo "import ($IMPLINE )"
  for c in $GO_CATS; do sed 's/\$/_/g' "$XATSHOME/prelude/DATS/CATS/GO/$c.cats"; done
} > "$WORK/zz_floor.go"
cat > "$WORK/go.mod" <<EOF
module goarm_$NAME
go 1.24
require xatsgo v0.0.0
replace xatsgo => $X/runtime/xatsgo
EOF
( cd "$WORK" && gofmt -w . >/dev/null 2>&1; go mod tidy >/dev/null 2>&1 )

echo ">> [3/4] go build"
if ! ( cd "$WORK" && go build -o bin . 2>"$WORK/build.err" ); then
  echo "!! go build FAILED"; head -30 "$WORK/build.err"; exit 1
fi

echo ">> [4/4] run + compare golden"
"$WORK/bin" > "$WORK/out.txt" 2>"$WORK/run.err" || { echo "!! run failed"; cat "$WORK/run.err"; exit 1; }
GOLDEN="$X/srcgen2/TEST/OUTS/$NAME.expected"
if [ -f "$GOLDEN" ]; then
  if cmp -s "$WORK/out.txt" "$GOLDEN"; then
    echo ">> GOARM PASS: $NAME  (byte-equal golden)"; cat "$WORK/out.txt"
  else
    echo "!! MISMATCH vs golden:"; diff "$WORK/out.txt" "$GOLDEN"; exit 1
  fi
else
  echo ">> (no golden — output below; save to $GOLDEN to gate)"; cat "$WORK/out.txt"
fi
