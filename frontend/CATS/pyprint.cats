////////////////////////////////////////////////////////////////////////.
//   BOOTSTRAP PRETTY-PRINTER (P2) — JS glue (.cats)
//   companion for frontend/DATS/pyprint.dats + pyprint_main.dats
//
//   PYPP_log*       -> process.stderr  (progress; stdout = the pythonic text)
//   PYPP_capitalize -> uppercase the first char (rule 1: type/cons names)
//   PYPP_dollar_fix -> '$' -> '/'  (rule 2; Koka-style module/name spelling)
//   PYPP_xname/PYPP_pname -> synthesized positional typaram/param names
//   PYPP_source_set / PYPP_import_stem -> normalize ATS #staload paths for import
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
function PYPP_dollar_fix(s) {
  return String(s).split("$").join("/");
}
// synthesized positional names (string-building stays in JS; the ATS side has no
// string-append). a typaram X0, X1, ...; a parameter a/b/c/d/e then x5, x6, ...
function PYPP_xname(i) { return "X" + String(i); }
function PYPP_pname(i) {
  var t = ["a", "b", "c", "d", "e"];
  return (i >= 0 && i < t.length) ? t[i] : ("x" + String(i));
}
//
var PYPP_source_path = "";
function PYPP_source_set(s) { PYPP_source_path = String(s || ""); return; }
function PYPP_unquote(s) {
  s = String(s);
  if (s.length >= 2 && s.charAt(0) === '"' && s.charAt(s.length - 1) === '"') {
    return s.substring(1, s.length - 1);
  }
  return s;
}
function PYPP_strip_ext(s) {
  s = String(s);
  return s.replace(/\.(sats|hats)$/i, "");
}
function PYPP_import_path(raw) {
  var path = require("path").posix;
  raw = PYPP_unquote(raw);
  var src = PYPP_source_path;
  var resolved = raw;
  if (raw.indexOf(".") === 0) {
    resolved = path.normalize(path.join(path.dirname(src || "."), raw));
  } else {
    resolved = path.normalize(raw);
  }
  if (path.isAbsolute(resolved)) {
    var rel = path.relative(process.cwd(), resolved);
    if (rel !== "" && rel.indexOf("..") !== 0) resolved = rel;
    else resolved = resolved.replace(/^\/+/, "");
  }
  resolved = resolved.replace(/^\/+/, "");
  return resolved;
}
function PYPP_import_stem(raw) {
  return PYPP_strip_ext(PYPP_import_path(raw));
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
