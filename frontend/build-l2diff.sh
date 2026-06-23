#!/usr/bin/env bash
########################################################################
# L2DIFF — Pythonic-ATS round-trip FAITHFULNESS gate (structural L2 compare).
#
# For a canonical ATS file F this proves the round-trip is FAITHFUL by comparing
# the RAW lowered L2 (the d2parsed BEFORE the post-passes) two ways:
#
#   stock L2   = trans02_from_fpath(F)                  -- the STOCK compiler's L2
#   pythonic L2= pyfront_d2parsed_of_fpath(pyprint(F))  -- OUR frontend's L2 from
#                                                          the pretty-printed pythonic
#
# Steps:
#   (a) pyprint F  ->  BUILD/<base>.l2diff.p{d,s}ats   (the pythonic surface text)
#   (b) run BUILD/pyfront-l2dump.js twice:
#         stock   F            -> the stock raw-L2 node dump
#         pyfront <pythonic>   -> our  raw-L2 node dump
#   (c) NORMALIZE both dumps (strip locations, canonicalize stamps; see below)
#   (d) diff.  Exit 0 = structurally identical = round-trip provably FAITHFUL.
#       A non-zero diff PINPOINTS the diverging construct (and on a typecheck-green
#       file is a REAL finding: we lower differently from stock but it typechecks).
#
# NORMALIZATION (the crux). The node dump (d2parsed_fprint) is one long line of
# D2C.../D2E.../S2E... nodes; d2con/d2cst/d2var print as `name(STAMP)` /`name[STAMP]`.
# We canonicalize the incidental, non-structural differences:
#   1. one node per line  : a newline before every Uppercase node constructor, so the
#                           diff localizes to the diverging node (purely cosmetic).
#   2. locations          : `LCSRCsome1(...)@(...)` and bare `@(N(line=..,offs=..)..)`
#                           -> `@LOC`. The source PATH (F vs the .pdats) and the
#                           line:col spans are incidental — only structure matters.
#   3. abs paths          : `FPATH(/abs/.../x.sats)` -> `FPATH(@P/x.sats)` (machine path).
#   4. stamps             : `name(NNNNN)` / `name[NNNNN]` -- the d2var/d2con/d2cst stamp
#                           ids differ between stock & pyfront (assigned in different
#                           orders). Map each DISTINCT stamp to a sequential id BY FIRST
#                           OCCURRENCE within each dump, so identical structures yield
#                           identical canonical stamps. Prelude d2csts print by NAME
#                           (already stable) and are untouched; only the numeric id in
#                           the parens/brackets is canonicalized.
#   5. case-fold the leading char of bracket-stamp names (itm/Itm, x0/X0) -- pyprint's
#                           capitalize-scoping flips the FIRST letter of a synthesized
#                           binder name; the binder is structurally the same var.
#
# REUSES BUILD/pyfront-l2dump.js (build it via build-l2dump.sh) and the pyprint
# bundle BUILD/pp.js / BUILD/pp-dyn.js (build via build-pp.sh / build-pp-dyn.sh).
# PURELY ADDITIVE: writes only into BUILD/.
#
# Usage:
#   bash frontend/build-l2diff.sh <F.sats|F.dats> [stadyn] [--pythonic P] [--triage]
#       stadyn: 0 = static .sats (default), 1 = dynamic .dats. (Inferred from the
#       extension when omitted: .dats -> 1, else 0.)
#       --triage: cascade-immune root-divergence map (strips stamps; see below).
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
NODE="node --stack-size=8801"

L2DUMP="$BUILD/pyfront-l2dump.js"

F="${1:-}"
if [ -z "$F" ]; then
  echo "usage: bash frontend/build-l2diff.sh <F.sats|F.dats> [stadyn] [--pythonic <P>] [--triage]" >&2
  exit 2
