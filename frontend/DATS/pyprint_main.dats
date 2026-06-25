(* ****** ****** *)
(*
** pyprint_main.dats — the bootstrap pretty-printer DRIVER.
**
** Runs pyprint_of_fpath("srcgen2/SATS/xstamp0.sats", stdout): parses the real
** canonical-ATS interface to the stock L0 AST and emits our PYTHONIC surface text
** to STDOUT (the build script redirects it to BUILD/xstamp0.pp.psats).
**
** PURELY ADDITIVE: only CALLS the compiler-as-a-library (lib2xatsopt).
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
#staload "./../../srcgen2/SATS/staexp0.sats"
#staload "./../../srcgen2/SATS/dynexp0.sats"
//
#staload "./../SATS/pyprint.sats"
//
(* ****** ****** *)
//
#extern fun PYPP_log(s: strn): void = $extnam()
#extern fun PYPP_argv_path((*0*)): strn = $extnam()
#extern fun PYPP_argv_stadyn((*0*)): sint = $extnam()
//
(* ****** ****** *)
//
fun
mymain_pyprint((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
// argv[2] if given, else the default tracer target.
val arg = PYPP_argv_path()
val fpath = if arg = "" then "srcgen2/SATS/xstamp0.sats" else arg
// argv[3] if given: stadyn flag (0 = static .sats, 1 = dynamic .dats).
val stadyn = PYPP_argv_stadyn()
//
val () = (PYPP_log("[pyprint] L0->pythonic for: "); PYPP_log(fpath))
//
val out = g_stdout<>()
// stadyn: 0 = a STATIC .sats interface file, 1 = a DYNAMIC .dats file.
val () = pyprint_of_fpath(stadyn, fpath, out)
//
in
  PYPP_log("[pyprint] done (pythonic written to stdout)")
end // end of [mymain_pyprint]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_pyprint()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyprint_main.dats]
*)
