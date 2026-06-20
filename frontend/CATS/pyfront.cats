////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//   M0a — Python-surface frontend: JS glue (.cats)                   //.
//   companion for frontend/DATS/pyfront.dats                         //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// The JS half of the FFI idiom (primer §10.1). Every ATS3
//   `#extern fun NAME(...) = $extnam()` in pyfront.dats
// is implemented here by a same-named JS function. build-m0a.sh cat-links this
// file BEFORE the transpiled DATS so these definitions exist when the DATS
// top-level `val () = mymain_main()` runs (require is not hoisted, but these are
// plain function declarations — hoisted — and use no require()).
//
// In the xats2js runtime, ATS `strn` is a JS string and `sint` is a JS number,
// so these pass through with String()/(n|0) coercions for safety.
//
// All success markers go to STDOUT (process.stdout) so `nerror=0` is visible on
// stdout exactly as the task requires; the stock f3perr0 reporter writes to the
// g_stderr() FILR (stderr), matching the stock compiler driver.
//
////////////////////////////////////////////////////////////////////////.
//
function PYF_print(s) {
  process.stdout.write(String(s));
}
//
function PYF_println(s) {
  process.stdout.write(String(s) + "\n");
}
//
function PYF_println_int(s, n) {
  process.stdout.write(String(s) + " " + String(n | 0) + "\n");
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront.cats]
////////////////////////////////////////////////////////////////////////.
