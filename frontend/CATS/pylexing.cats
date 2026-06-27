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
    s = s.substring(1, s.length - 1);
  }
  s = s.replace(/\\\r?\n[ \t]*/g, "");
  return s;
}
function PYL_has_ats_ext(s) {
  s = PYL_unquote(s);
  return /\.(sats|dats|hats)$/i.test(String(s));
}
function PYL_has_hats_ext(s) {
  s = PYL_unquote(s);
  return /\.hats$/i.test(String(s));
}
// faithful #include path-resolution helper: true iff the (already-unquoted) path begins with '/'.
// An `include "PATH"` path is XATSHOME-relative; the elaborator ensures a single leading '/' so
// M3's strn_append(the_XATSHOME(), path) reconstructs the absolute path (mirroring PCCimport).
function PYL_has_leading_slash(s) {
  s = String(s);
  return s.length > 0 && s.charCodeAt(0) === 47;
}
// faithful #include: strip the single leading '/' so the path is XATSHOME-RELATIVE. The emitted
// D2Cinclude FPATH must carry the RELATIVE fnm1 (e.g. `srcgen2/HATS/x.hats`), matching stock's
// fsrch_dcurrent resolution (which is relative to the source's drpth), NOT an absolute path.
function PYL_strip_leading_slash(s) {
  s = String(s);
  return (s.length > 0 && s.charCodeAt(0) === 47) ? s.slice(1) : s;
}
// faithful #include: the CURRENT file's stadyn (0=static .psats, 1=dynamic .pdats). The driver sets
// it BEFORE lowering (mirroring stock's `f00` parse flag, which becomes the `D2Cinclude(knd0;...)`
// knd0 = the INCLUDING file's stadyn — NOT the included file's). `lower_include` reads it so an
// included file's D2Cinclude knd0 matches stock exactly. Default 0 (the static-tracer default).
var PYL_cur_stadyn = 0;
function PYL_cur_stadyn_set(n) { PYL_cur_stadyn = (Number(n) === 1) ? 1 : 0; return; }
function PYL_cur_stadyn_get() { return PYL_cur_stadyn; }
//
// Surface identifiers spell ATS '$' segments Koka-style with '/', e.g. `a0ref/get`.
// Lowering resolves those names against the existing compiler/prelude spelling.
// Keep real operator spellings alone; callers use this only for identifier names,
// but the guard prevents accidental `/` division remapping in operator paths.
function PYL_ats_name(s) {
  s = String(s);
  if (s === "/" || s === "//") return s;
  return s.split("/").join("$");
}
function PYL_is_qualified_name(s) {
  return String(s).indexOf(".") >= 0;
}
function PYL_ats_qualified_name(s) {
  s = String(s);
  return "$" + PYL_ats_name(s.split(".").join("$"));
}
function PYL_qual_head_key(s) {
  s = String(s);
  var i = s.indexOf(".");
  return i < 0 ? "" : ("$" + s.slice(0, i + 1));
}
function PYL_qual_tail_name(s) {
  s = String(s);
  var i = s.indexOf(".");
  return i < 0 ? s : s.slice(i + 1);
}
function PYL_uncapitalize(s) {
  s = String(s);
  if (s.length === 0) return s;
  return s.charAt(0).toLowerCase() + s.slice(1);
}
//
// FIXITY (Cluster B): classify an operator lexeme for the stock token kind it round-trips to.
// A name whose FIRST char is a letter or `_` is ALPHANUMERIC -> stock T_IDALP (e.g. `app`, `foo`,
// `orelse`); anything else is SYMBOLIC -> stock T_IDSYM (e.g. `+`, `**`, `<<`, `::`, `:=`). This
// mirrors stock's lexer split (lexing0: alnum idents vs symbolic idents) so the lowered D0Cfixity
// i0dnt token matches stock's exactly (the l2dump shows T_IDSYM(+) vs T_IDALP(foo)).
function PYL_is_symbolic_name(s) {
  s = String(s);
  if (s.length === 0) return false;
  var b = s.charCodeAt(0);
  var isAlpha = (b >= 65 && b <= 90) || (b >= 97 && b <= 122);
  var isUnder = (b === 95);
  return (isAlpha || isUnder) ? false : true;
}
//
// FIXITY (relative precedence): the parser encodes `OP[(±N)]` as `opr:<op>:<±N>` (e.g.
// `opr:||:+1`, `opr:+:`). These decoders split that back out for build_fixity's PRECopr2 build.
//   PYL_is_relprec(s)  : does s start with the `opr:` tag?
//   PYL_relprec_op(s)  : the reference OP (between `opr:` and the 2nd `:`).
//   PYL_relprec_num(s) : the signed-int adjustment text after the 2nd `:` ("" = no `(±N)` mod).
function PYL_is_relprec(s) { return String(s).indexOf("opr:") === 0; }
function PYL_relprec_op(s) {
  s = String(s);
  if (s.indexOf("opr:") !== 0) return "";
  var rest = s.slice(4);
  var j = rest.indexOf(":");
  return j < 0 ? rest : rest.slice(0, j);
}
function PYL_relprec_num(s) {
  s = String(s);
  if (s.indexOf("opr:") !== 0) return "";
  var rest = s.slice(4);
  var j = rest.indexOf(":");
  return j < 0 ? "" : rest.slice(j + 1);
}
//   PYL_relprec_num_is_neg(n) : is the signed-int text `n` (e.g. "+1"/"-1") negative?
//   PYL_relprec_num_digits(n) : the bare digit text of `n` (sign char stripped).
function PYL_relprec_num_is_neg(n) { return String(n).charAt(0) === "-"; }
function PYL_relprec_num_digits(n) {
  n = String(n);
  var c = n.charAt(0);
  return (c === "+" || c === "-") ? n.slice(1) : n;
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

////////////////////////////////////////////////////////////////////////.
//
// Iterative raw scanner.
//
// The original ATS scanner remains as the executable specification in
// DATS/pylexing_token.dats, but its self-tail recursion is emitted as plain
// JavaScript recursion. Large pretty-printed compiler interfaces can exceed
// Node's call stack before the parser even runs. This helper mirrors the raw
// scanner's token rules while using ordinary JS loops and an iterative list
// construction pass.
//
function PYL__postn(ntot, nrow, ncol) {
  return XATSCAPP("POSTN", [0, ntot | 0, nrow | 0, ncol | 0]);
}
function PYL__loc(src, b, e) {
  return XATSCAPP("LOCTN", [0, src, PYL__postn(b.i, b.r, b.c), PYL__postn(e.i, e.r, e.c)]);
}
function PYL__tok(src, node, b, e) {
  return XATSCAPP("PYTOKEN", [0, node, PYL__loc(src, b, e)]);
}
function PYL__node(name, tag, arg) {
  return arguments.length >= 3 ? XATSCAPP(name, [tag, arg]) : XATSCAPP(name, [tag]);
}
function PYL__list_from_array(xs) {
  var res = XATSCAPP("list_nil", [0]);
  for (var i = xs.length - 1; i >= 0; --i) {
    res = XATSCAPP("list_cons", [1, xs[i], res]);
  }
  return res;
}
function PYL__is_lower(b) { return 97 <= b && b <= 122; }
function PYL__is_upper(b) { return 65 <= b && b <= 90; }
function PYL__is_alpha(b) { return PYL__is_lower(b) || PYL__is_upper(b); }
function PYL__is_digit(b) { return 48 <= b && b <= 57; }
function PYL__is_alnum(b) { return PYL__is_alpha(b) || PYL__is_digit(b); }
function PYL__is_under(b) { return b === 95; }
function PYL__is_idcont(b) { return PYL__is_alnum(b) || PYL__is_under(b); }
function PYL__is_idstart(b) { return PYL__is_alpha(b) || PYL__is_under(b); }
function PYL__is_hex(b) {
  return PYL__is_digit(b) || (97 <= b && b <= 102) || (65 <= b && b <= 70);
}
function PYL__is_oct(b) { return 48 <= b && b <= 55; }
function PYL__is_bin(b) { return b === 48 || b === 49; }
function PYL__is_inws(b) { return b === 32 || b === 9 || b === 13 || b === 12 || b === 11; }

const PYL__KW = Object.freeze({
  "let": ["PT_KW_LET", 0],
  "mut": ["PT_KW_MUT", 1],
  "var": ["PT_KW_VAR", 2],
  "def": ["PT_KW_DEF", 3],
  "if": ["PT_KW_IF", 4],
  "elif": ["PT_KW_ELIF", 5],
  "else": ["PT_KW_ELSE", 6],
  "while": ["PT_KW_WHILE", 7],
  "for": ["PT_KW_FOR", 8],
  "in": ["PT_KW_IN", 9],
  "match": ["PT_KW_MATCH", 10],
  "case": ["PT_KW_CASE", 11],
  "break": ["PT_KW_BREAK", 12],
  "continue": ["PT_KW_CONTINUE", 13],
  "return": ["PT_KW_RETURN", 14],
  "import": ["PT_KW_IMPORT", 15],
  "from": ["PT_KW_FROM", 16],
  "type": ["PT_KW_TYPE", 17],
  "enum": ["PT_KW_ENUM", 18],
  "struct": ["PT_KW_STRUCT", 19],
  "exception": ["PT_KW_EXCEPTION", 20],
  "raise": ["PT_KW_RAISE", 21],
  "try": ["PT_KW_TRY", 22],
  "except": ["PT_KW_EXCEPT", 23],
  "as": ["PT_KW_AS", 24],
  "forall": ["PT_KW_FORALL", 25],
  "exists": ["PT_KW_EXISTS", 26],
  "at": ["PT_KW_AT", 27],
  "where": ["PT_KW_WHERE", 28],
  "private": ["PT_KW_PRIVATE", 29],
  "and": ["PT_KW_AND", 30],
  "or": ["PT_KW_OR", 31],
  "not": ["PT_KW_NOT", 32],
  "true": ["PT_TRUE", 40],
  "false": ["PT_FALSE", 41],
  // INCLUDE (faithful #include): PT_KW_INCLUDE is APPENDED LAST in the ptnode datatype (after
  // PT_QMARK=81) so adding it renumbers NOTHING; its constructor tag is 82. Keep in lock-step with
  // the SATS declaration order (a mid-datatype insert would desync every later operator tag here).
  "include": ["PT_KW_INCLUDE", 82],
  // FIXITY (Cluster B): the ATS fixity keywords kept VERBATIM (`infixl 50 +` <-> `#infixl + of 50`).
  // APPENDED LAST in the ptnode datatype (after PT_KW_INCLUDE=82) so their tags 83..87 renumber
  // NOTHING. Keep in lock-step with the SATS order — XATSCAPP discards the constructor NAME; the
  // TAG (node[0]) is the pattern-match discriminant, so a wrong tag here mis-routes the token.
  "infixl":  ["PT_KW_INFIXL", 83],
  "infixr":  ["PT_KW_INFIXR", 84],
  "prefix":  ["PT_KW_PREFIX", 85],
  "postfix": ["PT_KW_POSTFIX", 86],
  "nonfix":  ["PT_KW_NONFIX", 87],
  "infix0":  ["PT_KW_INFIX0", 88],
  // MISC (Cluster E): the ATS dyn-load + recursive-lambda keywords. APPENDED LAST in the ptnode
  // datatype (after PT_KW_INFIX0=88) so tags 89/90 renumber NOTHING. Keep in lock-step with
  // pylexing.sats's PT_KW_INITIALIZE / PT_KW_FIX constructor positions.
  "initialize": ["PT_KW_INITIALIZE", 89],
  "fix":        ["PT_KW_FIX", 90]
});

function PYL_scan_raw_iter(src, text) {
  PYL_load(text);
  var out = [];
  var i = 0, r = 0, c = 0;
  var bol = true;

  function pos() { return { i: i, r: r, c: c }; }
  function byte(k) {
    var j = i + (k | 0);
    return (j < 0 || j >= PYL__len) ? -1 : (PYL__bytes[j] | 0);
  }
  function adv1() {
    var b = byte(0);
    i += 1;
    if (b === 10) { r += 1; c = 0; }
    else { c += 1; }
  }
  function advn(n) {
    for (var k = 0; k < n; ++k) adv1();
  }
  function emit(name, tag, b, arg) {
    var node = arguments.length >= 4 ? PYL__node(name, tag, arg) : PYL__node(name, tag);
    out.push(PYL__tok(src, node, b, pos()));
  }
  function emit_fixed(name, tag, n) {
    var b = pos();
    advn(n);
    emit(name, tag, b);
  }

  function scan_ident() {
    var b = pos();
    var first = byte(0);
    function segment() {
      while (PYL__is_idcont(byte(0))) adv1();
    }
    segment();
    while (byte(0) === 47 && PYL__is_idstart(byte(1))) {
      adv1();
      segment();
    }
    var lx = PYL_slice(b.i, i);
    if (lx === "_") emit("PT_USCORE", 35, b);
    else if (PYL__is_upper(first)) emit("PT_UIDENT", 33, b, lx);
    else {
      var kw = PYL__KW[lx];
      if (kw) emit(kw[0], kw[1], b);
      else emit("PT_LIDENT", 34, b, lx);
    }
  }

  function run(pred) {
    while (pred(byte(0))) adv1();
  }

  function scan_number() {
    var b = pos();
    var b0 = byte(0), b1 = byte(1);
    if (b0 === 48 && (b1 === 120 || b1 === 88)) {
      advn(2); run(PYL__is_hex);
      emit("PT_INT", 36, b, PYL_slice(b.i, i));
    } else if (b0 === 48 && (b1 === 111 || b1 === 79)) {
      advn(2); run(PYL__is_oct);
      emit("PT_INT", 36, b, PYL_slice(b.i, i));
    } else if (b0 === 48 && (b1 === 98 || b1 === 66)) {
      advn(2); run(PYL__is_bin);
      emit("PT_INT", 36, b, PYL_slice(b.i, i));
    } else {
      run(PYL__is_digit);
      if (!(byte(0) === 46 && PYL__is_digit(byte(1)))) {
        emit("PT_INT", 36, b, PYL_slice(b.i, i));
      } else {
        adv1();
        run(PYL__is_digit);
        var be = byte(0);
        if (be === 101 || be === 69) {
          var save = pos();
          adv1();
          if (byte(0) === 43 || byte(0) === 45) adv1();
          if (PYL__is_digit(byte(0))) {
            run(PYL__is_digit);
          } else {
            i = save.i; r = save.r; c = save.c;
          }
        }
        emit("PT_FLOAT", 37, b, PYL_slice(b.i, i));
      }
    }
  }

  function scan_quoted(q) {
    var b = pos();
    adv1();
    var closed = false;
    while (true) {
      var bb = byte(0);
      if (bb < 0 || bb === 10) break;
      if (bb === 92) {
        adv1();
        if (byte(0) < 0) break;
        adv1();
      } else if (bb === q) {
        adv1();
        closed = true;
        break;
      } else {
        adv1();
      }
    }
    var lx = PYL_slice(b.i, i);
    if (!closed) emit("PT_ERROR", 80, b, lx);
    else if (q === 34) emit("PT_STRING", 38, b, lx);
    else emit("PT_CHAR", 39, b, lx);
  }

  function scan_block_comment() {
    var opening = pos();
    advn(2);
    var depth = 1;
    while (true) {
      var bb = byte(0);
      if (bb < 0) {
        var e = { i: opening.i + 2, r: opening.r, c: opening.c + 2 };
        var node = PYL__node("PT_ERROR", 80, PYL_slice(opening.i, opening.i + 2));
        out.push(PYL__tok(src, node, opening, e));
        bol = false;
        return;
      }
      if (bb === 40 && byte(1) === 42) {
        advn(2); depth += 1;
      } else if (bb === 42 && byte(1) === 41) {
        advn(2); depth -= 1;
        if (depth <= 0) return;
      } else {
        adv1();
      }
    }
  }

  function scan_op() {
    var b0 = byte(0), b1 = byte(1), b2 = byte(2);
    if (b0 === 58 && b1 === 61 && b2 === 62) emit_fixed("PT_MOVE", 57, 3);
    else if (b0 === 58 && b1 === 61 && b2 === 58) emit_fixed("PT_SWAP", 58, 3);
    else if (b0 === 61 && b1 === 61) emit_fixed("PT_EQEQ", 49, 2);
    else if (b0 === 33 && b1 === 61) emit_fixed("PT_NEQ", 50, 2);
    else if (b0 === 60 && b1 === 61) emit_fixed("PT_LTE", 52, 2);
    else if (b0 === 62 && b1 === 61) emit_fixed("PT_GTE", 54, 2);
    else if (b0 === 47 && b1 === 47) emit_fixed("PT_SLASH2", 46, 2);
    else if (b0 === 42 && b1 === 42) emit_fixed("PT_STAR2", 48, 2);
    else if (b0 === 61 && b1 === 62) emit_fixed("PT_FATARROW", 62, 2);
    else if (b0 === 45 && b1 === 62) emit_fixed("PT_ARROW", 63, 2);
    else if (b0 === 58 && b1 === 61) emit_fixed("PT_COLONEQ", 56, 2);
    else if (b0 === 43) emit_fixed("PT_PLUS", 42, 1);
    else if (b0 === 45) emit_fixed("PT_MINUS", 43, 1);
    else if (b0 === 42) emit_fixed("PT_STAR", 44, 1);
    else if (b0 === 47) emit_fixed("PT_SLASH", 45, 1);
    else if (b0 === 37) emit_fixed("PT_PERCENT", 47, 1);
    else if (b0 === 61) emit_fixed("PT_EQ", 55, 1);
    else if (b0 === 60) emit_fixed("PT_LT", 51, 1);
    else if (b0 === 62) emit_fixed("PT_GT", 53, 1);
    else if (b0 === 58) emit_fixed("PT_COLON", 64, 1);
    else if (b0 === 64) emit_fixed("PT_AT", 65, 1);
    else if (b0 === 38) emit_fixed("PT_AMP", 59, 1);
    else if (b0 === 33) emit_fixed("PT_BANG", 60, 1);
    else if (b0 === 126) emit_fixed("PT_TILDE", 61, 1);
    // QMARK-TYPE: the `?` static / top-view operator (byte 0x3f). PT_QMARK is the
    // LAST ptnode constructor (appended after PT_ERROR in pylexing.sats), so its
    // datatype tag is 81 — keep this in lock-step with the SATS declaration order.
    else if (b0 === 63) emit_fixed("PT_QMARK", 81, 1);
    else if (b0 === 124) emit_fixed("PT_BAR", 66, 1);
    else if (b0 === 44) emit_fixed("PT_COMMA", 67, 1);
    else if (b0 === 46) emit_fixed("PT_DOT", 68, 1);
    else if (b0 === 40) emit_fixed("PT_LPAREN", 69, 1);
    else if (b0 === 41) emit_fixed("PT_RPAREN", 70, 1);
    else if (b0 === 91) emit_fixed("PT_LBRACK", 71, 1);
    else if (b0 === 93) emit_fixed("PT_RBRACK", 72, 1);
    else if (b0 === 123) emit_fixed("PT_LBRACE", 73, 1);
    else if (b0 === 125) emit_fixed("PT_RBRACE", 74, 1);
    else {
      var b = pos();
      adv1();
      emit("PT_ERROR", 80, b, PYL_slice(b.i, i));
    }
  }

  while (true) {
    var bb = byte(0);
    if (bb < 0) {
      var e = pos();
      out.push(PYL__tok(src, PYL__node("PT_EOF", 79), e, e));
      return PYL__list_from_array(out);
    } else if (bb === 10) {
      var b = pos();
      adv1();
      emit("PT_NL_RAW", 75, b);
      bol = true;
    } else if (bb === 92) {
      var b1 = byte(1), b2 = byte(2);
      if (b1 === 10) advn(2);
      else if (b1 === 13 && b2 === 10) advn(3);
      else { scan_op(); bol = false; }
    } else if (bol && bb === 9) {
      var tb = pos();
      adv1();
      emit("PT_ERROR", 80, tb, PYL_slice(tb.i, i));
      bol = true;
    } else if (PYL__is_inws(bb)) {
      adv1();
    } else if (bb === 35) {
      while (byte(0) >= 0 && byte(0) !== 10) adv1();
    } else if (bb === 40 && byte(1) === 42) {
      scan_block_comment();
    } else if (PYL__is_idstart(bb)) {
      scan_ident();
      bol = false;
    } else if (PYL__is_digit(bb)) {
      scan_number();
      bol = false;
    } else if (bb === 34) {
      scan_quoted(34);
      bol = false;
    } else if (bb === 39) {
      scan_quoted(39);
      bol = false;
    } else {
      scan_op();
      bol = false;
    }
  }
}

////////////////////////////////////////////////////////////////////////.
//
// Iterative layout pass.
//
// DATS/pylayout.dats keeps the readable off-side-rule implementation, but
// generated JS recursion can overflow on pretty-printed compiler files. This
// helper mirrors that logic with ordinary JS loops over the ATS token list.
//
function PYL__token_node(tok) { return tok[1]; }
function PYL__token_loc(tok) { return tok[2]; }
function PYL__loc_src(loc) { return loc[1]; }
function PYL__loc_pbeg(loc) { return loc[2]; }
function PYL__postn_col(pos) { return pos[3] | 0; }
function PYL__synth(name, tag, loc) {
  var p = PYL__loc_pbeg(loc);
  var zloc = XATSCAPP("LOCTN", [0, PYL__loc_src(loc), p, p]);
  return XATSCAPP("PYTOKEN", [0, PYL__node(name, tag), zloc]);
}
function PYL__brk_delta(tag) {
  if (tag === 69 || tag === 71 || tag === 73) return 1;   // (, [, {
  if (tag === 70 || tag === 72 || tag === 74) return -1;  // ), ], }
  return 0;
}
function PYL_layout_iter(toks) {
  var out = [];
  var stk = [0];
  var depth = 0;
  var bol = true;
  var pend = false;
  var lastLoc = null;

  function emit_dedents(n, loc) {
    for (var k = 0; k < n; ++k) out.push(PYL__synth("PT_DEDENT", 78, loc));
  }
  function do_indent(ind, loc) {
    var top = stk.length > 0 ? stk[stk.length - 1] : 0;
    if (ind > top) {
      stk.push(ind);
      out.push(PYL__synth("PT_INDENT", 77, loc));
    } else if (ind < top) {
      while (stk.length > 0 && stk[stk.length - 1] > ind) {
        stk.pop();
        out.push(PYL__synth("PT_DEDENT", 78, loc));
      }
    }
  }

  var xs = toks;
  while (xs && xs[0] === 1) {
    var tok = xs[1];
    xs = xs[2];
    var nod = PYL__token_node(tok);
    var tag = nod[0] | 0;
    var loc = PYL__token_loc(tok);
    lastLoc = loc;

    if (tag === 79) { // PT_EOF
      if (pend) out.push(PYL__synth("PT_NEWLINE", 76, loc));
      emit_dedents(Math.max(0, stk.length - 1), loc);
      out.push(XATSCAPP("PYTOKEN", [0, PYL__node("PT_EOF", 79), loc]));
      return PYL__list_from_array(out);
    }

    if (tag === 75) { // PT_NL_RAW
      if (depth > 0) {
        // implicit line join inside brackets
      } else if (bol) {
        // blank/comment-only logical line
      } else {
        out.push(PYL__synth("PT_NEWLINE", 76, loc));
        bol = true;
        pend = false;
      }
      continue;
    }

    if (bol && depth === 0) {
      do_indent(PYL__postn_col(PYL__loc_pbeg(loc)), loc);
    }
    depth += PYL__brk_delta(tag);
    out.push(tok);
    bol = false;
    pend = true;
  }

  if (lastLoc) {
    if (pend) out.push(PYL__synth("PT_NEWLINE", 76, lastLoc));
    emit_dedents(Math.max(0, stk.length - 1), lastLoc);
    out.push(PYL__synth("PT_EOF", 79, lastLoc));
  }
  return PYL__list_from_array(out);
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
// MIRROR MODE (self-host): when env PYL_MIRROR_ROOT is set (e.g. ".../frontend/PY"),
// rebase an XATSHOME-relative `.sats` import path to the corresponding pythonic `.psats`
// under the mirror root. Returns "" when PYL_MIRROR_ROOT is unset OR the path is not a
// `.sats` (so lower_import's `fpath_rexists("")` test fails -> it falls back to loading
// the ATS `.sats`). This is how a PY/ mirror file imports its sibling pythonic interfaces
// while non-mirrored deps (the prelude) still resolve to their ATS originals.
//   path = "/srcgen2/SATS/x.sats"  ->  "<MIRROR_ROOT>/srcgen2/SATS/x.psats"
function PYL_mirror_psats(path) {
  var root = process.env.PYL_MIRROR_ROOT;
  if (!root) return "";
  var p = String(path), cand;
  if (p.endsWith(".sats")) cand = String(root) + p.slice(0, -5) + ".psats";       // interface
  else if (p.endsWith(".dats")) cand = String(root) + p.slice(0, -5) + ".pdats";  // impl (anon staload)
  else return "";
  // only redirect to the mirror if the file actually exists there (else "" -> ATS fallback).
  try { require("fs").accessSync(cand); return cand; } catch (e) { return ""; }
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
