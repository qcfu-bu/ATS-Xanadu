#!/usr/bin/env bash
########################################################################
# RESIDENT LSP server (Chez)  -  chez-build-resident.sh
#
# Builds the resident in-process ATS3 LSP server as a CHEZ program: the cz0emit-
# compiled resident driver (which #includes the shared harvest/typrint .hats),
# linked with the self-hosted Chez frontend fragments + the Scheme glue
# (SCM/xats_lsp_resident.scm — a hand-written LSP JSON-RPC transport replacing
# vscode-languageserver).
#
# Pyfront (.pdats/.psats) is deferred: the driver's pyfront references resolve
# lazily on Chez (only evaluated if a .pdats is opened), so the core links
# without the pyfront fragments.
#
# Run:  XATSHOME=... chez --script BUILD/chez/chez-lsp-resident.so --stdio
########################################################################
set -uo pipefail
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN2="$XATSHOME/srcgen2"; XATS2CZ="$SRCGEN2/xats2cz"
CZBUNDLE="$XATS2CZ/BUILD/xats2cz-bundle.js"
SELFHOST_SCM="$XATS2CZ/BUILD/selfhost/scm"
RUNTIME="$XATS2CZ/runtime/xats2cz_runtime.scm"
SRC_DATS="${1:-$HERE/resident/DATS/xats_lsp_resident.dats}"
GLUE="${2:-$HERE/SCM/xats_lsp_resident.scm}"
# BUILD_TAG suffixes the outputs so a candidate build (e.g. BUILD_TAG=.wip) never
# clobbers the deployed chez-lsp-resident.so until it has passed smoke.
OUTDIR="$HERE/BUILD/chez"; OUT="$OUTDIR/chez-lsp-resident${BUILD_TAG:-}.scm"; SO="$OUTDIR/chez-lsp-resident${BUILD_TAG:-}.so"
COMPILE="${COMPILE:-1}"
# Portable LSP modules (Stage 4b+): each .dats is emitted as its own cz fragment
# and linked into the assembly; the driver #staloads the matching .sats.
LSP_MODULES="${LSP_MODULES:-xats_lsp_json xats_lsp_uri xats_lsp_u16 xats_lsp_dedup xats_lsp_index xats_lsp_proj}"
mkdir -p "$OUTDIR"

[ -f "$CZBUNDLE" ] || { echo "!! $CZBUNDLE missing — (cd $XATS2CZ && make bundle)"; exit 1; }
[ -d "$SELFHOST_SCM" ] || { echo "!! frontend fragments missing — (cd $XATS2CZ && make -j8 fragments)"; exit 1; }

echo ">> [1/3] emit resident driver -> Scheme fragment"
BODY="$OUTDIR/resident.body.scm"
ulimit -s 65520 2>/dev/null
NODE_COMPILE_CACHE= node --stack-size=60000 "$CZBUNDLE" "$SRC_DATS" 2>"$OUTDIR/emit.err" \
  | awk '/^;;==XATS2CZ-BEGIN==/{f=1;next}/^;;==XATS2CZ-END==/{f=0}f' > "$BODY"
NDEF="$(grep -c '^(define' "$BODY" 2>/dev/null || echo 0)"
echo "   -> $BODY ($NDEF top-level defines)"
if [ "$NDEF" -lt 80 ]; then echo "!! resident emit too small; see $OUTDIR/emit.err"; tail -20 "$OUTDIR/emit.err"; exit 1; fi
grep -q 'UNHANDLED\|BODILESS' "$BODY" && { echo "!! UNHANDLED/BODILESS in emit"; grep -n 'UNHANDLED\|BODILESS' "$BODY" | head; exit 1; }

echo ">> [1b/3] emit portable LSP module fragments"
MOD_BODIES=()
for m in $LSP_MODULES; do
  msrc="$HERE/resident/DATS/${m}.dats"; mbody="$OUTDIR/${m}.body.scm"; merr="$OUTDIR/${m}.emit.err"
  [ -f "$msrc" ] || { echo "!! module source missing: $msrc"; exit 1; }
  NODE_COMPILE_CACHE= node --stack-size=60000 "$CZBUNDLE" "$msrc" 2>"$merr" \
    | awk '/^;;==XATS2CZ-BEGIN==/{f=1;next}/^;;==XATS2CZ-END==/{f=0}f' > "$mbody"
  mdef="$(grep -c '^(define' "$mbody" 2>/dev/null || echo 0)"
  echo "   -> $m ($mdef defines)"
  if [ "$mdef" -lt 1 ]; then echo "!! module $m emit empty; see $merr"; tail -15 "$merr"; exit 1; fi
  if grep -q 'UNHANDLED\|BODILESS' "$mbody"; then echo "!! UNHANDLED/BODILESS in $m"; grep -n 'UNHANDLED\|BODILESS' "$mbody" | head; exit 1; fi
  MOD_BODIES+=("$mbody")
done

echo ">> [2/3] assemble runtime + glue + 162 frontend fragments + LSP modules + resident driver -> $OUT"
FE_ORDER="$(awk '/^SRCDATS[ ]*:?=/{c=1} c{print; if(!/\\$/)exit}' "$SRCGEN2/Makefile_xjsemit" | grep -oE '[a-z0-9_]+\.dats')"
{
  cat "$RUNTIME"
  cat "$GLUE"
  while read -r f; do frag="$SELFHOST_SCM/fe_${f}.scm"; [ -f "$frag" ] && cat "$frag" || echo "!! missing $frag" >&2; done <<< "$FE_ORDER"
  for mb in "${MOD_BODIES[@]}"; do cat "$mb"; done
  cat "$BODY"
} > "$OUT"
echo "   -> $OUT ($(wc -l < "$OUT") lines, $(du -h "$OUT" | awk '{print $1}'))"

if [ "$COMPILE" = "1" ]; then
  echo ">> [3/3] compile-file -> chez-lsp-resident.so"
  echo "(optimize-level 2)(generate-inspector-information #f)(compile-file \"$OUT\" \"$SO\")" | chez -q 2>"$OUTDIR/compile.err" \
    && echo "   -> $SO ($(du -h "$SO" | awk '{print $1}'))" \
    || { echo "!! compile-file failed; see $OUTDIR/compile.err"; tail -20 "$OUTDIR/compile.err"; exit 1; }
else
  echo ">> [3/3] compile skipped (COMPILE=0)"
fi
echo ">> done.  run: XATSHOME=$XATSHOME chez --script $SO --stdio"
