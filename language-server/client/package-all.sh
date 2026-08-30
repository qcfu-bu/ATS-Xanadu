#!/usr/bin/env bash
# package-all.sh — one platform-specific .vsix per target, each shipping
# exactly ONE server binary (the in-process compiler, ~190 MB -> ~12 MB
# compressed).
#
# The native (darwin-arm64) binary comes from tools/build.sh; the cross
# binaries from wire-server.sh with e.g.
#   XLSP_PLATFORMS="darwin/amd64 linux/amd64 linux/arm64 windows/amd64" \
#     bash srcgen2/xats2go/selfhost-build/wire-server.sh
#
# NB windows COMPILES (pure Go) but the XATSHOME/prelude path model is
# untested there; darwin-arm64 is the only human-verified platform.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
B=../go-server/BUILD
TARGETS="${1:-darwin-arm64 darwin-x64 linux-x64 linux-arm64 win32-x64}"

npm run bundle

built=0
for t in $TARGETS; do
  case $t in
    darwin-arm64) src=$B/ats3-lsp-server ;;
    darwin-x64)   src=$B/dist/darwin-amd64/ats3-lsp-server ;;
    linux-x64)    src=$B/dist/linux-amd64/ats3-lsp-server ;;
    linux-arm64)  src=$B/dist/linux-arm64/ats3-lsp-server ;;
    win32-x64)    src=$B/dist/windows-amd64/ats3-lsp-server.exe ;;
    *) echo "!! unknown target $t"; exit 1 ;;
  esac
  if [ ! -f "$src" ]; then
    echo "!! $t: missing $src (wire-server.sh with XLSP_PLATFORMS) — SKIPPED"
    continue
  fi
  rm -rf server-dist && mkdir server-dist
  cp "$src" server-dist/
  npx vsce package --target "$t" --out "ats3-lsp-client-$t.vsix"
  built=$((built+1))
done
echo ">> $built platform vsix package(s) built"
# leave the native binary staged (the F5 dev flow expects server-dist/)
rm -rf server-dist && mkdir server-dist
cp "$B/ats3-lsp-server" server-dist/ 2>/dev/null || true
