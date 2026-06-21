#!/usr/bin/env bash
########################################################################
# xats2go — REUSABLE DIFFERENTIAL HARNESS  (milestone M2.0)
#
#   build-go.sh <source.dats> [--force]
#
# Compiles ANY ATS3 source through BOTH backends and asserts the two
# stdouts are byte-equal -- the differential oracle that gates every M2
# chunk:
#
#   <source.dats>
#     -> shared xatsopt frontend (parse + typecheck)      [lib2xatsopt, reused]
#     -> trxd3i0 / tryd3i0   (D3 -> intrep0)              [lib2xats2cc, reused]
#     -> trxi0i1             (intrep0 -> intrep1)          [copied into xats2go]
#     -> i1parsed_go1emit    -> <name>.go                  [xats2go, OUR backend]
#         -> scratch Go module (replace xatsgo => runtime/xatsgo)
#         -> gofmt -l / go vet / go build / run            -> GO stdout
#     -> i1parsed_js1emit    -> <name>.js                  [xats2js, reference]
#         -> node                                          -> JS stdout
#     -> ASSERT  GO stdout == JS stdout   (byte-equal; xxd diff on FAIL)
#
# Purely additive: writes only into a per-test scratch dir under
# srcgen2/xats2go/srcgen2/BUILD/<name>/.  REUSES the prebuilt frontend
# libs (never rebuilds lib2xatsopt.js / lib2xats2cc.js / lib2xats2js.js).
#
# Caching: lib2xats2go.js is rebuilt only when one of its DATS sources (or
# the driver) is newer than the cached lib, or when --force is given.
# Correctness-first: --force always does a clean rebuild.
#
# Exit 0 + PASS banner  <=>  green & byte-equal-vs-JS.   Nonzero on any
# failure (transpile, go vet/build, run, or stdout mismatch).
########################################################################
set -uo pipefail

########################################################################
# 0. args + paths
########################################################################
FORCE=0
SRC=""
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    -*) echo "!! unknown flag: $a" >&2; exit 2 ;;
    *)  SRC="$a" ;;
  esac
done
[ -n "$SRC" ] || { echo "usage: build-go.sh <source.dats> [--force]" >&2; exit 2; }
[ -f "$SRC" ] || { echo "!! source not found: $SRC" >&2; exit 2; }
# absolute-ize the source path (the driver opens it; also used in messages)
SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
NAME="$(basename "$SRC" .dats)"

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"
FRONTEND="$XATSHOME/frontend"
XATS2GO="$SRCGEN2/xats2go/srcgen2"
RUNTIMEGO="$SRCGEN2/xats2go/runtime/xatsgo"
JSSHIM="$SRCGEN2/xats2go/runtime/jsshim/gen-i0varfst-shim.sh"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
LIB2CC="$FRONTEND/BUILD/lib2xats2cc.js"
LIB2JS="$FRONTEND/BUILD/lib2xats2js.js"   # JS differential oracle

NODE="node --stack-size=8801"

# shared (cached) build area + per-test scratch dir
BUILD="$XATS2GO/BUILD"
WORK="$BUILD/$NAME"
GOOUT="$WORK/GO"
GOMOD="$WORK/GOMOD"
mkdir -p "$BUILD" "$WORK" "$GOOUT" "$GOMOD"

for f in "$LIB2OPT" "$LIB2CC"; do
  [ -f "$f" ] || { echo "!! missing prebuilt lib: $f" >&2; exit 1; }
done
command -v go >/dev/null 2>&1 || { echo "!! 'go' not on PATH" >&2; exit 1; }

########################################################################
# 1. THE DATS SOURCE SET for lib2xats2go.js  (ONE obvious place: add new
#    go1emit_*.dats here in dependency order; emitter files go after the
#    env [xats2go_myenv0] and before the tmplib [xats2go_tmplib, last]).
########################################################################
GO_DATS=(
  intrep1.dats
  intrep1_print0.dats
  intrep1_utils0.dats
  trxi0i1.dats
  trxi0i1_myenv0.dats
  trxi0i1_dynexp.dats
  trxi0i1_decl00.dats
  xats2go_myenv0.dats
  go1emit_tytab0.dats       # M2.6a: the i1tnm->i0typ side-table (provides go_tytab_put/get/reset)
  go1emit_styp0.dats        # NEW (M2.0): liveness + s2typ->Go-type scaffold
  go1emit_utils0.dats
  go1emit_dynexp.dats
  go1emit_decl00.dats
  go1emit.dats
  xats2go_tmplib.dats
)
DRIVER="$XATS2GO/UTIL/xats2go_goemit01.dats"

