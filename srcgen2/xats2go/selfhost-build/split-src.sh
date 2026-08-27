#!/usr/bin/env bash
# split-src.sh — route the assembled selfhost source into multiple Go
# packages so no package object approaches the goobj 4GB (uint32-offset)
# linker limit.
#
# REPLACES split-src.py (2026-08-27): with every cross-package symbol
# EXPORTED AT BIRTH by the emitter (Z_<name>_<stamp> from d2vargo1 /
# d2cstimplgo1, Zzs_/ZzpZzs_ layout names, Zzmodinit_<N> module inits),
# the split is pure FILE ROUTING — no crossing-symbol analysis and no
# renaming.  Cross-package references resolve through dot-imports of all
# earlier packages; each package defines an ANCHOR var and every importer
# references it, so a dot-import is never "unused" regardless of which
# symbols a file actually touches.  A partition mistake (a backward
# reference) surfaces as a loud `go build` undefined-identifier error.
#
# Consumes src/emitter_all.go (//==ZZMOD:name==, //==ZZINIT==,
# //==ZZLAYOUTS== markers from assemble.sh), src/zz_floor.go,
# src/zz_shims.go (//==ZZSHIMS:{base,main,cc}==) and src/zz_driver.go;
# produces src/{zzbase,zzfe2,zzfe3,zzcc,zzgo}/<pkg>.go + src/zz_init.go
# + a re-headered src/zz_driver.go, then deletes the consumed inputs.
set -uo pipefail
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC=$OUT/src
ASM=$SRC/emitter_all.go

if [ ! -s "$ASM" ]; then
  echo ">> split-src: no emitter_all.go — nothing to split"
  exit 0
fi

# module lists parsed from assemble.sh itself, so the partition can never
# drift from the assembly (same trick split-src.py used).
FRONTEND=$(sed -n 's/^FRONTEND="\([^"]*\)".*$/\1/p' "$OUT/assemble.sh")
CCMODS=$(sed -n 's/^CCMODS="\([^"]*\)".*$/\1/p' "$OUT/assemble.sh")
[ -n "$FRONTEND" ] && [ -n "$CCMODS" ] || { echo "!! split-src: cannot parse FRONTEND/CCMODS from assemble.sh" >&2; exit 1; }

FE2_END=f2perr0_decl00   # last module of zzfe2 (lexing/parsing + trans01/12/2a)

# ---- module -> package map (one line per module, consumed by awk) -------
MAP=$SRC/.pkgmap
: > "$MAP"
pkg=zzfe2
for m in $FRONTEND; do
  echo "$m $pkg" >> "$MAP"
  [ "$m" = "$FE2_END" ] && pkg=zzfe3
done
for m in $CCMODS; do echo "$m zzcc" >> "$MAP"; done
# any module not in the map is the emitter's own DATS glob -> zzgo.

# ---- route the marked chunks into per-package body files ----------------
for p in zzbase zzfe2 zzfe3 zzcc zzgo main; do : > "$SRC/.body_$p"; done
awk -v src="$SRC" '
  BEGIN { while ((getline line < (src "/.pkgmap")) > 0) { split(line, a, " "); pkg[a[1]] = a[2] } }
  /^\/\/==ZZMOD:/ { nm = $0; sub(/^\/\/==ZZMOD:/, "", nm); sub(/==$/, "", nm)
                    dest = (nm in pkg) ? pkg[nm] : "zzgo"; skip = 0; next }
  /^\/\/==ZZINIT==$/    { dest = "main"; skip = 0; next }
  /^\/\/==ZZLAYOUTS==$/ { dest = "zzbase"; skip = 0; next }
  { if (dest != "") print >> (src "/.body_" dest) }
' "$ASM"
# NB the pre-marker package header (and the trailing synthetic main, which
# wire-driver.sh already removed) never reaches a body: dest starts unset.

# ---- floor -> zzbase; shims by marker -----------------------------------
if [ -s "$SRC/zz_floor.go" ]; then
  awk 'BEGIN{hdr=1} hdr && (/^func /||/^var /||/^type /||/^const /){hdr=0} !hdr{print}' \
    "$SRC/zz_floor.go" >> "$SRC/.body_zzbase"
fi
if [ -s "$SRC/zz_shims.go" ]; then
  awk -v src="$SRC" '
    /^\/\/==ZZSHIMS:base==$/ { dest = "zzbase"; next }
    /^\/\/==ZZSHIMS:cc==$/   { dest = "zzcc";   next }
    /^\/\/==ZZSHIMS:main==$/ { dest = "main";   next }
    { if (dest != "") print >> (src "/.body_" dest) }
  ' "$SRC/zz_shims.go"
fi

# ---- driver: strip its old header, keep the body ------------------------
DRVBODY=$SRC/.body_driver
awk 'BEGIN{hdr=1} hdr && (/^func /|| (/^var / && !/^var _/)){hdr=0} !hdr{print}' \
  "$SRC/zz_driver.go" > "$DRVBODY"

# ---- headers + final files ----------------------------------------------
MODNAME=selfhostemit
emit_pkg() { # $1=pkg-name  $2=body-file  $3=out-file  $4=space-list of earlier pkgs
  local pkg=$1 body=$2 outf=$3 deps=$4 d
  {
    echo "package $pkg"
    echo
    for d in $deps; do echo "import . \"$MODNAME/$d\""; done
    if grep -q 'xatsgo\.' "$body"; then echo 'import "xatsgo"'; fi
    if grep -q 'unsafe\.' "$body"; then echo 'import "unsafe"'; fi
    for lib in fmt math reflect strconv strings; do
      if grep -qE "\b$lib\." "$body"; then echo "import \"$lib\""; fi
    done
    if grep -q 'xatsgo\.' "$body"; then echo 'var _ = xatsgo.XATSNIL'; fi
    if grep -q 'unsafe\.' "$body"; then echo 'var _ unsafe.Pointer'; fi
    # dot-import anchors: reference each imported package unconditionally.
    for d in $deps; do echo "var _ = Z_anchor_$d"; done
    if [ "$pkg" != "main" ]; then echo "var Z_anchor_$pkg = 0"; fi
    echo
    cat "$body"
  } > "$outf"
}

DEPS=""
for p in zzbase zzfe2 zzfe3 zzcc zzgo; do
  mkdir -p "$SRC/$p"
  emit_pkg "$p" "$SRC/.body_$p" "$SRC/$p/$p.go" "$DEPS"
  DEPS="$DEPS $p"
done
emit_pkg main "$SRC/.body_main" "$SRC/zz_init.go" "$DEPS"
emit_pkg main "$DRVBODY" "$SRC/zz_driver.go" "$DEPS"

rm -f "$ASM" "$SRC/zz_floor.go" "$SRC/zz_shims.go" "$MAP" "$DRVBODY"
sizes=""
for p in zzbase zzfe2 zzfe3 zzcc zzgo main; do
  sizes="$sizes  $p:$(wc -l < "$SRC/.body_$p" | tr -d ' ')"
  rm -f "$SRC/.body_$p"
done
echo ">> split-src:$sizes  (routing only — crossing symbols exported at birth)"
