#!/usr/bin/env bash
# build.sh — build the ATS3 LSP server: emit each server module to Go with
# the xats2go compiler, assemble into ONE Go package (the selfhost-build
# recipe: strip headers, rename per-module temps, preserve module inits,
# dedup layout structs), splice the CATS/GO floors, go build.
#
#   tools/build.sh            incremental (mtime-cached emissions)
#   tools/build.sh clean      force re-emit of every module
#
# EMITTER: the node BUNDLE by default (it is rebuilt from emitter sources
# by selfhost-build/build.sh quick, so it carries the language-server
# package-path support the moment it lands).  XLSP_EMIT=selfhost switches
# to the native binary once a selfcycle has rebuilt it with that change.
#
# STAMP DISCIPLINE: any SATS/HATS change shifts stamps for EVERY module,
# so such a change forces a full re-emit (checked below).
set -uo pipefail
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X
ulimit -s 65520 2>/dev/null || true
G=$X/language-server/go-server
B=$G/BUILD
EMIT=$B/emit
SRC=$B/src
mkdir -p "$EMIT" "$SRC"

# assembly order = staload order (lspserver_sats.hats); the driver is LAST
# (its renamed main runs after every module's init).
MODULES="lsp_floor lsp_util lsp_json lsp_frame lsp_uri lsp_diag lsp_index lsp_main"

BUNDLE=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
SELFHOST=$X/srcgen2/xats2go/selfhost-build/src/xats2go-selfhost
RUNTIME=$X/srcgen2/xats2go/runtime/xatsgo
export NODE_COMPILE_CACHE=$X/srcgen2/xats2go/srcgen2/BUILD/.v8cache

emit_one() { # emit_one <mod>  -> $EMIT/<mod>.go
  local m=$1 src=$G/DATS/$m.dats
  if [ "${XLSP_EMIT:-bundle}" = selfhost ]; then
    "$SELFHOST" "$src" > "$EMIT/$m.raw" 2> "$EMIT/$m.err"
  else
    node --stack-size=50000 "$BUNDLE" "$src" > "$EMIT/$m.raw" 2> "$EMIT/$m.err"
  fi
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' \
    "$EMIT/$m.raw" > "$EMIT/$m.go"
  if [ ! -s "$EMIT/$m.go" ]; then
    echo "!! empty emission for $m"; tail -5 "$EMIT/$m.err"; return 1
  fi
  local nerr
  nerr=$(grep -c 'F3PERR0-ERROR\|PREAD00-ERROR' "$EMIT/$m.err" || true)
  if [ "$nerr" != 0 ]; then
    echo "!! $m: $nerr frontend errors"
    grep 'F3PERR0-ERROR\|PREAD00-ERROR' "$EMIT/$m.err" | head -5; return 1
  fi
  return 0
}

# ---- 1. emit (mtime-cached; SATS/HATS edits invalidate everything) -------
FORCE=0
[ "${1:-}" = clean ] && FORCE=1
# newest stamp-relevant shared input
NEWEST_SHARED=$(ls -t "$G"/SATS/*.sats "$G"/HATS/*.hats 2>/dev/null | head -1)
EMITTER_BIN=$BUNDLE
[ "${XLSP_EMIT:-bundle}" = selfhost ] && EMITTER_BIN=$SELFHOST
for m in $MODULES; do
  out=$EMIT/$m.go
  stale=$FORCE
  [ -s "$out" ] || stale=1
  [ "$G/DATS/$m.dats" -nt "$out" ] && stale=1
  [ "$EMITTER_BIN" -nt "$out" ] && stale=1
  [ -n "$NEWEST_SHARED" ] && [ "$NEWEST_SHARED" -nt "$out" ] && stale=1
  if [ "$stale" = 1 ]; then
    echo ">> emit $m"
    emit_one "$m" || exit 1
  fi
done

# ---- 3. floors -----------------------------------------------------------
# 3a. the CATS/GO prelude floor (bench/run-goarm recipe, $->_ mangled)
GO_CATS="xtop000 gint000 bool000 char000 gflt000 axrf000 unsfx00 strn000"
CATSPATHS=""
for c in $GO_CATS; do CATSPATHS="$CATSPATHS $X/prelude/DATS/CATS/GO/$c.cats"; done
IMPLINE=""
for p in fmt math reflect strconv strings; do
  if grep -qhE "\b$p\." $CATSPATHS 2>/dev/null; then IMPLINE="$IMPLINE \"$p\";"; fi
done
{
  echo 'package main'
  echo "import ($IMPLINE )"
  for c in $GO_CATS; do sed 's/\$/_/g' "$X/prelude/DATS/CATS/GO/$c.cats"; done
} > "$SRC/zz_floor.go"
# 3b. the server's own extern floor (name=importpath pairs)
LSPCATS=$G/CATS/GO/lsp_floor.cats
LIMPLINE=""
for pi in os=os io=io time=time bufio=bufio fmt=fmt strings=strings \
          bytes=bytes exec=os/exec xatsgo=xatsgo; do
  p=${pi%%=*}; imp=${pi#*=}
  if grep -qE "\b$p\." "$LSPCATS"; then LIMPLINE="$LIMPLINE \"$imp\";"; fi
done
{
  echo 'package main'
  echo "import ($LIMPLINE )"
  sed 's/\$/_/g' "$LSPCATS"
} > "$SRC/zz_lspfloor.go"

# ---- 4. wire against the compiler assembly (M6: in-process checks) -------
# The server links libxatsopt: assembly + build happen in
# selfhost-build/wire-server.sh (module processing, layout dedup vs the
# compiler packages, tchecklib/lspidx modules, zz_init, go build), which
# writes the binary back to $B/ats3-lsp-server.
bash "$X/srcgen2/xats2go/selfhost-build/wire-server.sh" || exit 1
