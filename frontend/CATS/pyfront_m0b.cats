////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//   M0b — Python-surface frontend: JS glue (.cats)                   //.
//   companion for frontend/DATS/pyfront_m0b.dats                     //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// The JS half of the M0b FFI. Each ATS3
//   `#extern fun NAME(...) = $extnam()` in pyfront_m0b.dats
// is implemented here by a same-named JS function. build-m0b.sh cat-links this
// file BEFORE the transpiled DATS so these definitions exist when the DATS
// top-level `val () = mymain_m0b()` runs.
//
// CRITICAL: the emitted user-program JS is written to process.stdout by the
// backend (i1parsed_js1emit -> g_stdout()). To keep that stdout stream clean,
// ALL M0b progress markers go to process.stderr; only the two sentinel lines
// (PYF2_mark) go to stdout, bracketing the emitted JS so build-m0b.sh can
// extract exactly the emitted text (M0a's auto-run summary also lands on
// stdout but sits OUTSIDE the sentinels and is discarded by the extractor).
//
// In the xats2js runtime, ATS `strn` is a JS string and `sint` a JS number.
//
////////////////////////////////////////////////////////////////////////.
//
function PYF2_log(s) {
  process.stderr.write(String(s) + "\n");
}
//
function PYF2_log_int(s, n) {
  process.stderr.write(String(s) + " " + String(n | 0) + "\n");
}
//
function PYF2_mark(s) {
  process.stdout.write(String(s) + "\n");
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_m0b.cats]
////////////////////////////////////////////////////////////////////////.
