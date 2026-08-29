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

# ---- 2. assemble one package file ---------------------------------------
ALL=$SRC/lspserver_all.go
{
  printf 'package main\n\n'
  printf 'import "xatsgo"\nimport "unsafe"\n\n'
  printf 'var _ = xatsgo.XATSNIL\nvar _ unsafe.Pointer\n\n'
} > "$ALL"
: > "$SRC/.layouts"
: > "$SRC/.modinits"
n=0; MI=0
for m in $MODULES; do
  printf '//==ZZMOD:%s==\n' "$m" >> "$ALL"
  awk 'BEGIN{started=0}
       /^type Zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func ZzpZzs_/{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed -E "s/goxtnm([0-9])/go${n}tnm\\1/g" \
    | sed -E "s/goxtmpl([0-9])/go${n}tmpl\\1/g" \
    | sed "s/^func main() {\$/func Zzmodinit_${MI}() {/" >> "$ALL"
  awk '/^type Zzs_[a-z]* struct \{$/{lay=1} lay{print; if($0=="}"){lay=0}; next}
       /^func ZzpZzs_/{print}' "$EMIT/$m.go" >> "$SRC/.layouts"
  echo "Zzmodinit_${MI}" >> "$SRC/.modinits"
  printf '\n' >> "$ALL"
  MI=$((MI+1)); n=$((n+1))
done
{
  printf '\n//==ZZLAYOUTS==\n'
  awk '/^type (Zzs_[a-z]*) struct \{$/{nm=$2; if(nm in seen){skip=1} else {seen[nm]=1; skip=0}; if(!skip)print; next}
       /^func ZzpZzs_/{fn=$2; sub(/\(.*/,"",fn); if(fn in seenf)next; seenf[fn]=1; print; next}
       !skip{print}
       /^\}$/{skip=0}' "$SRC/.layouts"
  # the generated main runs every module's preserved top-level effects in
  # assembly order; the DRIVER's effects (the serve loop) run last.  NO
  # print-store flush afterwards: stdout is the protocol channel.
  printf '\nfunc main() {\n'
  while IFS= read -r nm; do printf '\t%s()\n' "$nm"; done < "$SRC/.modinits"
  printf '}\n'
} >> "$ALL"

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
# 3b. the server's own extern floor (name=importpath pairs: `exec.` needs
# the "os/exec" import)
LSPCATS=$G/CATS/GO/lsp_floor.cats
LIMPLINE=""
for pi in os=os io=io time=time bufio=bufio fmt=fmt strings=strings \
          bytes=bytes exec=os/exec; do
  p=${pi%%=*}; imp=${pi#*=}
  if grep -qE "\b$p\." "$LSPCATS"; then LIMPLINE="$LIMPLINE \"$imp\";"; fi
done
{
  echo 'package main'
  echo "import ($LIMPLINE )"
  sed 's/\$/_/g' "$LSPCATS"
} > "$SRC/zz_lspfloor.go"

# ---- 4. go build ---------------------------------------------------------
printf 'module ats3lspserver\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' \
  "$RUNTIME" > "$SRC/go.mod"
( cd "$SRC" && gofmt -w . >/dev/null 2>&1
  go build ${XGCFLAGS:+-gcflags "$XGCFLAGS"} -o "$B/ats3-lsp-server" . 2> "$SRC/build.err" ) \
  || { echo "!! go build FAILED"; head -30 "$SRC/build.err"; exit 1; }
echo ">> built $B/ats3-lsp-server"
