////////////////////////////////////////////////////////////////////////.
//   BOOTSTRAP PRETTY-PRINTER (P2) — JS glue (.cats)
//   companion for frontend/DATS/pyprint.dats + pyprint_main.dats
//
//   PYPP_log*       -> process.stderr  (progress; stdout = the pythonic text)
//   PYPP_capitalize -> uppercase the first char (rule 1: type/cons names)
//   PYPP_dollar_fix -> '$' -> '_'  (rule 2; design target '/', see DATS note)
//   PYPP_has_dollar -> did the name contain '$' (for the divergence TODO note)
//   PYPP_xname/PYPP_pname -> synthesized positional typaram/param names
//   PYPP_argv_path  -> process.argv[2] or ""
////////////////////////////////////////////////////////////////////////.
//
function PYPP_log(s) { process.stderr.write(String(s)); }
//
function PYPP_capitalize(s) {
  s = String(s);
  if (s.length === 0) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}
//
// DESIGN target is Koka-style '$'->'/', but our lexer doesn't accept '/' in an
// identifier yet (it lexes as division), so the TRACER emits '$'->'_' (matching
// the reference _ucase translation that reaches nerror=0). Switching to '/' is
// lexer/parser-breadth work, not a P2 pretty-printer concern.
function PYPP_dollar_fix(s) {
  return String(s).split("$").join("_");
}
function PYPP_has_dollar(s) {
  return String(s).indexOf("$") >= 0;
}
//
// synthesized positional names (string-building stays in JS; the ATS side has no
// string-append). a typaram X0, X1, ...; a parameter a/b/c/d/e then x5, x6, ...
function PYPP_xname(i) { return "X" + String(i); }
function PYPP_pname(i) {
  var t = ["a", "b", "c", "d", "e"];
  return (i >= 0 && i < t.length) ? t[i] : ("x" + String(i));
}
//
function PYPP_argv_path() {
  var a = process.argv[2];
  return (a === undefined || a === null) ? "" : String(a);
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyprint.cats]
////////////////////////////////////////////////////////////////////////.