fi
# --pythonic <P> : use the GIVEN hand-written pythonic P for the pyfront side instead
# of pyprint(F). Lets us validate the harness mechanics (normalization -> zero diff)
# against a known-faithful hand translation, independent of pyprint's current fidelity.
#
# --triage : CASCADE-IMMUNE mode. The default mode CANONICALIZES stamps by first
# occurrence, so identical structures compare equal — but ONE inserted/removed node
# shifts every later stamp, cascading a single root divergence into thousands of changed
# lines (e.g. filpath_drpth0: one #define->value-binding extra binder -> ~9965 diff
# lines). Triage instead STRIPS stamps entirely (name(NNNN)->name(#), name[NNNN]->[#]),
# so an inserted/removed node is just ONE diff line — the ROOT structural divergences
# stay visible, not buried under a stamp cascade. Use --triage to MAP the diverging
# constructs; use the default canonicalize mode for exact-faithfulness proof (it can
# distinguish a stamp-level structural difference that stripping would hide).
HANDPY=""
TRIAGE=0
for i in "$@"; do
  if [ "$i" = "--pythonic" ]; then HANDPY="__next__"; continue; fi
  if [ "$HANDPY" = "__next__" ]; then HANDPY="$i"; continue; fi
  if [ "$i" = "--triage" ]; then TRIAGE=1; fi
done
# stadyn: explicit numeric arg2, else inferred from the extension.
if [ "${2:-}" = "0" ] || [ "${2:-}" = "1" ]; then
  STADYN="$2"
else
  case "$F" in
    *.dats) STADYN=1 ;;
    *)      STADYN=0 ;;
  esac
fi
# pick the pyprint bundle + the pythonic extension by stadyn.
if [ "$STADYN" = "1" ]; then
  PPBUNDLE="$BUILD/pp-dyn.js"; PEXT="pdats"
else
  PPBUNDLE="$BUILD/pp.js";     PEXT="psats"
fi

BASE="$(basename "$F")"; BASE="${BASE%.*}"

if [ ! -s "$L2DUMP" ]; then
  echo "!! $L2DUMP missing — run 'bash frontend/build-l2dump.sh' first." >&2
  exit 1
fi
if [ -z "$HANDPY" ] && [ ! -s "$PPBUNDLE" ]; then
  echo "!! $PPBUNDLE missing — run 'bash frontend/build-pp.sh' (static) or" >&2
  echo "   'bash frontend/build-pp-dyn.sh' (dynamic) first to build the pyprint bundle." >&2
  echo "   (or pass --pythonic <P> to supply a hand-written pythonic and skip pyprint.)" >&2
  exit 1
fi

PY="$BUILD/${BASE}.l2diff.${PEXT}"
STOCK_RAW="$BUILD/${BASE}.l2diff.stock.raw"
PYF_RAW="$BUILD/${BASE}.l2diff.pyfront.raw"
# triage normalizes/diffs into separate files so the two modes never clobber each other.
if [ "$TRIAGE" = "1" ]; then
  STOCK_N="$BUILD/${BASE}.l2triage.stock.norm"
  PYF_N="$BUILD/${BASE}.l2triage.pyfront.norm"
  DIFF="$BUILD/${BASE}.l2triage.diff"
  MODELABEL="L2TRIAGE (stamps STRIPPED, cascade-immune)"
else
  STOCK_N="$BUILD/${BASE}.l2diff.stock.norm"
  PYF_N="$BUILD/${BASE}.l2diff.pyfront.norm"
  DIFF="$BUILD/${BASE}.l2diff.diff"
  MODELABEL="L2DIFF (stamps CANONICALIZED, exact-faithfulness)"
fi

########################################################################
# (a) the pythonic surface text: pyprint(F), OR the given hand-written --pythonic P
########################################################################
if [ -n "$HANDPY" ]; then
  echo ">> [a] using hand-written pythonic $HANDPY (pyprint skipped)"
  cp "$HANDPY" "$PY"
else
  echo ">> [a] pyprint $F (stadyn=$STADYN) -> $PY"
  ( cd "$XATSHOME" && $NODE "$PPBUNDLE" "$F" "$STADYN" > "$PY" 2>"$BUILD/${BASE}.l2diff.pp.err" )
fi
if [ ! -s "$PY" ]; then
  echo "!! no pythonic produced; see $BUILD/${BASE}.l2diff.pp.err" >&2
  [ -f "$BUILD/${BASE}.l2diff.pp.err" ] && tail -10 "$BUILD/${BASE}.l2diff.pp.err" >&2
  exit 1
fi
echo "   pythonic: $(wc -l < "$PY") lines, $(wc -c < "$PY") bytes"

