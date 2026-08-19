#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
#include
"./../HATS/xatsopt_sats.hats"
//
(*
regress: ILL-TYPED impltmp (the strm_vt wrapper dropped) — errors on BOTH
sides.  PIN: identical F3PERR counts AND identical diagnostic text
(binary's error dumps must match the bundle's, path-normalized).
*)
#impltmp
<xs><x0>
gseq_istrmize
  ( xs ) =
(
  gseq_strmize<xs><x0>(xs) )
//
