////////////////////////////////////////////////////////////////////////.
//   A-QUANT STAGE-0 SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_aquant_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env (SX-EXI=1, SX-SUB=2 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "SX-EXI") return 1;
  if (p === "SX-SUB") return 2;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_aquant_spike.cats]
////////////////////////////////////////////////////////////////////////.
