#!/usr/bin/env bash
########################################################################
# BOOTSTRAP PRETTY-PRINTER CORPUS AUDIT.
#
# Runs pyprint over a small default corpus or an explicit file list, then
# summarizes emitted lines, visible # TODO(pp) markers, and whether the current
# M3 executable reports `nerror (after tread3a) = 0` on the emitted file.
#
# This is a reporting harness only. It is not a self-hosting proof.
#
# Usage:
#   bash frontend/build-pp-corpus.sh
#   bash frontend/build-pp-corpus.sh --static srcgen2/SATS/xstamp0.sats
#   bash frontend/build-pp-corpus.sh --dynamic --file-list /tmp/pp-files.txt
#   bash frontend/build-pp-corpus.sh --stadyn auto FILE...
########################################################################
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XATSHOME="${XATSHOME:-$(cd "$HERE/.." && pwd)}"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
BUILD="$HERE/BUILD"
NODE="node --stack-size=8801"

PP_DATS="$HERE/DATS/pyprint.dats"
DRV_DATS="$HERE/DATS/pyprint_main.dats"
GLUE="$HERE/CATS/pyprint.cats"

MODE="auto"
OUTDIR="$BUILD/pp-corpus"
REBUILD_PP=0
REUSE_ONLY=0
DO_REPARSE=1
FILES=()

usage() {
  cat <<'EOF'
BOOTSTRAP PRETTY-PRINTER CORPUS AUDIT

Runs pyprint over a small default corpus or an explicit file list, then
summarizes emitted lines, visible # TODO(pp) markers, and whether the current
M3 executable reports `nerror (after tread3a) = 0` on the emitted file.

This is a reporting harness only. It is not a self-hosting proof.

Usage:
  bash frontend/build-pp-corpus.sh
  bash frontend/build-pp-corpus.sh --static srcgen2/SATS/xstamp0.sats
  bash frontend/build-pp-corpus.sh --dynamic --file-list /tmp/pp-files.txt
  bash frontend/build-pp-corpus.sh --stadyn auto FILE...

Options:
  --stadyn auto|static|dynamic|0|1  pyprint parse mode; auto infers .sats/.dats
  --static                          same as --stadyn static
  --dynamic                         same as --stadyn dynamic
  --file-list PATH                  read input files, one per line (# and blanks skipped)
  --out-dir PATH                    output directory (default: BUILD/pp-corpus)
  --reuse-bundle, --reuse-bundles   require existing bundles; do not build missing ones
  --rebuild-pp                      rebuild the pyprint bundle used by this audit
  --no-reparse                      skip M3 reparse and mark m3_zero=skipped
  -h, --help                        show this help
EOF
}

die() {
  echo "!! $*" >&2
  exit 1
}

normalize_mode() {
  case "$1" in
    auto) echo "auto" ;;
    static|0) echo "static" ;;
    dynamic|1) echo "dynamic" ;;
    *) echo "bad stadyn: $1" >&2; return 2 ;;
  esac
}

add_file_list() {
  local list="$1" line
  [ -f "$list" ] || die "file list not found: $list"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
      *) FILES+=("$line") ;;
    esac
  done < "$list"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stadyn)
      [ "$#" -ge 2 ] || die "--stadyn needs a value"
      MODE="$(normalize_mode "$2")" || exit 2
      shift 2
      ;;
    --stadyn=*)
      MODE="$(normalize_mode "${1#*=}")" || exit 2
      shift
      ;;
    --static)
      MODE="static"; shift
      ;;
    --dynamic)
      MODE="dynamic"; shift
      ;;
    --auto)
      MODE="auto"; shift
      ;;
    --file-list)
      [ "$#" -ge 2 ] || die "--file-list needs a path"
      add_file_list "$2"
      shift 2
      ;;
    --file-list=*)
      add_file_list "${1#*=}"
      shift
      ;;
    --out-dir)
      [ "$#" -ge 2 ] || die "--out-dir needs a path"
      OUTDIR="$2"
      shift 2
      ;;
    --out-dir=*)
      OUTDIR="${1#*=}"
      shift
      ;;
    --reuse-bundle|--reuse-bundles)
      REUSE_ONLY=1
      shift
      ;;
    --rebuild-pp)
      REBUILD_PP=1
      shift
      ;;
    --no-reparse)
      DO_REPARSE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [ "${#FILES[@]}" -eq 0 ]; then
  case "$MODE" in
    static) FILES=("srcgen2/SATS/xstamp0.sats") ;;
    dynamic) FILES=("srcgen2/DATS/filpath_drpth0.dats" "frontend/TEST/roundtrip/uppercase_values.dats" "frontend/TEST/roundtrip/local_type_alias.dats") ;;
    auto) FILES=("srcgen2/SATS/xstamp0.sats" "srcgen2/DATS/filpath_drpth0.dats" "frontend/TEST/roundtrip/uppercase_values.dats" "frontend/TEST/roundtrip/local_type_alias.dats") ;;
  esac
