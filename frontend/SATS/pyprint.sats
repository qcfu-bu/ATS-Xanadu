(* ****** ****** *)
(*
** pyprint.sats — the BOOTSTRAP PRETTY-PRINTER (P2) entry.
**
** Ingests a real canonical-ATS file at level-0 (the stock parser's d0parsed AST)
** and emits our PYTHONIC surface text. The INVERSE of the frontend's lowering:
** a surface->surface transliteration over the stock L0 declaration tree.
**
** TRACER scope: the constructs in srcgen2/SATS/xstamp0.sats (abstype/abstbox,
** typedef, bodyless val/fun, symload, define, include). Anything unmapped is
** emitted as a `# TODO(pp): <construct>` line so gaps are VISIBLE.
*)
(* ****** ****** *)
//
// brings in FILR/FILEref (libcats) + the prelude, so the FILR param type resolves
// to the SAME abstract type that g_stdout()/g_stderr() return.
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/lexing0.sats"
#staload "./../../srcgen2/SATS/staexp0.sats"
#staload "./../../srcgen2/SATS/dynexp0.sats"
//
(* ****** ****** *)
//
// parse `fpath` to its stock d0parsed and write the pythonic transliteration of
// every top-level declaration to `out`. `stadyn` = 0 for a static .sats file.
//
fun
pyprint_of_fpath(stadyn: sint, fpath: strn, out: FILR): void
//
(* ****** ****** *)
(*
end of [frontend/SATS/pyprint.sats]
*)