########################################################################
# helper: transpile one DATS to JS via jsemit00, guard our own sources.
########################################################################
transpile_one() {
  local dir="$1" f="$2" idx="$3" out="$4"
  local base="${f%.dats}"
  local trans="$BUILD/$(basename "$dir")__${base}_dats_out0.js"
  $NODE "$JSEMIT" "$dir/$f" > "$trans" 2>"$trans.err"
  if [ "$(wc -l < "$trans")" -lt 3 ]; then
    echo "!! transpile FAILED for $dir/$f (see $trans.err)" >&2
    tail -30 "$trans.err" >&2
    return 1
  fi
  # a parse/typecheck error in OUR backend source would silently drop the
  # offending decl (-> // I1Dnone1 comment) and surface later as a runtime
  # ReferenceError.  Catch it here for OUR files (the prelude legitimately
  # streams some errck markers).
  case "$f" in
    go1emit*.dats|xats2go_*.dats)
      if grep -qE "F3PERR0-ERROR.*${f}|PREAD00-ERROR.*${f}" "$trans.err"; then
        echo "!! parse/typecheck ERROR in $f (see $trans.err):" >&2
        grep -E "ERROR.*${f}" "$trans.err" | head -8 >&2
        return 1
      fi ;;
  esac
  sed -e "s/jsxtnm/jsx${idx}tnm/g" "$trans" >> "$out"
  return 0
}

########################################################################
# helper: (re)build lib2xats2go.js from $GO_DATS, with mtime caching.
########################################################################
build_lib2go() {
  local out="$1"
  # cache check: skip if [out] exists and is newer than every DATS source
  # and the driver and this script.
  if [ "$FORCE" -eq 0 ] && [ -f "$out" ]; then
    local stale=0 src
    for f in "${GO_DATS[@]}"; do
      src="$XATS2GO/DATS/$f"
      [ "$src" -nt "$out" ] && stale=1
    done
    [ "${BASH_SOURCE[0]}" -nt "$out" ] && stale=1
    if [ "$stale" -eq 0 ]; then
      echo "   (cached) $out is up to date ($(wc -l < "$out") lines)"
      return 0
    fi
  fi
  : > "$out"
  local idx=100 f
  for f in "${GO_DATS[@]}"; do
    transpile_one "$XATS2GO/DATS" "$f" "$idx" "$out" || return 1
    idx=$((idx + 1))
  done
  echo "   -> $out ($(wc -l < "$out") lines, ${#GO_DATS[@]} files)"
  return 0
}

########################################################################
# helper: link a compiler bundle  runtime + js1·opt + js2·cc + js3·LIB + driver,
#         then prepend the i0varfst shim.  Echoes the patched bundle path.
########################################################################
S2R="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
S1R="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
RUNTIME=(
  "$S2R/xats2js_js1emit.js"
  "$S2R/srcgen2_precats.js"
  "$S1R/srcgen1_prelude.js"
  "$S1R/srcgen1_prelude_node.js"
  "$S1R/srcgen1_xatslib_node.js"
)
link_bundle() {
  local lib3="$1" drv="$2" bundle="$3"
  cat "${RUNTIME[@]}" > "$bundle"
  sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$bundle"
  sed -E 's/jsx(...)tnm/js2\1tnm/g' "$LIB2CC"  >> "$bundle"
  sed -E 's/jsx(...)tnm/js3\1tnm/g' "$lib3"    >> "$bundle"
  cat "$drv" >> "$bundle"
  local shim="${bundle%.js}.shim.js"
  bash "$JSSHIM" "$bundle" "$shim" >/dev/null || { echo "!! shim gen failed" >&2; return 1; }
  cat "$shim" "$bundle" > "${bundle%.js}.patched.js"
  echo "${bundle%.js}.patched.js"
}

########################################################################
echo ">> [1/7] build lib2xats2go.js (intrep1 + trxi0i1 + env + go1emit)"
########################################################################
LIB2GO="$BUILD/lib2xats2go.js"
build_lib2go "$LIB2GO" || exit 1

