#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
#include
"./../HATS/xatsopt_sats.hats"
//
(*
regress: malformed PATTERN — the PARSE-level (pread00) reporter path.
//
PIN: identical PREAD00-ERROR output, not just F3PERR0.
//
Every other probe here errors at level 2/3 only, so all of them stayed
green while the driver was dropping the parse-level report entirely
(the driver called [d3parsed_of_fildats], which builds the [d0parsed]
and hands it to trans03 without ever calling [d0parsed_fpemsg]).
This probe is the one that goes red if that reporter is unwired again.
*)
fun f0(x: sint): sint = case+ x of | ) => 0
//
