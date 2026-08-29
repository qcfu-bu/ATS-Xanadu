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
xats2go_lspidx — the LSP hover/def INDEX emitter (tcheck01's --index
mode).  CLAUDE-2026-08-29: one pass over the checked d3parsed emits
machine records to the given FILR (stdout), between sentinel lines:

  //==XLSPIDX-BEGIN==
  H <TAB> l0 <TAB> c0 <TAB> l1 <TAB> c1 <TAB> <type>
  D <TAB> l0 <TAB> c0 <TAB> l1 <TAB> c1 <TAB> <defpath> <TAB> dl0 <TAB> dc0 <TAB> dl1 <TAB> dc1
  //==XLSPIDX-END==

All positions are INTERNAL (0-based; columns are UTF-16 code units
under this compiler's string model).  H = a typed node in the TARGET
file (type printed in ATS3 surface syntax, single line); D = a
use-site (var/cst/con) with its definition location.  The LSP server
caches the records per (uri, version) and answers hover/definition
from the cache.
*)
(* ****** ****** *)
#staload
D3E = "./../../../SATS/dynexp3.sats"
(* ****** ****** *)
#include
"./../../../HATS/xatsopt_sats.hats"
(* ****** ****** *)
#typedef d3parsed = $D3E.d3parsed
(* ****** ****** *)
//
fun
lspidx_emit(out: FILR, dpar: d3parsed): void
//
(* ****** ****** *)
(***********************************************************************)
(* end of [xats2go_lspidx.sats] *)
(***********************************************************************)
