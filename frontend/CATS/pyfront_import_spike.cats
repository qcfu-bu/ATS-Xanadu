////////////////////////////////////////////////////////////////////////.
//   M7-import (multi-file) GATING SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_import_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
// probe selector from the environment (PROBE=I0|I1). Each probe runs in its OWN
// node process so a hard XATS000_cfail in one is ISOLATED, not masking the other.
//   I0 = 0 (control: NO load — lib_double unresolved -> nerror>0 expected)
//   I1 = 1 (GO/NO-GO : LOAD lib.sats then USE lib_double -> nerror=0 = GO)
//   ALL = 9 (run both in one process)
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "I0") return 0;
  if (p === "I1") return 1;
  return 9;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_import_spike.cats]
////////////////////////////////////////////////////////////////////////.