########################################################################
# (b) raw-L2 dumps: stock from F, pyfront from the pythonic
########################################################################
echo ">> [b] raw-L2 dumps (stock from F ; pyfront from the pythonic)"
( cd "$XATSHOME" && $NODE "$L2DUMP" stock   "$F"  "$STADYN" > "$STOCK_RAW" 2>"$BUILD/${BASE}.l2diff.stock.err" )
( cd "$XATSHOME" && $NODE "$L2DUMP" pyfront "$PY" "$STADYN" > "$PYF_RAW"   2>"$BUILD/${BASE}.l2diff.pyfront.err" )
if ! grep -q "^D2PARSED(" "$STOCK_RAW"; then
  echo "!! stock dump produced no D2PARSED tree; see $BUILD/${BASE}.l2diff.stock.err" >&2
  tail -10 "$BUILD/${BASE}.l2diff.stock.err" >&2
  exit 1
fi
if ! grep -q "^D2PARSED(" "$PYF_RAW"; then
  echo "!! pyfront dump produced no D2PARSED tree; see $BUILD/${BASE}.l2diff.pyfront.err" >&2
  tail -10 "$BUILD/${BASE}.l2diff.pyfront.err" >&2
  exit 1
fi
echo "   stock raw:   $(wc -c < "$STOCK_RAW") bytes"
echo "   pyfront raw: $(wc -c < "$PYF_RAW") bytes"

