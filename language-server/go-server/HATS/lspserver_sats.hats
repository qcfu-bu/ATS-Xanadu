(* ****** ****** *)
(*
lspserver_sats.hats — the ONE shared staload manifest of the server.

EVERY server DATS (modules and driver alike) includes this file so that
each separate emission loads the SAME SATS set in the SAME order: the
compiler's stamps are deterministic in that order, which is what makes
the per-module Go emissions link by stamped names at assembly.

DISCIPLINE: append new SATS at the END; a mid-list insertion (or any
mid-file SATS edit) shifts stamps for every module — tools/build.sh
re-emits everything when any SATS/HATS changes, so builds stay correct
either way, but appends keep diffs and stamps tame.
*)
(* ****** ****** *)
//
#staload "./../SATS/lsp_floor.sats"
#staload "./../SATS/lsp_util.sats"
#staload "./../SATS/lsp_json.sats"
#staload "./../SATS/lsp_frame.sats"
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lspserver_sats.hats] *)
(***********************************************************************)
