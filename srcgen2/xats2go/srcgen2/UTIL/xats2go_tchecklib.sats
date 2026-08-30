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
xats2go_tchecklib — the CALLABLE check core (M6, in-process LSP).
CLAUDE-2026-08-29: the body of xats2go_tcheck01's mymain_main/work,
extracted so BOTH the CLI driver (xats2go_tcheck01, process-per-check)
and the resident LSP server (in-process, prelude loaded once) run the
IDENTICAL pipeline and reporters:

  d0parsed (from fpath, or from TEXT attributed to fpath)
    -> pread00 report -> trans03 -> tread3a/trtmp3b/trtmp3c/t3read0
    -> f3perr0 report + dependency reports -> [--index] lspidx_emit
    -> EVICTION of the checked file + its freshly-loaded (shr = 0)
       non-stdlib dependencies from the four per-file caches
       (the_d1parenv/d2parenv/d3parenv topmaps + the_d3tmpenv).

The eviction is what makes repeated in-process checks equivalent to
process-per-check (the ats3-compiler-one-shot constraint): each check
re-elaborates exactly its own workspace closure while the pvsloaded
prelude stays warm and immutable.  In the one-shot CLI the eviction
runs too (last, after all reports) and is unobservable.

All error text goes to [errout]; index records go to [idxout].  The
CLI passes g_stderr()/g_stdout<>() — byte-identical to the pre-M6
driver.  The resident server brackets the call with the runtime's
capture window (XATS2GO_capture_begin/end) so the report-channel
prints that bypass [errout] (the flipped default channel — see the
window note in xats2go_tcheck01) land in the same captured string.
*)
(* ****** ****** *)
#include
"./../../../HATS/xatsopt_sats.hats"
(* ****** ****** *)
//
(*
load the prelude + the driver flag set, once per process: fixity defs
(the_fxtyenv_pvsl00d), the trans12 prelude store (the_tr12env_pvsl01d),
and the SAME xatsopt flags as xats2go_goemit01 (the flags select which
CATS files xatsopt_dpre includes; the diagnostic surface must match the
CLI driver byte-for-byte).  Progress lines print to the default
channel exactly as the CLI driver printed them.
*)
fun
tchk_prelude_load((*void*)): void
//
(*
check ONE file: [txt] is used when stdinq > 0 (the live buffer,
attributed to fpth); otherwise the file is read from disk.  stadyn
follows the extension (.sats = 0).  idxq > 0 emits the LSP index
records to [idxout].
*)
fun
tchk_check
( fpth: strn
, txt: strn
, stdinq: sint
, idxq: sint
, errout: FILR
, idxout: FILR): void
//
(* ****** ****** *)
(***********************************************************************)
(* end of [xats2go_tchecklib.sats] *)
(***********************************************************************)
