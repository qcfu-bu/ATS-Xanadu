////////////////////////////////////////////////////////////////////////.
//   C-PROOF STAGE-0 SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_cproof_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env (CP-MET=1, CP-UNP=2, CP-WTH=3 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "CP-MET") return 1;
  if (p === "CP-UNP") return 2;
  if (p === "CP-WTH") return 3;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_cproof_spike.cats]
////////////////////////////////////////////////////////////////////////.
