(* ****** ****** *)
(*
Compiler-header include for the resident LSP server.

Pulls in the stock libxatsopt header (front-end API: d3parsed_of_fil*,
the_d?parenv_pvstmap, topmap, xglobal, xatsopt flags) PLUS the few extra SATS
our harvest traversal needs but libxatsopt does not staload:
  locinfo -> postn/loctn accessors (pbeg/pend/ntot/nrow/ncol), loctn_dummy
  lexing0 -> token accessors + atext lexing chain (lxbf1/lctnize/preping)
  lexbuf0 -> lxbf1_make_strn (lex an in-memory buffer; live-on-change)
  parsing -> tokbuf + fp_d0eclsq1 + d0parsed_of_pread00  (in-memory parse)
  pread00 -> d0parsed_of_pread00                          (in-memory parse)
  dynexp0 -> d0parsed constructor + d0eclist              (in-memory parse)
  dynexp1 -> bare D1Eid0 + d1exp.node()  (unbound-id classification)
  filpath -> fpath_get_fnm1 / fnm2       (def-path + cache key)
The locinfo/lexing0/dynexp1/filpath set is exactly what
server/DATS/xats_lsp_check.dats already staloads (harvest reused verbatim); the
lexbuf0/parsing/pread00/dynexp0 set is added for the in-memory (unsaved-buffer)
validate path — building a d0parsed from the live editor text with the source
identity set to the document's REAL path (so loctns/diagnostics map back to the
real uri and relative #staloads resolve from the file's own directory).
*)
(* ****** ****** *)
//
#include "./../../../../srcgen2/HATS/libxatsopt.hats"
//
(* ****** ****** *)
//
#staload "./../../../../srcgen2/SATS/locinfo.sats"
#staload "./../../../../srcgen2/SATS/lexing0.sats"
#staload "./../../../../srcgen2/SATS/lexbuf0.sats"
#staload "./../../../../srcgen2/SATS/parsing.sats"
#staload "./../../../../srcgen2/SATS/pread00.sats"
#staload "./../../../../srcgen2/SATS/dynexp0.sats"
#staload "./../../../../srcgen2/SATS/dynexp1.sats"
#staload "./../../../../srcgen2/SATS/filpath.sats"
//
(* ****** ****** *)
(*
end of [language-server/server/resident/HATS/libxatsopt_resident.hats]
*)
