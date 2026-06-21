#!/usr/bin/env bash
########################################################################
# xats2go — milestone M1 — WALKING SKELETON ("Hello World").
#
# As of M2.0 this is a THIN WRAPPER over the reusable differential harness
# build-go.sh, pinned to the M1 test source (test01_xats2go.dats).  The
# full M1 pipeline + oracle now lives in build-go.sh; this script is kept
# so the documented `bash build-go-m1.sh` entry point still works.
#
#   test01_xats2go.dats  (strn_print + the_print_store_log flush)
#     -> xats2go -> .go -> go build/vet/run -> stdout
#     -> xats2js -> .js -> node          -> stdout
#     -> assert byte-equal (differential oracle)
#
# Usage:   bash srcgen2/xats2go/build-go-m1.sh [--force]
########################################################################
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/build-go.sh" \
  "$HERE/srcgen2/TEST/test01_xats2go.dats" "$@"
