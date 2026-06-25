#!/usr/bin/env bash
########################################################################
# build-lib2xatsopt.sh
#
# Rebuilds srcgen2/lib/lib2xatsopt.js = the ATS3 compiler front-end,
# compiled to JS and ready to be cat-linked under a driver program.
#
# This reproduces srcgen2/Makefile_xjsemit's `lib2xatsopt` target, but
#   (1) uses the prebuilt _opt1 transpiler in xassets/JS (the Makefile's
#       default xats2js_jsemit00_ats2.js does NOT exist in this tree), and
#   (2) drives the per-file `jsxtnm -> jsxNtnm` namespacing in bash.
#
# The per-file SED transform (Makefile_xjsemit:282-285) gives each
# compiler .dats its own template-name namespace `jsx<N>tnm`; without it,
# template instantiations from different files would collide.
#
# Runs ~6-9 min (162 files transpiled). Output: srcgen2/lib/lib2xatsopt.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
SRCGEN2="$XATSHOME/srcgen2"
# Use the jsemit00 transpiler (the generation the stock Makefile targets as
# XATS2JS_JSEMIT00). The jsemit01_*_opt1 asset, while fine for the FFI spike,
# REGRESSES on ~23 closure-template instantiations in trans01_staexp.dats
# (e.g. list_map$e1nv_vt): it emits an unresolved `XATSDAPP(...debug AST...)`
# blob containing `//` from locations, which is invalid JS (parsed as a regex
# at load time). jsemit00 resolves all templates correctly.
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
BUILD="$SRCGEN2/BUILD/JS"
OUTLIB="$SRCGEN2/lib/lib2xatsopt.js"
mkdir -p "$BUILD" "$SRCGEN2/lib"

# Extract the SRCDATS list straight from the authoritative Makefile so we
# never drift from the compiler's own file/ordering.  (Portable to bash 3.2:
# no `mapfile`; iterate the awk output directly — filenames have no spaces.)
DATS_LIST="$(awk '/^SRCDATS :=/{f=1;next} f&&/^$/{f=0} f{gsub(/\\/,"");for(i=1;i<=NF;i++) if($i ~ /\.dats$/) print $i}' "$SRCGEN2/Makefile_xjsemit")"
NTOTAL="$(printf '%s\n' "$DATS_LIST" | grep -c .)"

echo ">> building lib2xatsopt.js from $NTOTAL .dats files"
: > "$OUTLIB"
n=0
for f in $DATS_LIST; do
  n=$((n+1))
  src="$SRCGEN2/DATS/$f"
  base="${f%.dats}"
  out0="$BUILD/${base}_dats_out0.js"
  if [ ! -f "$src" ]; then echo "   !! MISSING $src" ; continue; fi
  # transpile (heavy debug + proofread errors of *dependencies* go to stderr;
  # clean JS goes to stdout). We do NOT trust $? / PERR0-ERROR here: those
  # errors are in the prelude/staloaded deps as loaded, not in our output.
  node --stack-size=8801 "$JSEMIT" "$src" > "$out0" 2>/dev/null
  # per-file namespacing: jsxtnm -> jsx<N>tnm  (N = file index, matching the
  # Makefile's $(words $(NFILE)) counter which starts at 1).
  sed -e "s/jsxtnm/jsx${n}tnm/g" "$out0" >> "$OUTLIB"
  printf "   [%3d/%3d] %s (%d lines)\n" "$n" "$NTOTAL" "$f" "$(wc -l < "$out0")"
done
echo ">> done: $OUTLIB ($(wc -l < "$OUTLIB") lines)"