########################################################################
# (c) normalize both dumps (see the header for the rationale of each step)
########################################################################
normalize() {
  # stdin: one-line D2PARSED(...) dump ; stdout: normalized, one node per line.
  # Portable BSD sed + BSD awk only (no gawk gensub / no \l).
  sed -E \
    -e 's/LCSRCsome1\([^)]*\)@\([^)]*\)/@LOC/g' \
    -e 's/@\([0-9]+\(line=[0-9]+,offs=[0-9]+\)--[0-9]+\(line=[0-9]+,offs=[0-9]+\)\)/@LOC/g' \
    -e 's/LCSRCsome1\([^)]*\)/@SRC/g' \
    -e 's#FPATH\(/[^)]*/([^/)]+)\)#FPATH(@P/\1)#g' \
    -e 's/,D2Cnone0\(\)//g' \
    -e 's/TEQD2EXPsome\(T_[A-Za-z0-9_]*\([^;)]*\);/TEQD2EXPsome(@BINDTOK;/g' \
  | awk '
      # 1. one node per line: newline before each Uppercase node constructor token
      #    (D2..., S2..., G1..., T2..., A2..., X2..., TEQ..., TRCD..., LAB..., FPATH,
      #     D2PARSED). A node constructor is an Uppercase-led identifier immediately
      #    followed by "(". Purely cosmetic — localizes the diff to the diverging node.
      {
        line = $0
        gsub(/[A-Z][A-Za-z0-9_]*\(/, "\n&", line)
        n = split(line, parts, "\n")
        for (i = 1; i <= n; i++) if (parts[i] != "") print parts[i]
      }
    ' \
  | awk -v triage="$TRIAGE" '
      # 4 + 5. stamps. Two modes (see header), selected by `triage`:
      #
      #   CANONICALIZE (triage=0, exact-faithfulness proof):
      #     - bracket-stamp  name[NNNN]  -> [SK]  (DROP the synthesized binder name:
      #         itm/Itm/X0/x0/... are positional/internal vars whose name + leading-case
      #         vary with order + pyprint capitalize-scoping; the canonical id identifies
      #         the var structurally).
      #     - paren-stamp    name(NNNN)  -> name(SK)  (KEEP the symbol name — d2cst/d2con
      #         names are stable + load-bearing; canonicalize only the numeric stamp id).
      #     K = a per-dump sequential id assigned BY FIRST OCCURRENCE, so identical
      #     structures yield identical canonical stamps. The hazard: one inserted/removed
      #     node shifts every later K -> a single root divergence cascades to thousands
      #     of changed lines.
      #
      #   TRIAGE (triage=1, cascade-immune ROOT-divergence map):
      #     - bracket-stamp  name[NNN]  -> [#]       (DROP the name, as in canonicalize:
      #         synthesized binder names + leading-case vary, itm/Itm/X0/x0)
      #     - paren-stamp    name(NNN)  -> name(#)   (KEEP the symbol name)
      #     Stamps are STRIPPED to a single placeholder, NOT numbered, and with NO
      #     digit guard — so even the LOW (1-2 digit) d2var binder stamps x(2)/y(6)/...
      #     collapse. That is the whole point: the #define cascade is precisely a chain
      #     of low binder stamps shifted by +1 from one extra binder; numbering them
      #     (canonicalize) or guarding them (3-digit) re-exposes the shift, stripping
      #     them does not. An inserted/removed node is then just ONE diff line.
      #     A paren/bracket-number is a STAMP only when it directly follows an
      #     IDENTIFIER name (so bare label/literal parens like ;35) are never matched),
      #     and we still SKIP the token-literal carriers whose paren holds a real value,
      #     not a stamp: T_INT01(0) (an int literal), LABint(1) (a tuple label),
      #     T_TRCD10(2) (a token record arity). Those are matched by the T_*/LABint
      #     name and left intact.
      #
      #   The CANONICALIZE branch keeps the original 3-digit guard (token lengths like
      #   T_STRN1_clsd("..";29) are never touched there because they are not
      #   name-anchored stamps).
      {
        line = $0
        if (triage == "1") {
          # name-anchored, no digit guard; skip literal carriers (T_*, LABint).
          out = ""; rest = line
          while (match(rest, /[A-Za-z_][A-Za-z0-9_$]*\[[0-9]+\]|[A-Za-z_][A-Za-z0-9_$]*\([0-9]+\)/)) {
            pre = substr(rest, 1, RSTART-1)
            tok = substr(rest, RSTART, RLENGTH)
            # split the name from the [..] / (..) bracket (bp>0 means a bracket-stamp).
            bp = index(tok, "[")
            if (bp > 0) { nm = substr(tok, 1, bp-1) } else { nm = substr(tok, 1, index(tok, "(")-1) }
            if (nm ~ /^T_/ || nm == "LABint" || nm == "LABext") {
              # literal carrier: the number is a value, not a stamp -> keep it.
              out = out pre tok
            } else if (bp > 0) {
              # bracket-stamp: DROP the synthesized binder name (case-flips), keep [#].
              out = out pre "[#]"
            } else {
              # paren-stamp: KEEP the symbol name (d2cst/d2con names load-bearing).
              out = out pre nm "(#)"
            }
            rest = substr(rest, RSTART+RLENGTH)
          }
          print out rest
        } else {
          out = ""; rest = line
          while (match(rest, /[A-Za-z_][A-Za-z0-9_$]*\[[0-9][0-9][0-9]+\]|\([0-9][0-9][0-9]+\)/)) {
            pre = substr(rest, 1, RSTART-1)
            tok = substr(rest, RSTART, RLENGTH)
            if (substr(tok,1,1) == "(") {
              num = substr(tok, 2, length(tok)-2)
              if (!(num in seen)) seen[num] = ++ctr
              out = out pre "(S" seen[num] ")"
            } else {
              b = index(tok, "[")
              num = substr(tok, b+1, length(tok)-b-1)
              if (!(num in seen)) seen[num] = ++ctr
              out = out pre "[S" seen[num] "]"
            }
            rest = substr(rest, RSTART+RLENGTH)
          }
          print out rest
        }
      }
    '
}
echo ">> [c] normalize both dumps"
normalize < "$STOCK_RAW" > "$STOCK_N"
normalize < "$PYF_RAW"   > "$PYF_N"
echo "   stock norm:   $(wc -l < "$STOCK_N") lines"
echo "   pyfront norm: $(wc -l < "$PYF_N") lines"

########################################################################
# (d) diff
########################################################################
echo ">> [d] structural diff (stock vs pyfront) [$MODELABEL]"
if diff -u "$STOCK_N" "$PYF_N" > "$DIFF" 2>&1; then
  echo "======================================================================"
  echo ">> $MODELABEL: FAITHFUL — zero structural diff for $BASE"
  echo ">>   stock L2 (trans02_from_fpath) == pythonic L2 (pyfront(pyprint($BASE)))"
  echo "======================================================================"
  exit 0
else
  NLINES="$(grep -cE '^[+-]' "$DIFF")"
  echo "======================================================================"
  echo ">> $MODELABEL: DIVERGENT — $NLINES changed lines for $BASE (see $DIFF)"
  echo ">>   the round-trip is NOT structurally faithful here; first diverging nodes:"
  grep -E '^[+-][^+-]' "$DIFF" | head -20 | sed 's/^/     /'
  echo "======================================================================"
  exit 1
fi
