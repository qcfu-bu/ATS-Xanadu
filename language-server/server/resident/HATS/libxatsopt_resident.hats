(* ****** ****** *)
(*
Compiler-header include for the resident LSP server.

Pulls in the stock libxatsopt header (front-end API: d3parsed_of_fil*,
the_d?parenv_pvstmap, topmap, xglobal, xatsopt flags) PLUS the few extra SATS
our harvest traversal needs but libxatsopt does not staload:
  locinfo -> postn/loctn accessors (pbeg/pend/ntot/nrow/ncol), loctn_dummy
  lexing0 -> token accessors
  dynexp1 -> bare D1Eid0 + d1exp.node()  (unbound-id classification)
  filpath -> fpath_get_fnm1 / fnm2       (def-path + cache key)
These are exactly the SATS server/DATS/xats_lsp_check.dats already staloads,
so the harvest code is reused verbatim.
*)
(* ****** ****** *)
//
#include "./../../../../srcgen2/HATS/libxatsopt.hats"
//
(* ****** ****** *)
//
#staload "./../../../../srcgen2/SATS/locinfo.sats"
#staload "./../../../../srcgen2/SATS/lexing0.sats"
#staload "./../../../../srcgen2/SATS/dynexp1.sats"
#staload "./../../../../srcgen2/SATS/filpath.sats"
//
(* ****** ****** *)
(*
end of [language-server/server/resident/HATS/libxatsopt_resident.hats]
*)