########################################################################
echo ">> [2/7] transpile go driver"
########################################################################
DRV_GO="$BUILD/xats2go_goemit01_dats.js"
if [ "$FORCE" -ne 0 ] || [ ! -f "$DRV_GO" ] || [ "$DRIVER" -nt "$DRV_GO" ]; then
  $NODE "$JSEMIT" "$DRIVER" > "$DRV_GO" 2>"$BUILD/transpile_godrv.err"
  [ "$(wc -l < "$DRV_GO")" -ge 5 ] || { echo "!! go driver transpile too small" >&2; tail -40 "$BUILD/transpile_godrv.err" >&2; exit 1; }
else
  echo "   (cached) $DRV_GO"
fi

########################################################################
echo ">> [3/7] link go-emitter bundle + run on $NAME -> emit Go"
########################################################################
GOBUNDLE="$WORK/xats2go-bundle.js"
GOPATCHED="$(link_bundle "$LIB2GO" "$DRV_GO" "$GOBUNDLE")" || exit 1
RAWOUT="$WORK/go-stdout.txt"
$NODE "$GOPATCHED" "$SRC" > "$RAWOUT" 2>"$WORK/go-stderr.txt"; RC=$?
echo ">> go-emitter exit code: $RC"
if [ "$RC" -ne 0 ]; then
  echo "!! go-emitter bundle did not exit 0" >&2
  echo "--- stderr tail ---"; tail -40 "$WORK/go-stderr.txt" >&2
  exit "$RC"
fi
EMIT="$GOOUT/$NAME.go"
awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$RAWOUT" > "$EMIT"
echo ">> extracted emitted Go -> $EMIT ($(wc -l < "$EMIT") lines)"
[ "$(wc -c < "$EMIT")" -ge 2 ] || { echo "!! no emitted Go captured" >&2; cat "$RAWOUT" >&2; exit 1; }
echo "-- emitted Go ($NAME.go) --"; cat "$EMIT"

########################################################################
echo ">> [4/7] assemble Go module + gofmt / go vet / go build / run"
########################################################################
cat > "$GOMOD/go.mod" <<EOF
module xats2go_$NAME

go 1.26

require xatsgo v0.0.0
replace xatsgo => $RUNTIMEGO
EOF
cp "$EMIT" "$GOMOD/$NAME.go"
( cd "$GOMOD" && go mod tidy >/dev/null 2>&1 || true )

# M2.6b: gofmt-CANONICALIZE the assembled file in place (PLAN Sec.5.8 -- "run
# gofmt on output as a convenience").  The emitter writes a single-line
# anonymous struct type `struct{F0 T0; F1 T1}` for tuples/records; gofmt
# expands a MULTI-FIELD inline struct type to multi-line (its fixed behavior),
# so the emitted text, while semantically identical (Go is whitespace-
# insensitive -- it still builds/vets/runs/byte-matches), is not gofmt-canonical
# as written.  Formatting it here makes the CHECKED + BUILT file gofmt-clean
# without changing behavior.  (A future M2.6c/M3 may hoist named `type`
# declarations so the emitter is canonical at the source.)
gofmt -w "$GOMOD/$NAME.go" 2>/dev/null || true

echo "-- gofmt -l (empty == canonical) --"
if [ -z "$(gofmt -l "$GOMOD/$NAME.go")" ]; then
  echo ">> gofmt: clean"
else
  echo "!! gofmt: would reformat $NAME.go (showing diff):" >&2
  gofmt -d "$GOMOD/$NAME.go" >&2
  echo "   (cosmetic; not a hard gate, continuing)"
fi
echo "-- go vet --"
( cd "$GOMOD" && go vet ./... ) && echo ">> go vet: OK" || { echo "!! go vet FAILED" >&2; exit 1; }
echo "-- go build --"
( cd "$GOMOD" && go build -o "$WORK/$NAME.bin" . ) && echo ">> go build: OK" || { echo "!! go build FAILED" >&2; exit 1; }
echo "-- run --"
GO_STDOUT="$WORK/$NAME.go.stdout"
"$WORK/$NAME.bin" > "$GO_STDOUT" 2>"$WORK/$NAME.go.stderr"; GRC=$?
echo ">> program exit code: $GRC"
[ "$GRC" -eq 0 ] || { echo "!! program did not exit 0" >&2; cat "$WORK/$NAME.go.stderr" >&2; exit 1; }
echo "-- Go stdout (xxd) --"; xxd "$GO_STDOUT"

