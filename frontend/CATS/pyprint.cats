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
// argv[3] (optional): the stadyn flag, 0 = static .sats, 1 = dynamic .dats.
// Defaults to 0 (the static tracer target) when absent.
function PYPP_argv_stadyn() {
  var a = process.argv[3];
  if (a === undefined || a === null) return 0;
  var n = parseInt(String(a), 10);
  return (n === 1) ? 1 : 0;
}
//
// CAPITALIZE-SCOPING (dynamic side): a registry of names DEFINED IN THE CURRENT
// FILE (its own datatype type-names + data-constructor names). Only THESE get
// capitalized when emitted; EXTERNAL/PRELUDE names (list_cons, a0ref_*, strn, ...)
// stay verbatim so they resolve against the existing lowercase pyrt. The walk
// pre-registers a file-local name (the lowercase ATS spelling) then checks
// membership at every name-emission site.
var PYPP_local_set = {};
function PYPP_local_reset() { PYPP_local_set = {}; }
function PYPP_local_add(s) { PYPP_local_set[String(s)] = true; return; }
function PYPP_local_has(s) { return PYPP_local_set[String(s)] === true; }
//
// CAPITALIZE-ALL mode: the STATIC (.sats) tracer capitalizes EVERY type name
// (positional rule 1 — there is no lowercase-pyrt to resolve against in that
// path). The DYNAMIC (.dats) round-trip instead capitalizes ONLY file-local
// names (capall=false) so prelude names stay lowercase. Default: capall=true
// (the static path is the historical default + must stay byte-identical).
var PYPP_capall = true;
function PYPP_capall_set(b) { PYPP_capall = (b === 1 || b === true); return; }
function PYPP_capall_get() { return PYPP_capall ? 1 : 0; }
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyprint.cats]
////////////////////////////////////////////////////////////////////////.
