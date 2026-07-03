(* ****** ****** *)
(* ****** ****** *)
(*
HX-2022-06-06:
For ATS3/XATSOPT
*)
(* ****** ****** *)
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/gbas000.sats"
#staload
"srcgen1/prelude/SATS/gord000.sats"
#staload
"srcgen1/prelude/SATS/gnum000.sats"
#staload
"srcgen1/prelude/SATS/gseq000.sats"
//
(*
HX-late/CLAUDE-2026-07:
The dpre chain INCLUDES srcgen1/prelude/DATS/{gmap000,genv000}.dats, whose
declarations live in the SATS below — without them every use of the genv
template families (list_map$e1nv_vt, list_foritm$e1nv, ...) and the gmap
interface fails NAME resolution (D2Enone1) and the enclosing decls are
errck-erased.
*)
#staload
"srcgen1/prelude/SATS/gmap000.sats"
#staload
"srcgen1/prelude/SATS/genv000.sats"
#staload
"srcgen1/prelude/SATS/gras000.sats"
#staload
"srcgen1/prelude/SATS/grasn00.sats"
//
(* ****** ****** *)
(*
#staload
"srcgen1/prelude/SATS/gfor000.sats"
#staload
"srcgen1/prelude/SATS/gfun000.sats"
*)
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/bool000.sats"
#staload
"srcgen1/prelude/SATS/char000.sats"
#staload
"srcgen1/prelude/SATS/gint000.sats"
#staload
"srcgen1/prelude/SATS/gflt000.sats"
//
#staload
"srcgen1/prelude/SATS/strn000.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/arrn000.sats"
#staload
"srcgen1/prelude/SATS/arrn001.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/list000.sats"
#staload
"srcgen1/prelude/SATS/optn000.sats"
#staload
"srcgen1/prelude/SATS/strm000.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/synoug0.sats"
//
#staload
"srcgen1/prelude/SATS/tupl000.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/VT/gseq000_vt.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/VT/strn000_vt.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/VT/arrn000_vt.sats"
#staload
"srcgen1/prelude/SATS/VT/arrn001_vt.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/VT/list000_vt.sats"
#staload
"srcgen1/prelude/SATS/VT/optn000_vt.sats"
//
#staload
"srcgen1/prelude/SATS/VT/strm000_vt.sats"
#staload
"srcgen1/prelude/SATS/VT/strm001_vt.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/prelude/SATS/VT/synoug0_vt.sats"
//
#staload
"srcgen1/prelude/SATS/VT/tupl000_vt.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#staload
"srcgen1/xatslib/libcats/SATS/libcats.sats"
//
(* ****** ****** *)
//
#staload
"srcgen1/xatslib/libcats/SATS/synoug0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
#staload
"srcgen1/xatslib/githwxi/SATS/genv000.sats"
*)
//
(* ****** ****** *)
//
#staload
"srcgen1/xatslib/githwxi/SATS/githwxi.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_HATS_xatsopt_sats.hats] *)
(***********************************************************************)