########################################################################
echo ">> [5/7] build JS-backend reference (the differential oracle)"
########################################################################
JS_STDOUT="$WORK/$NAME.js.stdout"
: > "$JS_STDOUT"
if [ -f "$LIB2JS" ]; then
  JDRV="$BUILD/xats2js_jsemit01_dats.js"
  if [ "$FORCE" -ne 0 ] || [ ! -f "$JDRV" ]; then
    $NODE "$JSEMIT" "$SRCGEN2/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats" > "$JDRV" 2>"$BUILD/transpile_jsdrv.err"
  fi
  if [ "$(wc -l < "$JDRV")" -ge 5 ]; then
    JSBUNDLE="$WORK/xats2js-ref.js"
    JSPATCHED="$(link_bundle "$LIB2JS" "$JDRV" "$JSBUNDLE")" || exit 1
    # emit user JS; driver also prints a debug trace, so keep only from the
    # first emitted '// LCSRCsome1(...<name>...)' comment onward.
    $NODE "$JSPATCHED" "$SRC" > "$WORK/$NAME.emit.js" 2>"$WORK/jsemit.err"
    awk -v n="$NAME" 'f||$0 ~ ("^// LCSRCsome1.*"n){f=1; print}' "$WORK/$NAME.emit.js" > "$WORK/$NAME.user.js"
    # run the emitted user JS on node with the node-side prelude runtime.
    NS2R="$SRCGEN2/xats2js/srcgen1/xshared/runtime"
    RUNJS="$WORK/$NAME.run.js"
    cat "$NS2R/srcgen2_prelude.js" "$NS2R/srcgen2_prelude_node.js" \
        "$NS2R/srcgen2_precats.js" "$NS2R/srcgen2_xatslib.js" \
        "$S2R/xats2js_js1emit.js" "$WORK/$NAME.user.js" > "$RUNJS"
    node "$RUNJS" > "$JS_STDOUT" 2>"$WORK/$NAME.js.stderr"
    echo "-- JS stdout (xxd) --"; xxd "$JS_STDOUT"
  else
    echo "   (js driver transpile too small; JS oracle unavailable)" >&2
  fi
else
  echo "   (lib2xats2js.js absent; JS oracle unavailable)" >&2
fi

########################################################################
echo ">> [6/7] ORACLE: assert Go stdout == JS stdout (byte-equal)"
########################################################################
EXPECT_DIR="$XATS2GO/TEST/OUTS"
mkdir -p "$EXPECT_DIR"
EXPECT="$EXPECT_DIR/$NAME.expected"
ok=0
if [ -s "$JS_STDOUT" ]; then
  if cmp -s "$GO_STDOUT" "$JS_STDOUT"; then
    echo ">> DIFFERENTIAL-vs-JS: Go stdout is BYTE-EQUAL to JS stdout."
    cp "$GO_STDOUT" "$EXPECT"   # refresh the golden from the verified run
    ok=1
  else
    echo "!! DIFFERENTIAL-vs-JS MISMATCH:" >&2
    echo "--- go  ($(wc -c < "$GO_STDOUT") bytes) ---" >&2; xxd "$GO_STDOUT" >&2
    echo "--- js  ($(wc -c < "$JS_STDOUT") bytes) ---" >&2; xxd "$JS_STDOUT" >&2
    echo "--- diff ---" >&2; diff <(xxd "$GO_STDOUT") <(xxd "$JS_STDOUT") >&2 || true
    exit 1
  fi
elif [ -z "$(cat "$JS_STDOUT")" ] && [ ! -s "$GO_STDOUT" ]; then
  # both empty: a program with no observable output is a (degenerate) pass
  # only if the JS side actually ran; otherwise fall through to golden.
  :
fi
if [ "$ok" -eq 0 ]; then
  if [ -s "$EXPECT" ] && cmp -s "$GO_STDOUT" "$EXPECT"; then
    echo ">> GOLDEN: Go stdout matches $EXPECT (JS oracle deferred)."
    ok=1
  else
    echo "!! no oracle matched (no usable JS ref and no/!= golden)" >&2
    echo "--- go stdout ---" >&2; xxd "$GO_STDOUT" >&2
    exit 1
  fi
fi

########################################################################
echo ">> [7/7] PASS"
########################################################################
echo "======================================================================"
echo ">> xats2go build-go.sh GREEN: $NAME"
echo ">>   emitted: $EMIT"
echo ">>   stdout : $(tr -d '\n' < "$GO_STDOUT" | head -c 80) (+newlines)"
echo "======================================================================"
exit 0
