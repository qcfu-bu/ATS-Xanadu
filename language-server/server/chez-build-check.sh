#!/usr/bin/env bash
########################################################################
# WS-1a (Chez)  Checker build  -  chez-build-check.sh
#
# Builds the ATS3 LSP diagnostics checker as a CHEZ SCHEME program, using the
# xats2cz backend (cz0emit) instead of xats2js.  Analogous to build.sh, but the
# "compiler as a library" is the SELF-HOSTED Chez frontend (the cz0emit
# self-host fragments), not lib2xatsopt.js.
#
# Pipeline:
#   (1) emit xats_lsp_check.dats -> Scheme fragment via the cz0emit bundle
#       (the same bundle the self-host uses; emits the driver + the #include'd
#        shared harvest/typrint .hats now that cz0emit recurses into I0Dinclude);
#   (2) assemble: runtime + Chez glue (SCM/xats_lsp_check.scm) + the 162 frontend
#       fragments (SRCDATS order) + the checker fragment -> chez-lsp-check.scm;
#   (3) (optional) compile-file -> chez-lsp-check.so for fast startup.
#
# Run:
#   XATSHOME=... chez --script BUILD/chez/chez-lsp-check.scm \
#       <src.dats|sats> --uri <uri> --json-out <path.json>
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN2="$XATSHOME/srcgen2"
XATS2CZ="$SRCGEN2/xats2cz"
CZBUNDLE="$XATS2CZ/BUILD/xats2cz-bundle.js"
SELFHOST_SCM="$XATS2CZ/BUILD/selfhost/scm"
RUNTIME="$XATS2CZ/runtime/xats2cz_runtime.scm"

SRC_DATS="${1:-$HERE/DATS/xats_lsp_check.dats}"
GLUE="${2:-$HERE/SCM/xats_lsp_check.scm}"
OUTDIR="$HERE/BUILD/chez"
OUT="$OUTDIR/chez-lsp-check.scm"
COMPILE="${COMPILE:-1}"

mkdir -p "$OUTDIR"

if [ ! -f "$CZBUNDLE" ]; then
  echo "!! $CZBUNDLE missing — run (cd $XATS2CZ && make bundle) first" >&2; exit 1
fi
if [ ! -d "$SELFHOST_SCM" ]; then
  echo "!! self-host frontend fragments missing — run (cd $XATS2CZ && make -j8 fragments) first" >&2; exit 1
fi

echo ">> [1/3] emit checker driver -> Scheme fragment"
BODY="$OUTDIR/checker.body.scm"
ulimit -s 65520 2>/dev/null
NODE_COMPILE_CACHE= node --stack-size=60000 "$CZBUNDLE" "$SRC_DATS" 2>"$OUTDIR/emit.err" \
  | awk '/^;;==XATS2CZ-BEGIN==/{f=1;next}/^;;==XATS2CZ-END==/{f=0}f' > "$BODY"
NDEF="$(grep -c '^(define' "$BODY" 2>/dev/null || echo 0)"
echo "   -> $BODY ($NDEF top-level defines)"
if [ "$NDEF" -lt 50 ]; then
  echo "!! checker emit produced too few defines; see $OUTDIR/emit.err" >&2
  tail -20 "$OUTDIR/emit.err" >&2; exit 1
fi
if grep -q 'UNHANDLED\|BODILESS' "$BODY"; then
  echo "!! checker emit has UNHANDLED/BODILESS nodes" >&2
  grep -n 'UNHANDLED\|BODILESS' "$BODY" | head >&2; exit 1
fi

echo ">> [2/3] assemble runtime + glue + 162 frontend fragments + checker -> $OUT"
# frontend fragment order = SRCDATS in Makefile_xjsemit (top-level val initializers
# run in that order, matching the self-host assembly).
FE_ORDER="$(awk '/^SRCDATS[ ]*:?=/{c=1} c{print; if(!/\\$/)exit}' "$SRCGEN2/Makefile_xjsemit" | grep -oE '[a-z0-9_]+\.dats')"
{
  cat "$RUNTIME"
  cat "$GLUE"
  while read -r f; do
    frag="$SELFHOST_SCM/fe_${f}.scm"
    if [ -f "$frag" ]; then cat "$frag"; else echo "!! missing $frag" >&2; fi
  done <<< "$FE_ORDER"
  cat "$BODY"
} > "$OUT"
echo "   -> $OUT ($(wc -l < "$OUT") lines, $(du -h "$OUT" | awk '{print $1}'))"

if [ "$COMPILE" = "1" ]; then
  echo ">> [3/3] compile-file -> chez-lsp-check.so"
  SO="$OUTDIR/chez-lsp-check.so"
  echo "(optimize-level 2)(generate-inspector-information #f)(compile-file \"$OUT\" \"$SO\")" \
    | chez -q 2>"$OUTDIR/compile.err" \
    && echo "   -> $SO" \
    || { echo "!! compile-file failed (the raw .scm still runs via chez --script); see $OUTDIR/compile.err" >&2; tail -15 "$OUTDIR/compile.err" >&2; }
else
  echo ">> [3/3] compile skipped (COMPILE=0); run the .scm via chez --script"
fi

echo ">> done."
echo "   chez --script $OUT <src> --uri <uri> --json-out <path>"
