////////////////////////////////////////////////////////////////////////.
//   STAGE-0 DEPENDENT/PROOF GATING SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_dep_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env (P1=1 .. P6=6 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "P1") return 1;
  if (p === "P2") return 2;
  if (p === "P3") return 3;
  if (p === "P4") return 4;
  if (p === "P5") return 5;
  if (p === "P6") return 6;
  if (p === "P7") return 7;
  if (p === "P8") return 8;
  if (p === "P9") return 9;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_dep_spike.cats]
////////////////////////////////////////////////////////////////////////.
