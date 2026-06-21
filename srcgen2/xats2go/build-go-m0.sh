#!/usr/bin/env bash
########################################################################
# xats2go — milestone M0 — GREEN PIPELINE tracer bullet.
#
# SUPERSEDED.  M0 validated a STUB [go1emit] (fixed `package main`, no go
# toolchain, no oracle) against test00_xats2go.dats.  That stub was
# replaced by the real emitter at M1, and the M0-era standalone build path
# (a smaller DATS list + the stub) no longer matches the current split
# go1emit sources.  Rather than keep a dead build, this entry point now
# delegates to the reusable differential harness build-go.sh on the
# current green test (test01), so `bash build-go-m0.sh` still exits 0.
#
# For the real M2.0 pipeline + oracle, use:
#     bash srcgen2/xats2go/build-go.sh <source.dats>
#
# Usage:   bash srcgen2/xats2go/build-go-m0.sh [--force]
########################################################################
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo ">> [build-go-m0.sh] M0 stub is superseded; running build-go.sh on test01."
exec bash "$HERE/build-go.sh" \
  "$HERE/srcgen2/TEST/test01_xats2go.dats" "$@"
