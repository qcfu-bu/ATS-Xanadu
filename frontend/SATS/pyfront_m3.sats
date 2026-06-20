(* ****** ****** *)
(*
** M3 — Python-surface frontend: the REAL pipeline driver (SATS).
**
** The full .py -> L2/L3 path, RE-ENTRANT (fresh tr12env + self-contained d2topenv per call;
** global bootstrap once). Declared in the SATS so the symbols are stable across the DATS
** split (same discipline as pylower.sats / pyelab.sats).
**
**   pyfront_d2parsed_of_fpath(stadyn, src, text)
**     = lex (pylex_layout) -> parse (pyparse_module) -> elaborate (pyelab_module)
**       -> lower (pylower_decls) -> d2parsed_make_args
**          (empty d1topenv via tr01env_free_top(tr01env_make_nil());
**           the d2topenv via tr12env_free_top; nerror = 0 from our lowering).
**
**   pyfront_d3parsed_of_fpath(stadyn, src, text) = d3parsed_of_trans23(pyfront_d2parsed_...).
**
** `src` is the lcsrc source identity (LCSRCsome1/LCSRCfpath) the lexer stamps into every
** token's loctn, so spans flow into the L2 nodes and a type error lands on the .py span.
** `text` is the file contents. (File READ is the caller's FFI; the driver is text-in.)
**
** PURELY ADDITIVE; CALLS the compiler-as-a-library + the M1/M2/M2.5/M3 frontend passes.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
(* ****** ****** *)
//
fun
pyfront_d2parsed_of_fpath
(stadyn: sint, src: lcsrc, text: strn): d2parsed
//
fun
pyfront_d3parsed_of_fpath
(stadyn: sint, src: lcsrc, text: strn): d3parsed
//
(* ****** ****** *)
(*
end of [frontend/SATS/pyfront_m3.sats]
*)
