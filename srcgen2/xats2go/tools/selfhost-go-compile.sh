#!/bin/sh
#
# Standalone selfhost Go compile probe. This is intentionally not wired into
# the Makefile yet; it only writes under srcgen2/BUILD.

set -eu

DEFAULT_SRCS="
srcgen2/DATS/go1emit_dynexp.dats
srcgen2/DATS/go1emit_decl00.dats
"

: "${SELFHOST_COMPILE_EXPECT_FUNCS:=}"

die() {
  echo "!! $*" >&2
  exit 1
}

repo_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
scratch="$repo_root/srcgen2/BUILD/selfhost-go-compile"
smoke_dir="$repo_root/srcgen2/BUILD/selfhost-smoke"

[ -f "$repo_root/Makefile" ] || die "repo Makefile not found from $repo_root"
[ -d "$repo_root/runtime/xatsgo" ] || die "runtime/xatsgo not found from $repo_root"

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

failures=0

for src in "$@"; do
  case "$src" in
    /*) src_path=$src ;;
    *) src_path=$repo_root/$src ;;
  esac

  [ -f "$src_path" ] || die "source not found: $src"

  name=$(basename "$src_path" .dats)
  emit="$smoke_dir/$name.go"
  pkg_dir="$scratch/$name"

  echo "======================================================================"
  echo ">> emit strict selfhost Go: $src"
  echo "======================================================================"
  if ! (cd "$repo_root" && make selfhost-strict \
    SELFHOST_SMOKE_SRC="$src_path" \
    SELFHOST_STRICT_EXPECT_FUNCS="$SELFHOST_COMPILE_EXPECT_FUNCS")
  then
    echo "!! emit/strict failed: $src" >&2
    failures=$((failures + 1))
    continue
  fi

  [ -f "$emit" ] || die "emitted Go not found: $emit"

  mkdir -p "$pkg_dir"
  cp "$emit" "$pkg_dir/$name.go"

  echo "======================================================================"
  echo ">> go build: ./$name"
  echo "======================================================================"
  if ! (cd "$scratch" && GOCACHE="$scratch/.gocache" go build -o "$scratch/bin/$name" "./$name")
  then
    echo "!! go build failed: $src" >&2
    failures=$((failures + 1))
    continue
  fi
done

[ "$failures" -eq 0 ] || die "selfhost Go compile probe failed for $failures source(s)"

echo ">> selfhost Go compile probe PASS"
