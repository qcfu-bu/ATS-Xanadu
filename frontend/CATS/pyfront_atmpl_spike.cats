////////////////////////////////////////////////////////////////////////.
//   A-TEMPLATE GATING SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_atmpl_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env (T1=1 .. T4=4 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "T1") return 1;
  if (p === "T2") return 2;
  if (p === "T3") return 3;
  if (p === "T4") return 4;
  if (p === "T5") return 5;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_atmpl_spike.cats]
////////////////////////////////////////////////////////////////////////.
