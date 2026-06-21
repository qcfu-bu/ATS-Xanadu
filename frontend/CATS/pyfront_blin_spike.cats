////////////////////////////////////////////////////////////////////////.
//   B-LIN STAGE-0 SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_blin_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env
//     (BL-AT=1, BL-LIN=2, BL-ADDR=3, BL-DERF=4, BL-MV=5, BL-SW=6 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "BL-AT")   return 1;
  if (p === "BL-LIN")  return 2;
  if (p === "BL-ADDR") return 3;
  if (p === "BL-DERF") return 4;
  if (p === "BL-MV")    return 5;
  if (p === "BL-SW")    return 6;
  if (p === "BL-DERF2") return 7;
  if (p === "BL-AT2")   return 8;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_blin_spike.cats]
////////////////////////////////////////////////////////////////////////.
