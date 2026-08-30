(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(*
xats2go_lspglue — the resident LSP server's IN-PROCESS check entry
points (M6).  CLAUDE-2026-08-29: the server modules live in the
repo-root GO prelude world and CANNOT staload the compiler SATS (the
srcgen1 prelude world) — mixing the preludes detonates template
resolution.  This module lives on the COMPILER side of that fence and
exports two string-only entry points as stamped Z_ symbols;
wire-server.sh generates the Go shim that the server's plain
XATS2GO_LSP_* externs forward to.  Results (the captured report text
and the --index records) return via the runtime stash
(Xats_XATS2GO_lsp_stash_rep/idx -> the server floor's take_rep/idx).
*)
(* ****** ****** *)
#include
"./../../../HATS/xatsopt_sats.hats"
(* ****** ****** *)
//
(* prelude + flags, once per process (tchk_prelude_load) *)
fun
tchkglue_prelude_load((*void*)): void
//
(*
check ONE file in-process, under the runtime capture window: runs
tchk_check (with per-check eviction), then stashes the captured
report text and the index records for the server floor to collect.
txt is the live buffer when stdinq > 0.
*)
fun
tchkglue_check
(fpth: strn, txt: strn, stdinq: sint): void
//
(* ****** ****** *)
(***********************************************************************)
(* end of [xats2go_lspglue.sats] *)
(***********************************************************************)
