#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
#include
"./../HATS/xatsopt_sats.hats"
//
(*
regress: the vt-signature template impl (gseq000's gseq_istrmize VERBATIM)
that the selfhost binary errck'd while the JS bundle checked it clean —
root cause: unifier entity-equality bridged to pointer identity (fixed in
statyp2_tmplib).  PIN: both sides compile with F3PERR=0, byte-equal Go.
*)
#impltmp
<xs><x0>
gseq_istrmize
  ( xs ) =
(
  strm_vt_istrmize0
  (gseq_strmize<xs><x0>(xs)) )
//
