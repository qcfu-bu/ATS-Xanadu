#!/usr/bin/env bash
# wire-server.sh — build the ATS3 LSP server (M6: IN-PROCESS compiler) as a
# THIRD main package over the already-built frontend packages: the server
# module emissions (produced by language-server/server/tools/build.sh)
# are processed exactly like assemble.sh modules and placed in src/lspserver/
# together with the tchecklib/lspidx modules (shared with src/tcheck/), the
# prelude+server floors, and a verbatim zz_init.go; `go build ./lspserver`
# -> language-server/server/BUILD/ats3-lsp-server.
#
# Run via tools/build.sh (which refreshes the module emissions first).
# Symbol stamps are source-location-derived, so the server modules link
# against the same packages the CLI/tcheck drivers do.
set -uo pipefail
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X
G=$X/language-server/server
B=$G/BUILD
EMIT=$B/emit
OUT=$X/srcgen2/xats2go/selfhost-build
SRC=$OUT/src
DST=$SRC/lspserver
MODULES="lsp_floor lsp_util lsp_json lsp_frame lsp_uri lsp_diag lsp_index lsp_main"
mkdir -p "$DST"

[ -d "$SRC/zzbase" ] || { echo "!! wire-server: no assembled packages in src/ (run a full build first)"; exit 1; }
[ -s "$SRC/zz_init.go" ] || { echo "!! wire-server: src/zz_init.go missing"; exit 1; }
[ -s "$B/src/zz_floor.go" ] || { echo "!! wire-server: $B/src/zz_floor.go missing (run tools/build.sh)"; exit 1; }

# tchecklib + lspidx: ensure the processed module files exist and are fresh
# (wire-tcheck.sh maintains them; cheap when cached).
bash "$OUT/wire-tcheck.sh" || exit 1

# the glue module (compiler world): emit + process like wire-tcheck does.
GOPATCHED=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
NODESTK="${NODESTK:-50000}"
ulimit -s 65520 2>/dev/null || true
GEMIT=$OUT/emit
m=xats2go_lspglue
f=$X/srcgen2/xats2go/srcgen2/UTIL/$m.dats
GLUESATS=$X/srcgen2/xats2go/srcgen2/UTIL/$m.sats
TCLSATS=$X/srcgen2/xats2go/srcgen2/UTIL/xats2go_tchecklib.sats
if [ ! -s "$GEMIT/$m.go" ] || [ "$f" -nt "$GEMIT/$m.go" ] \
   || [ "$GLUESATS" -nt "$GEMIT/$m.go" ] || [ "$TCLSATS" -nt "$GEMIT/$m.go" ] \
   || [ "$GOPATCHED" -nt "$GEMIT/$m.go" ]; then
  node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$GEMIT/$m.raw" 2>"$GEMIT/$m.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$GEMIT/$m.raw" > "$GEMIT/$m.go"
fi
[ -s "$GEMIT/$m.go" ] || { echo "!! wire-server: empty glue emission"; tail -5 "$GEMIT/$m.err"; exit 1; }
nerr=$(grep -c 'F3PERR0-ERROR\|PREAD00-ERROR' "$GEMIT/$m.err" || true)
[ "$nerr" = 0 ] || { echo "!! wire-server: glue emission has $nerr frontend errors"; exit 1; }

# the zz_init header (package + dot-imports + anchors), reused per file.
HDRF=$DST/.hdr
sed -n '1,/^func init/p' "$SRC/zz_init.go" | sed '$d' | sed '/^func /d' > "$HDRF"

