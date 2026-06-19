////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//   C1  xglobal_reset() test  -  JS-glue companion (.cats)           //.
//                                                                    //.
//   Implements each `#extern fun NAME(...) = $extnam()` in            //.
//   c1_reset_test.dats. Cat-linked BEFORE the compiled driver by      //.
//   build.sh (its require()'d consts are used by top-level vals).     //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// ---- argv access -------------------------------------------------- //
function C1_argv_count()   { return process.argv.length; }
function C1_argv_get(i0)   { return process.argv[i0]; }
//
// ---- clean-channel printing --------------------------------------- //
// The compiler prints heavy debug tracing to stderr; we keep our test
// output on stdout with a sentinel prefix so it is trivially greppable.
function C1_say(s) { process.stdout.write("[C1] " + s + "\n"); }
//
// ---- one report line ---------------------------------------------- //
// label, compiler nerror, total unbound-identifier count, count for `x`.
function C1_report(label, nerror, nunbound, nx) {
  process.stdout.write(
    "[C1] " + label
    + " | nerror=" + (nerror|0)
    + " unbound=" + (nunbound|0)
    + " x-unbound=" + (nx|0) + "\n");
}
//
////////////////////////////////////////////////////////////////////////.
// end of [c1-test/CATS/c1_reset_test.cats]
////////////////////////////////////////////////////////////////////////.