fi

mkdir -p "$BUILD" "$OUTDIR"

require_file() {
  [ -f "$1" ] || die "required file missing: $1"
}

transpile() {
  local src="$1" dst="$2" errf="$3" lines
  $NODE "$JSEMIT" "$src" > "$dst" 2>"$errf"
  lines="$(wc -l < "$dst")"
  echo "   transpiled $(basename "$src") -> $dst ($lines lines)"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $(basename "$src") produced too little; see $errf" >&2
    tail -60 "$errf" >&2
    return 1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$errf" 2>/dev/null; then
    echo "!! transpile of $(basename "$src") reported errck; see $errf" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$errf" | head -20 >&2
    return 1
  fi
}

PP_BUNDLE=""

build_pyprint_bundle() {
  echo ">> [1/3] build pyprint bundle for corpus audit"
  require_file "$JSEMIT"
  require_file "$LIB2OPT"
  require_file "$PP_DATS"
  require_file "$DRV_DATS"
  require_file "$GLUE"

  local s2r="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
  local s1r="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
  local runtime=(
    "$s2r/xats2js_js1emit.js"
    "$s2r/srcgen2_precats.js"
    "$s1r/srcgen1_prelude.js"
    "$s1r/srcgen1_prelude_node.js"
    "$s1r/srcgen1_xatslib_node.js"
  )
  local f
  for f in "${runtime[@]}"; do require_file "$f"; done

  local pp_trans="$BUILD/pyprint_dats.js"
  local drv_trans="$BUILD/pyprint_main_dats.js"
  transpile "$PP_DATS"  "$pp_trans"  "$BUILD/pp-corpus-transpile.err" || exit 1
  transpile "$DRV_DATS" "$drv_trans" "$BUILD/pp-corpus-main-transpile.err" || exit 1

  PP_BUNDLE="$BUILD/pp-corpus.js"
  cat "${runtime[@]}" > "$PP_BUNDLE"
  sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$PP_BUNDLE"
  cat "$GLUE" >> "$PP_BUNDLE"
  cat "$pp_trans" >> "$PP_BUNDLE"
  cat "$drv_trans" >> "$PP_BUNDLE"
  echo "   linked $(wc -l < "$PP_BUNDLE") lines into $PP_BUNDLE"
}

ensure_pyprint_bundle() {
  if [ "$REBUILD_PP" -eq 0 ]; then
    if [ -s "$BUILD/pp.js" ]; then
      PP_BUNDLE="$BUILD/pp.js"
      echo ">> [1/3] reusing $PP_BUNDLE ($(wc -l < "$PP_BUNDLE") lines)"
      return
    fi
    if [ -s "$BUILD/pp-dyn.js" ]; then
      PP_BUNDLE="$BUILD/pp-dyn.js"
      echo ">> [1/3] reusing $PP_BUNDLE ($(wc -l < "$PP_BUNDLE") lines)"
      return
    fi
    if [ -s "$BUILD/pp-corpus.js" ]; then
      PP_BUNDLE="$BUILD/pp-corpus.js"
      echo ">> [1/3] reusing $PP_BUNDLE ($(wc -l < "$PP_BUNDLE") lines)"
      return
    fi
  fi

  if [ "$REUSE_ONLY" -eq 1 ]; then
    die "no reusable pyprint bundle found in BUILD (drop --reuse-bundles or run build-pp.sh)"
  fi
  build_pyprint_bundle
}

ensure_m3_bundle() {
  [ "$DO_REPARSE" -eq 1 ] || return 0
  if [ -s "$BUILD/pyfront-m3.js" ]; then
    echo ">> [2/3] reusing $BUILD/pyfront-m3.js ($(wc -l < "$BUILD/pyfront-m3.js") lines)"
    return 0
  fi
  if [ "$REUSE_ONLY" -eq 1 ]; then
    die "$BUILD/pyfront-m3.js missing and --reuse-bundles was requested"
  fi
  echo ">> [2/3] M3 bundle missing; invoking build-m3.sh (log: BUILD/pp-corpus-m3build.log)"
  bash "$HERE/build-m3.sh" > "$BUILD/pp-corpus-m3build.log" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -80 "$BUILD/pp-corpus-m3build.log" >&2
    die "build-m3.sh failed with exit code $rc"
  fi
  [ -s "$BUILD/pyfront-m3.js" ] || die "build-m3.sh completed but pyfront-m3.js is missing"
}

stadyn_of() {
  case "$MODE" in
    static) echo 0 ;;
    dynamic) echo 1 ;;
    auto)
      case "$1" in
        *.sats) echo 0 ;;
        *.dats) echo 1 ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

stadyn_label() {
  case "$1" in
    0) echo "static" ;;
    1) echo "dynamic" ;;
    *) echo "?" ;;
  esac
}