rm -f "$DST"/zz_srv_*.go "$DST/.layouts"
: > "$DST/.layouts"
n=0
for m in $MODULES; do
  [ -s "$EMIT/$m.go" ] || { echo "!! wire-server: missing emission $EMIT/$m.go"; exit 1; }
  {
    echo 'package main'
    echo
    grep '^import ' "$HDRF"
    echo 'import "unsafe"'
    echo
    grep '^var ' "$HDRF"
    echo 'var _ unsafe.Pointer'
    echo
    awk 'BEGIN{started=0}
         /^type Zzs_[a-z]* struct \{$/{lay=1}
         lay{if($0=="}"){lay=0}; next}
         /^func ZzpZzs_/{next}
         /^func /{started=1}
         /^var [^_]/{started=1}
         started{print}' "$EMIT/$m.go" \
      | sed -E "s/goxtnm([0-9])/gosrv${n}tnm\\1/g" \
      | sed -E "s/goxtmpl([0-9])/gosrv${n}tmpl\\1/g" \
      | sed "s/^func main() {\$/func Zzmodinit_srv_${n}() {/"
  } > "$DST/zz_srv_$m.go"
  awk '/^type Zzs_[a-z]* struct \{$/{lay=1} lay{print; if($0=="}"){lay=0}; next}
       /^func ZzpZzs_/{print}' "$EMIT/$m.go" >> "$DST/.layouts"
  n=$((n+1))
done

# layout structs: dedup across server modules, then DROP any layout the
# compiler packages already export (dot-imported; same emitter derivation =
# same shape).  What remains (jval & co) is declared here.
grep -h '^type Zzs_' "$SRC"/zz*/[a-z]*.go 2>/dev/null | awk '{print $2}' | sort -u > "$DST/.have_lay"
grep -h '^func ZzpZzs_' "$SRC"/zz*/[a-z]*.go 2>/dev/null \
  | sed -E 's/^func (ZzpZzs_[A-Za-z_0-9]*).*/\1/' | sort -u > "$DST/.have_zzp"
{
  echo 'package main'
  echo
  echo 'import "unsafe"'
  echo 'import "xatsgo"'
  echo
  echo 'var _ unsafe.Pointer'
  echo 'var _ = xatsgo.XATSNIL'
  echo
  # type blocks are multi-line (skip-until-}); ZzpZzs_ funcs are one line.
  awk -v have_lay="$DST/.have_lay" -v have_zzp="$DST/.have_zzp" '
    BEGIN{ while((getline l < have_lay)>0) hl[l]=1
           while((getline l < have_zzp)>0) hz[l]=1 }
    /^type Zzs_[a-z]* struct \{$/{
      nm=$2
      if(nm in seen || nm in hl){skip=1} else {seen[nm]=1; skip=0; print}
      next }
    /^func ZzpZzs_/{
      fn=$2; sub(/\(.*/,"",fn)
      if(fn in seenf || fn in hz){next}
      seenf[fn]=1; print; next }
    skip{if($0=="}"){skip=0}; next}
    {print}' "$DST/.layouts"
} > "$DST/zz_srv_layouts.go"

# the shared check-core modules + module inits: verbatim from src/tcheck/.
cp "$SRC/tcheck/zz_tchecklib.go" "$DST/zz_tchecklib.go"
cp "$SRC/tcheck/zz_lspidx.go" "$DST/zz_lspidx.go"
cp "$SRC/zz_init.go" "$DST/zz_init.go"

# the glue module: processed like an assemble.sh module (layouts stripped —
# zzbase has them; temps renamed; its trivial main renamed away).
{
  sed -n '1,/^func init/p' "$SRC/zz_init.go" | sed '$d' | sed '/^func /d'
  awk 'BEGIN{started=0}
       /^type Zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func ZzpZzs_/{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$GEMIT/xats2go_lspglue.go" \
    | sed -E "s/goxtnm([0-9])/goglutnm\\1/g" \
    | sed -E "s/goxtmpl([0-9])/goglutmpl\\1/g" \
    | sed "s/^func main() {\$/func Zzmodinit_lspglue() {/"
  printf '\nvar _ = Zzmodinit_lspglue\n'
} > "$DST/zz_lspglue.go"

# the tchk entry-point shims: forward the server's plain externs to the
# glue module's stamped Z_ symbols (extracted from the emission — the
# stamps move with the glue SATS, so this is generated every wire).
ZPL=$(grep -o '^func Z_tchkglue_prelude_load_[0-9]*' "$DST/zz_lspglue.go" | head -1 | sed 's/^func //')
ZRL=$(grep -o '^func Z_tchkglue_prelude_reload_[0-9]*' "$DST/zz_lspglue.go" | head -1 | sed 's/^func //')
ZCK=$(grep -o '^func Z_tchkglue_check_[0-9]*' "$DST/zz_lspglue.go" | head -1 | sed 's/^func //')
[ -n "$ZPL" ] && [ -n "$ZRL" ] && [ -n "$ZCK" ] || { echo "!! wire-server: glue Z_ symbols not found (load=$ZPL reload=$ZRL check=$ZCK)"; exit 1; }
{
  echo 'package main'
  echo
  echo '// GENERATED by wire-server.sh: the server-world externs forward to the'
  echo '// compiler-world glue (stamped names move with the glue SATS).'
  echo "func XATS2GO_LSP_tchk_prelude_load() any { ${ZPL}(); return nil }"
  echo
  echo "func XATS2GO_LSP_tchk_prelude_reload() any { ${ZRL}(); return nil }"
  echo
  echo "func XATS2GO_LSP_tchk_check(path string, txt string, stdinq int) any {"
  echo "	${ZCK}(path, txt, stdinq)"
  echo "	return nil"
  echo "}"
} > "$DST/zz_srv_shim.go"

# the server's extern floor (already package main; imports in-file).
# NB: the PRELUDE floor (zz_floor.go, the bare XATS2GO_* CATS leaves) is
# NOT copied — zzbase already exports the same names (assemble.sh splices
# the prelude floors into the compiler assembly); a second copy collides
# through the dot-import.  A server-referenced leaf missing from zzbase
# would surface as a loud undefined-identifier error here.
rm -f "$DST/zz_floor.go"
cp "$B/src/zz_lspfloor.go" "$DST/zz_lspfloor.go"

# main: the server module inits in assembly order (the compiler packages'
# inits run first via zz_init.go's func init()); the driver module's init
# (the serve loop) is LAST.  NO print-store flush: stdout is the protocol
# channel.
{
  echo 'package main'
  echo
  echo 'func main() {'
  i=0
  for m in $MODULES; do echo "	Zzmodinit_srv_${i}()"; i=$((i+1)); done
  echo '}'
} > "$DST/zz_srv_main.go"

( cd "$SRC" && gofmt -w lspserver >/dev/null 2>&1
  go build ${XGCFLAGS:+-gcflags "$XGCFLAGS"} -o "$B/ats3-lsp-server" ./lspserver 2> "$DST/build.err" ) \
  || { echo "!! wire-server: go build FAILED"; head -30 "$DST/build.err"; exit 1; }
echo ">> built $B/ats3-lsp-server (in-process compiler)"

# ---- cross-platform builds (pure Go, no cgo): opt in with e.g.
#   XLSP_PLATFORMS="linux/amd64 linux/arm64 darwin/amd64 windows/amd64"
# Binaries land in $B/dist/<goos>-<goarch>/; the client's package-all.sh
# stages them into per-target .vsix files.  (windows compiles but the
# XATSHOME/prelude path model is untested there.)
if [ -n "${XLSP_PLATFORMS:-}" ]; then
  for pl in $XLSP_PLATFORMS; do
    goos=${pl%%/*}; goarch=${pl#*/}
    exe=ats3-lsp-server; [ "$goos" = windows ] && exe=ats3-lsp-server.exe
    outd=$B/dist/$goos-$goarch
    mkdir -p "$outd"
    ( cd "$SRC" && GOOS=$goos GOARCH=$goarch \
        go build -o "$outd/$exe" ./lspserver 2> "$DST/build-$goos-$goarch.err" ) \
      || { echo "!! wire-server: cross build $pl FAILED"; head -10 "$DST/build-$goos-$goarch.err"; exit 1; }
    echo ">> built $outd/$exe"
  done
fi
