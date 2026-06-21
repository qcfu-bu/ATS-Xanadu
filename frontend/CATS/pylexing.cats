////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//   M1 — Python-surface frontend: lexer JS glue (.cats)              //.
//   companion for frontend/DATS/pylexing_*.dats + pylayout.dats      //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// The FFI byte source. The ATS lexer scans the source ONE BYTE AT A TIME via
// these accessors, so that columns are counted in UTF-8 BYTES exactly as the
// compiler's location model requires (locinfo.sats: ncol in UTF-8 bytes). JS
// owns the byte buffer; the ATS side never touches the dependently-typed
// strn_get$at (whose proof obligations don't survive a transpiled scan loop).
//
// In the xats2js runtime an ATS `strn` is a JS string and `sint` is a JS number.
// PYL_load encodes the JS string to a UTF-8 byte array ONCE; PYL_byte_at returns
// the byte value 0..255 at a byte offset, or -1 at/after end-of-input. This makes
// the lexer's notion of "byte i" agree with the loctn ntot/ncol byte offsets.
//
// RE-ENTRANCY: PYL_load REPLACES the buffer wholesale on every call, so a fresh
// lex starts from a clean slate; the buffer is module-local scratch fully (re)set
// per lex and never read across calls (the ATS lexer loads-then-scans within one
// pylex_text call). No state leaks between lexes.
//
////////////////////////////////////////////////////////////////////////.
//
var PYL__bytes = null;   // Uint8Array of the current source (UTF-8)
var PYL__len   = 0;      // its byte length
//
// Load `text` (a JS string) as the current byte buffer. Returns the byte length.
function PYL_load(text) {
  var s = String(text);
  // TextEncoder gives canonical UTF-8 bytes (matches the compiler's byte columns).
  if (typeof TextEncoder !== "undefined") {
    PYL__bytes = new TextEncoder().encode(s);
  } else {
    // node fallback
    PYL__bytes = Uint8Array.from(Buffer.from(s, "utf8"));
  }
  PYL__len = PYL__bytes.length | 0;
  return PYL__len;
}
//
// Byte length of the currently-loaded source.
function PYL_len() {
  return PYL__len | 0;
}
//
// The byte (0..255) at byte offset i, or -1 if i is out of range (i.e. EOF).
function PYL_byte_at(i) {
  i = i | 0;
  if (i < 0 || i >= PYL__len) return -1;
  return PYL__bytes[i] | 0;
}
//
// GAP2 (import crash-safety): strip ONE pair of surrounding double-quotes from a string, if
// present. A `from "x" import *` keeps the quotes in the PT_STRING lexeme (`"x"`); a quoted
// module-path segment must have them removed before it is joined into a filesystem path
// (otherwise `/"x".sats` is opened, which never exists). A string without both quotes is
// returned unchanged. Pure JS, never throws.
function PYL_unquote(s) {
  s = String(s);
  if (s.length >= 2 && s.charCodeAt(0) === 34 && s.charCodeAt(s.length - 1) === 34) {
    return s.substring(1, s.length - 1);
  }
  return s;
}
//
// Slice bytes [lo, hi) of the current buffer back into a JS (UTF-8) string. Used
// to materialize a token's lexeme (identifier / literal text) for PT_*(strn).
function PYL_slice(lo, hi) {
  lo = lo | 0; hi = hi | 0;
  if (lo < 0) lo = 0;
  if (hi > PYL__len) hi = PYL__len;
  if (hi < lo) hi = lo;
  var sub = PYL__bytes.subarray(lo, hi);
  if (typeof TextDecoder !== "undefined") {
    return new TextDecoder("utf-8").decode(sub);
  } else {
    return Buffer.from(sub).toString("utf8");
  }
}
//
// Read a whole file as UTF-8 text (for the file driver / golden harness). On
// failure returns the empty string (the lexer then yields just EOF).
function PYL_readfile(path) {
  try {
    return require("fs").readFileSync(String(path), "utf8");
  } catch (e) {
    return "";
  }
}
//
// The harness file path: process.argv[2] (the .py-surface snippet to lex). The
// build script invokes the harness once per snippet with the path as argv[2].
// Returns "" when absent (harness then prints nothing useful — see build-m1.sh).
function PYL_argv_path() {
  return (process.argv && process.argv.length > 2) ? String(process.argv[2]) : "";
}
//
////////////////////////////////////////////////////////////////////////.
//
// Stdout/stderr markers for the golden harness (same idiom as pyfront.cats).
//
function PYL_print(s)   { process.stdout.write(String(s)); }
function PYL_println(s) { process.stdout.write(String(s) + "\n"); }
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pylexing.cats]
////////////////////////////////////////////////////////////////////////.
