#!/bin/sh
#
# Standalone selfhost Go compile probe. This is intentionally not wired into
# the Makefile yet; it only writes under srcgen2/BUILD.

set -eu

DEFAULT_SRCS="
srcgen2/DATS/intrep1.dats
srcgen2/DATS/intrep1_print0.dats
srcgen2/DATS/intrep1_utils0.dats
srcgen2/DATS/go1emit_tytab0.dats
srcgen2/DATS/go1emit_byref0.dats
srcgen2/DATS/trxi0i1.dats
srcgen2/DATS/trxi0i1_myenv0.dats
srcgen2/DATS/trxi0i1_dynexp.dats
srcgen2/DATS/trxi0i1_decl00.dats
srcgen2/DATS/xats2go_myenv0.dats
srcgen2/DATS/go1emit_styp0.dats
srcgen2/DATS/go1emit_utils0.dats
srcgen2/DATS/go1emit_dynexp.dats
srcgen2/DATS/go1emit_decl00.dats
srcgen2/DATS/go1emit.dats
srcgen2/DATS/xats2go_tmplib.dats
"

: "${SELFHOST_COMPILE_EXPECT_FUNCS:=}"
: "${SELFHOST_COMPILE_MODE:=package}"
: "${SELFHOST_COMPILE_ACTION:=test}"

die() {
  echo "!! $*" >&2
  exit 1
}

usage() {
  cat >&2 <<EOF
usage: $0 [--package|--per-source] [srcgen2/DATS/file.dats ...]

Environment:
  SELFHOST_COMPILE_MODE=package|per-source  default: package
  SELFHOST_COMPILE_ACTION=test|build         package mode default: test
  SELFHOST_COMPILE_EXPECT_FUNCS="..."        forwarded to make selfhost-strict
EOF
}

repo_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
scratch="$repo_root/srcgen2/BUILD/selfhost-go-compile"
smoke_dir="$repo_root/srcgen2/BUILD/selfhost-smoke"
package_dir="$scratch/package"

[ -f "$repo_root/Makefile" ] || die "repo Makefile not found from $repo_root"
[ -d "$repo_root/runtime/xatsgo" ] || die "runtime/xatsgo not found from $repo_root"

mode="$SELFHOST_COMPILE_MODE"
action="$SELFHOST_COMPILE_ACTION"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      mode=package
      shift
      ;;
    --per-source)
      mode=per-source
      shift
      ;;
    --test)
      action=test
      shift
      ;;
    --build)
      action=build
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

case "$mode" in
  package|per-source) ;;
  *) die "SELFHOST_COMPILE_MODE must be package or per-source, got: $mode" ;;
esac

case "$action" in
  test|build) ;;
  *) die "SELFHOST_COMPILE_ACTION must be test or build, got: $action" ;;
esac

if [ "$#" -eq 0 ]; then
  # shellcheck disable=SC2086
  set -- $DEFAULT_SRCS
fi

command -v make >/dev/null 2>&1 || die "'make' not on PATH"
command -v go >/dev/null 2>&1 || die "'go' not on PATH"

rm -rf "$scratch"
mkdir -p "$scratch"
mkdir -p "$scratch/.gocache" "$scratch/bin"

cat > "$scratch/go.mod" <<EOF
module xats2go_selfhost_probe

go 1.26

require xatsgo v0.0.0

replace xatsgo => $repo_root/runtime/xatsgo
EOF

echo ">> selfhost Go compile scratch: $scratch"
echo ">> mode: $mode"

failures=0
first_failure_class=
first_failure_detail=

record_failure() {
  class=$1
  detail=$2
  failures=$((failures + 1))
  if [ -z "$first_failure_class" ]; then
    first_failure_class=$class
    first_failure_detail=$detail
  fi
}

emit_strict() {
  src=$1
  src_path=$2
  min_funcs=1

  case "$(basename "$src_path")" in
    xats2go_tmplib.dats)
      # Template-only support file in GO_DATS: today the emitter preserves the
      # declarations as comments, so it is intentionally zero-function Go.
      min_funcs=0
      ;;
  esac

  echo "======================================================================"
  echo ">> emit strict selfhost Go: $src"
  echo "======================================================================"
  (cd "$repo_root" && make selfhost-strict \
    SELFHOST_SMOKE_SRC="$src_path" \
    SELFHOST_SMOKE_MIN_FUNCS="$min_funcs" \
    SELFHOST_STRICT_EXPECT_FUNCS="$SELFHOST_COMPILE_EXPECT_FUNCS")
}

copy_with_inert_main() {
  emit=$1
  dest=$2
  inert=$3

  awk -v repl="func selfhost_inert_main_${inert}() {" '
    /^func[ \t]+main[ \t]*\([ \t]*\)[ \t]*\{[ \t]*$/ {
      print repl
      next
    }
    { print }
  ' "$emit" > "$dest"
}

if [ "$mode" = package ]; then
  mkdir -p "$package_dir"
  cat > "$package_dir/selfhost_compile_test.go" <<'EOF'
package main

import "testing"

func TestCompile(t *testing.T) {}
EOF
fi

for src in "$@"; do
  case "$src" in
    /*) src_path=$src ;;
    *) src_path=$repo_root/$src ;;
  esac

  [ -f "$src_path" ] || die "source not found: $src"

  name=$(basename "$src_path" .dats)
  emit="$smoke_dir/$name.go"

  if ! emit_strict "$src" "$src_path"
  then
    echo "!! emit/strict failed: $src" >&2
    record_failure "emit/strict" "$src"
    continue
  fi

  if [ ! -f "$emit" ]; then
    echo "!! emitted Go not found: $emit" >&2
    record_failure "missing emitted Go" "$src"
    continue
  fi

  if [ "$mode" = package ]; then
    dest="$package_dir/$name.go"
    if ! copy_with_inert_main "$emit" "$dest" "$name"; then
      echo "!! copy/main suppression failed: $src" >&2
      record_failure "copy/main suppression" "$src"
      continue
    fi
  else
    pkg_dir="$scratch/$name"
    mkdir -p "$pkg_dir"
    cp "$emit" "$pkg_dir/$name.go"

    echo "======================================================================"
    echo ">> go build: ./$name"
    echo "======================================================================"
    if ! (cd "$scratch" && GOCACHE="$scratch/.gocache" go build -o "$scratch/bin/$name" "./$name")
    then
      echo "!! go build failed: $src" >&2
      record_failure "go build" "$src"
      continue
    fi
  fi
done

if [ "$mode" = package ] && [ "$failures" -eq 0 ]; then
  echo "======================================================================"
  echo ">> go $action: ./package"
  echo "======================================================================"
  if [ "$action" = test ]; then
    if ! (cd "$scratch" && GOCACHE="$scratch/.gocache" go test ./package); then
      echo "!! go test failed: ./package" >&2
      record_failure "go test" "./package"
    fi
  else
    cat > "$package_dir/selfhost_compile_main.go" <<'EOF'
package main

func main() {}
EOF
    if ! (cd "$scratch" && GOCACHE="$scratch/.gocache" go build -o "$scratch/bin/package" ./package); then
      echo "!! go build failed: ./package" >&2
      record_failure "go build" "./package"
    fi
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo ">> first failure class: $first_failure_class ($first_failure_detail)" >&2
  die "selfhost Go compile probe failed for $failures step(s)"
fi

echo ">> selfhost Go compile probe PASS"