resolve_input() {
  local p="$1"
  if [ -f "$p" ]; then
    (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
    return 0
  fi
  if [ -f "$XATSHOME/$p" ]; then
    printf '%s\n' "$p"
    return 0
  fi
  return 1
}

slug_of() {
  printf '%s' "$1" \
    | sed -E 's#^\./##; s#[^A-Za-z0-9._-]+#_#g; s#_+#_#g; s#^_+##; s#_+$##'
}

nerror_from_log() {
  grep -oE "nerror \(after tread3a\) = [0-9]+" "$1" 2>/dev/null \
    | grep -oE "[0-9]+$" \
    | tail -1
}

ensure_pyprint_bundle
ensure_m3_bundle

SUMMARY="$OUTDIR/summary.tsv"
: > "$SUMMARY"
printf 'stadyn\tinput\tpyprint_rc\temitted_lines\ttodo_pp\tm3_nerror\tm3_zero\temitted_file\n' >> "$SUMMARY"

echo ">> [3/3] PP corpus audit"
echo ">> mode=$MODE  files=${#FILES[@]}  out=$OUTDIR"
echo ">> NOTE: reporting harness only; this does not claim full self-hosting."
if [ "$DO_REPARSE" -eq 1 ]; then
  echo ">> NOTE: m3_zero reflects the current M3 CLI reparse reaching tread3a nerror=0."
else
  echo ">> NOTE: M3 reparse disabled by --no-reparse."
fi

printf '%-8s %-58s %5s %7s %8s %8s %s\n' \
  "stadyn" "input" "lines" "TODOpp" "m3_nerr" "m3_0" "emitted"

TOTAL=0
PP_FAIL=0
M3_ZERO=0
TODO_TOTAL=0

for input0 in "${FILES[@]}"; do
  TOTAL=$((TOTAL + 1))
  stadyn="$(stadyn_of "$input0")" || die "cannot infer stadyn for $input0; pass --static or --dynamic"
  label="$(stadyn_label "$stadyn")"
  input="$(resolve_input "$input0")" || die "input file not found: $input0"
  slug="$(slug_of "$input0")"
  [ -n "$slug" ] || slug="input_$TOTAL"
  if [ "$stadyn" -eq 0 ]; then pp_ext="psats"; else pp_ext="pdats"; fi

  outpp="$OUTDIR/${slug}.pp.$pp_ext"
  pperr="$OUTDIR/${slug}.pyprint.err"
  rplog="$OUTDIR/${slug}.m3-reparse.log"

  (cd "$XATSHOME" && $NODE "$PP_BUNDLE" "$input" "$stadyn" > "$outpp" 2>"$pperr")
  pprc=$?
  if [ "$pprc" -ne 0 ]; then PP_FAIL=$((PP_FAIL + 1)); fi

  if [ -f "$outpp" ]; then
    lines="$(wc -l < "$outpp")"
    todos="$(grep -c '# TODO(pp)' "$outpp" 2>/dev/null || true)"
  else
    lines=0
    todos=0
  fi
  TODO_TOTAL=$((TODO_TOTAL + todos))

  m3_nerr="skipped"
  m3_zero="skipped"
  if [ "$DO_REPARSE" -eq 1 ] && [ -s "$outpp" ]; then
    (cd "$XATSHOME" && $NODE "$BUILD/pyfront-m3.js" "$outpp" > "$rplog" 2>&1)
    m3_nerr="$(nerror_from_log "$rplog" || true)"
    if [ -z "$m3_nerr" ]; then
      m3_nerr="?"
      m3_zero="no"
    elif [ "$m3_nerr" = "0" ]; then
      m3_zero="yes"
      M3_ZERO=$((M3_ZERO + 1))
    else
      m3_zero="no"
    fi
  elif [ "$DO_REPARSE" -eq 1 ]; then
    m3_nerr="?"
    m3_zero="no"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$label" "$input0" "$pprc" "$lines" "$todos" "$m3_nerr" "$m3_zero" "$outpp" >> "$SUMMARY"

  printf '%-8s %-58s %5s %7s %8s %8s %s\n' \
    "$label" "$input0" "$lines" "$todos" "$m3_nerr" "$m3_zero" "$outpp"
done

echo "----------------------------------------------------------------------"
echo ">> summary tsv: $SUMMARY"
echo ">> files audited: $TOTAL"
echo ">> total # TODO(pp): $TODO_TOTAL"
if [ "$DO_REPARSE" -eq 1 ]; then
  echo ">> M3 reparse reached nerror=0: $M3_ZERO / $TOTAL"
fi
if [ "$PP_FAIL" -ne 0 ]; then
  echo "!! pyprint failed for $PP_FAIL file(s); see $OUTDIR/*.pyprint.err" >&2
  exit 1
fi
echo ">> PP-CORPUS: COMPLETE (audit report only)"
