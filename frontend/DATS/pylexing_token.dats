(* ****** ****** *)
(*
** M1 — Python-surface frontend: the RAW SCANNER (DATS).
**
** Scans Python-surface source (a strn, UTF-8) into a raw `pytoken` list with real
** `loctn` spans (0-based; ncol counted in UTF-8 BYTES; newline resets ncol). This
** is the level BELOW layout: physical newlines appear as PT_NL_RAW; the layout
** pass (pylayout.dats) rewrites them into NEWLINE/INDENT/DEDENT.
**
** The byte source is the FFI buffer (frontend/CATS/pylexing.cats): PYL_load sets
** the current source; PYL_byte_at(i) reads byte i (0..255) or -1 at EOF; PYL_slice
** materializes a lexeme. This gives exact UTF-8 byte columns and avoids the
** dependently-typed strn_get$at in a scan loop.
**
** PURE per call: pylex_text loads the text, scans it to completion, returns a fresh
** list. No module-global lexer state persists across calls (plan §6.2).
**
** Lexical authority: SURFACE-GRAMMAR.md §5.1 (lexical), §5.6 (operators), §5 (case
** convention + keyword set). CPython-standard choices are noted inline where the
** doc is silent on a minor detail.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
//
(* ****** ****** *)
//
// ---- FFI byte source (frontend/CATS/pylexing.cats) -------------------------
//
#extern fun PYL_load(text: strn): sint = $extnam()
#extern fun PYL_len((*0*)): sint = $extnam()
#extern fun PYL_byte_at(i: sint): sint = $extnam()
#extern fun PYL_slice(lo: sint, hi: sint): strn = $extnam()
//
(* ****** ****** *)
//
// accessors for the token pair
//
#implfun pytoken_get_node(tok) = let val+ PYTOKEN(nod, _) = tok in nod end
#implfun pytoken_get_loctn(tok) = let val+ PYTOKEN(_, loc) = tok in loc end
//
(* ****** ****** *)
//
// ---- a cursor over the byte buffer -----------------------------------------
//
// The position is threaded BY VALUE through the recursion (functional) as a plain
// 3-tuple `cur = @(ntot, nrow, ncol)`: ntot = total byte offset; nrow = 0-based
// line; ncol = 0-based byte column within the line. (A tuple, not a record — the
// Xanadu surface uses @(...) tuples freely; an anonymous record literal is awkward.)
// Field order is FIXED here: .0 = ntot, .1 = nrow, .2 = ncol.
//
#typedef cur = @(sint, sint, sint)
//
fun cur_init((*0*)): cur = @(0, 0, 0)
//
fun cur_ntot(c: cur): sint = c.0
fun cur_nrow(c: cur): sint = c.1
fun cur_ncol(c: cur): sint = c.2
//
// the postn at a cursor
fun cur_postn(c: cur): postn =
  postn_make_int3(c.0, c.1, c.2)
//
// the byte at the cursor (or -1 at EOF)
fun cur_byte(c: cur): sint = PYL_byte_at(c.0)
// the byte k ahead (lookahead; -1 at EOF)
fun cur_byte_at(c: cur, k: sint): sint = PYL_byte_at(c.0 + k)
//
// advance one byte. A newline ('\n' = 10) bumps nrow and resets ncol to 0;
// any other byte bumps ncol. (We advance PAST the '\n' so the next line starts at
// col 0. CR '\r' (13) is treated as an ordinary byte that does not reset the line;
// a CRLF therefore advances ncol on the CR then resets on the LF — CPython-style.)
fun cur_adv(c: cur): cur = let
  val b = cur_byte(c)
in
  if b = 10 (* '\n' *)
    then @(c.0 + 1, c.1 + 1, 0)
    else @(c.0 + 1, c.1, c.2 + 1)
end
//
// advance n bytes (n known to contain no newline; used for fixed-width operators)
fun cur_advn(c: cur, n: sint): cur =
  if n <= 0 then c else cur_advn(cur_adv(c), n - 1)
//
(* ****** ****** *)
//
// ---- boolean helpers (EAGER and/or) ----------------------------------------
//
// Short-circuit `&&`/`||` are special parser forms (fixity-aliased to andalso/
// orelse) NOT visible to a standalone DATS via the prelude headers. All our boolean
// operands are PURE comparisons (no side effects / no exceptions), so EAGER and/or
// is semantically identical — we use these prefix helpers and avoid `&&`/`||`.
//
fun band(x: bool, y: bool): bool = (if x then y else false)
fun band3(x: bool, y: bool, z: bool): bool = (if x then (if y then z else false) else false)
fun bor(x: bool, y: bool): bool = (if x then true else y)
//
(* ****** ****** *)
//
// ---- ASCII byte classifiers (deterministic; locale-independent) ------------
//
// We classify by ASCII byte VALUE so the keyword lexer is exact and portable.
//
fun is_lower(b: sint): bool = band(b >= 97, b <= 122)   // a..z
fun is_upper(b: sint): bool = band(b >= 65, b <= 90)    // A..Z
fun is_alpha(b: sint): bool = bor(is_lower(b), is_upper(b))
fun is_digit(b: sint): bool = band(b >= 48, b <= 57)    // 0..9
fun is_alnum(b: sint): bool = bor(is_alpha(b), is_digit(b))
fun is_under(b: sint): bool = (b = 95)                  // '_'
// an identifier CONTINUATION byte: letter | digit | '_'
fun is_idcont(b: sint): bool = bor(is_alnum(b), is_under(b))
// an identifier START byte: letter | '_'
fun is_idstart(b: sint): bool = bor(is_alpha(b), is_under(b))
// hex/oct/bin digits
fun is_hex(b: sint): bool =
  bor(is_digit(b), bor(band(b >= 97, b <= 102), band(b >= 65, b <= 70)))
fun is_oct(b: sint): bool = band(b >= 48, b <= 55)      // 0..7
fun is_bin(b: sint): bool = bor(b = 48, b = 49)         // 0..1
// inline (non-newline) whitespace: space(32) tab(9) CR(13) FF(12) VT(11)
fun is_inws(b: sint): bool =
  bor(b = 32, bor(b = 9, bor(b = 13, bor(b = 12, b = 11))))
//
(* ****** ****** *)
//
// ---- keyword classification of an identifier lexeme ------------------------
//
// An identifier lexeme that exactly matches a reserved word lexes as that keyword;
// otherwise it is PT_UIDENT (if uppercase-initial) or PT_LIDENT. `_` alone is its
// own PT_USCORE token (handled before this — a lexeme of length 1 == "_").
//
fun
kw_of_lident(s: strn): ptnode =
(
  if s = "let" then PT_KW_LET()
  else if s = "mut" then PT_KW_MUT()
  else if s = "var" then PT_KW_VAR()
  else if s = "def" then PT_KW_DEF()
  else if s = "if" then PT_KW_IF()
  else if s = "elif" then PT_KW_ELIF()
  else if s = "else" then PT_KW_ELSE()
  else if s = "while" then PT_KW_WHILE()
  else if s = "for" then PT_KW_FOR()
  else if s = "in" then PT_KW_IN()
  else if s = "match" then PT_KW_MATCH()
  else if s = "case" then PT_KW_CASE()
  else if s = "break" then PT_KW_BREAK()
  else if s = "continue" then PT_KW_CONTINUE()
  else if s = "return" then PT_KW_RETURN()
  else if s = "import" then PT_KW_IMPORT()
  else if s = "from" then PT_KW_FROM()
  else if s = "type" then PT_KW_TYPE()
  else if s = "enum" then PT_KW_ENUM()
  else if s = "struct" then PT_KW_STRUCT()
  else if s = "exception" then PT_KW_EXCEPTION()
  else if s = "raise" then PT_KW_RAISE()
  else if s = "try" then PT_KW_TRY()
  else if s = "except" then PT_KW_EXCEPT()
  else if s = "as" then PT_KW_AS()
  // A-QUANT: `forall`/`exists` are NEW keywords — EXPLICIT quantifiers inside a TYPE
  // (`forall[n: SInt | g] T`, `exists[m: SInt] T`). They are GENUINE binders (not decorator-
  // izable), so they are reserved words, NOT LIDENTs.
  else if s = "forall" then PT_KW_FORALL()
  else if s = "exists" then PT_KW_EXISTS()
  // B-LINEAR: `at` is the AT-VIEW relation keyword (`A at l`). A genuine binder/relation
  // (not decorator-izable), so it is a reserved word, NOT a LIDENT.
  else if s = "at" then PT_KW_AT()
  // SCOPING (bootstrap P1): `where` trails a def as a `where:` block (backwards-scoping decls
  // around the body → D2Ewhere); `private` is a decl-modifier / `private:` block (capture-rest
  // → D2Clocal0). Both are genuine binders/scopers, so they are reserved words, NOT LIDENTs.
  else if s = "where" then PT_KW_WHERE()
  else if s = "private" then PT_KW_PRIVATE()
  // NOTE (decorator rework): `extern`/`implement`/`overload`/`prfun`/`prval`/`praxi`/`op`/`with`
  // are NO LONGER keywords — the ATS-specific def/let variants are now @decorators on a plain
  // `def`/`let` (`@extern`/`@impl`/`@overload`/`@proof`), and `op+` became the parenthesized
  // operator form `(+)`. So `extern`/`impl`/`proof`/`overload` lex as ordinary LIDENTs (which is
  // exactly what a `@name` decorator needs), and `op`/`with` are plain identifiers again.
  //
  // NOTE (decorator rework, slice 2): `dataprop`/`dataview`/`abstype`/`assume`/`sortdef`/`stacst`/
  // `stadef` are NO LONGER keywords either — the ATS-specific enum/type VARIANTS are now @decorators
  // on a plain `enum`/`type`/`let` (`@prop enum`/`@view enum`/`@abstract type`/`@impl type`/
  // `@sort type`/`@static type`/`@static let`). So `prop`/`view`/`abstract`/`sort`/`static` lex as
  // ordinary LIDENTs (decorator names; `impl` is shared with slice 1's `@impl def`).
  else if s = "and" then PT_KW_AND()
  else if s = "or" then PT_KW_OR()
  else if s = "not" then PT_KW_NOT()
  else if s = "true" then PT_TRUE()
  else if s = "false" then PT_FALSE()
  else PT_LIDENT(s)
) (* end of [kw_of_lident] *)
//
(* ****** ****** *)
//
// build a token spanning [c0, c1) with the given kind
//
fun
mk_tok
(src: lcsrc, nod: ptnode, c0: cur, c1: cur): pytoken =
  PYTOKEN(nod, loctn_make_arg3(src, cur_postn(c0), cur_postn(c1)))
//
(* ****** ****** *)
//
// ---- scanners for multi-byte lexemes; each returns (token, cursor-after) ----
//
// identifier / keyword: consume idcont bytes, then zero or more slash-separated
// identifier segments (`foo/bar/baz`) with NO whitespace. This gives Koka-style
// surface names for ATS `$` identifiers while preserving spaced `a / b` division.
//
fun
scan_ident
(src: lcsrc, c0: cur): @(pytoken, cur) = let
//
fun segment(c: cur): cur =
  if is_idcont(cur_byte(c)) then segment(cur_adv(c)) else c
and loop(c: cur): cur = let
  val c1 = segment(c)
in
  if band(cur_byte(c1) = 47, is_idstart(cur_byte_at(c1, 1)))
    then loop(cur_adv(c1))
    else c1
end
//
val c1 = loop(c0)
val lx = PYL_slice(c0.0, c1.0)
val b0 = cur_byte(c0)
val nod =
  if lx = "_" then PT_USCORE()
  else if is_upper(b0) then PT_UIDENT(lx)
  else kw_of_lident(lx)   // lowercase- or '_'-initial → keyword or LIDENT
//
in
  @(mk_tok(src, nod, c0, c1), c1)
end (* end of [scan_ident] *)
//
(* ****** ****** *)
//
// number: INT (dec / 0x / 0o / 0b) or FLOAT (dec '.' dec [eE [+-] dec]).
// We keep the lexeme faithful; full value parsing is M2/lowering's job. A leading
// '.' is NOT a number (handled as PT_DOT by the caller); we are entered on a digit.
//
fun
scan_number
(src: lcsrc, c0: cur): @(pytoken, cur) = let
//
// consume a run satisfying pred
fun run(c: cur, pred: sint -> bool): cur =
  if pred(cur_byte(c)) then run(cur_adv(c), pred) else c
//
val b0 = cur_byte(c0)
val b1 = cur_byte_at(c0, 1)
//
in
//
// radix prefixes: 0x / 0o / 0b  (b0 == '0')
if band(b0 = 48, bor(b1 = 120, b1 = 88)) then let       // 0x / 0X
  val c1 = run(cur_advn(c0, 2), lam(b) => is_hex(b))
  in @(mk_tok(src, PT_INT(PYL_slice(c0.0, c1.0)), c0, c1), c1) end
else if band(b0 = 48, bor(b1 = 111, b1 = 79)) then let   // 0o / 0O
  val c1 = run(cur_advn(c0, 2), lam(b) => is_oct(b))
  in @(mk_tok(src, PT_INT(PYL_slice(c0.0, c1.0)), c0, c1), c1) end
else if band(b0 = 48, bor(b1 = 98, b1 = 66)) then let     // 0b / 0B
  val c1 = run(cur_advn(c0, 2), lam(b) => is_bin(b))
  in @(mk_tok(src, PT_INT(PYL_slice(c0.0, c1.0)), c0, c1), c1) end
else let
  // decimal integer part
  val cA = run(c0, lam(b) => is_digit(b))
  // a FLOAT requires '.' FOLLOWED BY a digit (so `x.field` and `1.method` stay int+dot)
  val isdot = band(cur_byte(cA) = 46, is_digit(cur_byte_at(cA, 1)))
in
  if ~isdot then
    @(mk_tok(src, PT_INT(PYL_slice(c0.0, cA.0)), c0, cA), cA)
  else let
    // '.' then fractional digits
    val cB = run(cur_adv(cA), lam(b) => is_digit(b))
    // optional exponent: (e|E) [+|-] digit+
    val be = cur_byte(cB)
    val cC =
      if bor(be = 101, be = 69) then let                 // e / E
        val cd = cur_adv(cB)
        val bs = cur_byte(cd)
        val ce = if bor(bs = 43, bs = 45) then cur_adv(cd) else cd  // + / -
      in
        if is_digit(cur_byte(ce)) then run(ce, lam(b) => is_digit(b)) else cB
        // (no digits after eE ⇒ exponent not taken; lexeme ends before 'e')
      end
      else cB
  in
    @(mk_tok(src, PT_FLOAT(PYL_slice(c0.0, cC.0)), c0, cC), cC)
  end
end
//
end (* end of [scan_number] *)
//
(* ****** ****** *)
//
// quoted literal: string ('"') or char ("'"). The lexeme INCLUDES the quotes.
// Escapes: a backslash makes the NEXT byte literal (so \" \' \\ \n etc. don't close
// the quote). An unterminated literal (newline or EOF before the close) yields a
// PT_ERROR over what was consumed — the lexer never throws (recovery is M2's).
// `q` is the quote byte (34 = '"', 39 = "'").
//
fun
scan_quoted
(src: lcsrc, c0: cur, q: sint): @(pytoken, cur) = let
//
// scan from just-after the opening quote; return (cursor-after-close, closed?).
fun loop(c: cur): @(cur, bool) = let
  val b = cur_byte(c)
in
  if b < 0 then @(c, false)          // EOF before close
  else if b = 10 then @(c, false)    // newline before close (unterminated)
  else if b = 92 then                // backslash: skip the escaped byte too
    (let val c1 = cur_adv(c) in
       if cur_byte(c1) < 0 then @(c1, false) else loop(cur_adv(c1)) end)
  else if b = q then @(cur_adv(c), true)   // closing quote consumed
  else loop(cur_adv(c))
end
//
val cOpen = cur_adv(c0)               // past the opening quote
val @(c1, closed) = loop(cOpen)
val lx = PYL_slice(c0.0, c1.0)
val nod =
  if ~closed then PT_ERROR(lx)
  else if q = 34 then PT_STRING(lx)
  else PT_CHAR(lx)
//
in
  @(mk_tok(src, nod, c0, c1), c1)
end (* end of [scan_quoted] *)
//
(* ****** ****** *)
//
// ---- operator / punctuation dispatch ---------------------------------------
//
// Tries the longest match first (==, !=, <=, >=, //, **, =>, ->), then 1-byte ops.
// Returns (token, cursor-after) or, for an unknown byte, a PT_ERROR over 1 byte.
//
fun
scan_op
(src: lcsrc, c0: cur): @(pytoken, cur) = let
//
val b0 = cur_byte(c0)
val b1 = cur_byte_at(c0, 1)
val b2 = cur_byte_at(c0, 2)
//
// helper: emit a fixed-width op of n bytes
fun emit(nod: ptnode, n: sint): @(pytoken, cur) = let
  val c1 = cur_advn(c0, n) in @(mk_tok(src, nod, c0, c1), c1) end
//
in
//
// three-byte operators (B-LINEAR move/swap) — MUST precede the 2-byte `:=` so the
// longest match wins (`:=>` and `:=:` both start with `:=`).
if band3(b0 = 58, b1 = 61, b2 = 62) then emit(PT_MOVE(), 3)      // :=>
else if band3(b0 = 58, b1 = 61, b2 = 58) then emit(PT_SWAP(), 3) // :=:
// two-byte operators
else if band(b0 = 61, b1 = 61) then emit(PT_EQEQ(), 2)        // ==
else if band(b0 = 33, b1 = 61) then emit(PT_NEQ(), 2)    // !=
else if band(b0 = 60, b1 = 61) then emit(PT_LTE(), 2)    // <=
else if band(b0 = 62, b1 = 61) then emit(PT_GTE(), 2)    // >=
else if band(b0 = 47, b1 = 47) then emit(PT_SLASH2(), 2) // //
else if band(b0 = 42, b1 = 42) then emit(PT_STAR2(), 2)  // **
else if band(b0 = 61, b1 = 62) then emit(PT_FATARROW(), 2)// =>
else if band(b0 = 45, b1 = 62) then emit(PT_ARROW(), 2)  // ->
else if band(b0 = 58, b1 = 61) then emit(PT_COLONEQ(), 2) // := (var-cell assign; MUST
                                                          //    precede the 1-byte `:`)
// one-byte operators / punctuation
else if (b0 = 43) then emit(PT_PLUS(), 1)              // +
else if (b0 = 45) then emit(PT_MINUS(), 1)             // -
else if (b0 = 42) then emit(PT_STAR(), 1)              // *
else if (b0 = 47) then emit(PT_SLASH(), 1)             // /
else if (b0 = 37) then emit(PT_PERCENT(), 1)           // %
else if (b0 = 61) then emit(PT_EQ(), 1)                // =
else if (b0 = 60) then emit(PT_LT(), 1)                // <
else if (b0 = 62) then emit(PT_GT(), 1)                // >
else if (b0 = 58) then emit(PT_COLON(), 1)             // :
else if (b0 = 64) then emit(PT_AT(), 1)               // @  (decorator marker; standalone)
else if (b0 = 38) then emit(PT_AMP(), 1)               // &  (address-of prefix; B-LINEAR)
else if (b0 = 33) then emit(PT_BANG(), 1)              // !  (deref prefix; B-LINEAR; `!=` matched above)
else if (b0 = 126) then emit(PT_TILDE(), 1)            // ~  (linear-consume pattern prefix; B-LINEAR)
else if (b0 = 124) then emit(PT_BAR(), 1)              // |  (sum-type separator)
else if (b0 = 44) then emit(PT_COMMA(), 1)             // ,
else if (b0 = 46) then emit(PT_DOT(), 1)               // .
else if (b0 = 40) then emit(PT_LPAREN(), 1)            // (
else if (b0 = 41) then emit(PT_RPAREN(), 1)            // )
else if (b0 = 91) then emit(PT_LBRACK(), 1)            // [
else if (b0 = 93) then emit(PT_RBRACK(), 1)            // ]
else if (b0 = 123) then emit(PT_LBRACE(), 1)           // {
else if (b0 = 125) then emit(PT_RBRACE(), 1)           // }
else let
  // unknown byte: 1-byte PT_ERROR (never throw; recover)
  val c1 = cur_adv(c0)
in @(mk_tok(src, PT_ERROR(PYL_slice(c0.0, c1.0)), c0, c1), c1) end
//
end (* end of [scan_op] *)
//
(* ****** ****** *)
//
// ---- the main scan loop ----------------------------------------------------
//
// Accumulates tokens in REVERSE; reversed at the end. Skips inline whitespace and
// `#` line comments (advancing the cursor so spans stay correct). Emits PT_NL_RAW
// for a physical '\n'. A line continuation '\' immediately before '\n' joins the
// lines (the '\' and the '\n' are both consumed, NO PT_NL_RAW emitted). Ends with
// a zero-width PT_EOF.
//
// LEADING-TAB RULE (SURFACE-GRAMMAR §3): indentation must be SPACES. A TAB (0x09)
// in a logical line's LEADING (indentation) whitespace — i.e. before the line's
// first non-whitespace token — is a HARD ERROR: we emit a 1-byte PT_ERROR over the
// offending tab (no tab-stop guessing, no spaces/tabs mixing, no silent accept) and
// keep scanning (non-fail-fast). A tab AFTER the first real token of the line is
// ordinary inline whitespace and is skipped as before.
//
// `bol` ("beginning of line") = we are still in the LEADING whitespace of the
// current logical line (no real token seen on it yet). Threaded BY VALUE — no global
// state. It is TRUE at input start and right after a PT_NL_RAW; it stays TRUE while
// we skip leading spaces (or flag leading tabs) and for blank / comment-only lines;
// it becomes FALSE at the first real token of the line. A '\'-continuation does NOT
// start a new logical line, so it leaves `bol` unchanged.
//
fun
scan_loop
(src: lcsrc, c: cur, bol: bool, acc: pytokenlst): pytokenlst = let
  val b = cur_byte(c)
in
//
if b < 0 then
  // EOF: append a zero-width PT_EOF, then reverse.
  list_reverse(list_cons(mk_tok(src, PT_EOF(), c, c), acc))
//
else if b = 10 then   // physical newline → PT_NL_RAW (zero-width AT the '\n' pos)
  let
    val tk = mk_tok(src, PT_NL_RAW(), c, cur_adv(c))
  in scan_loop(src, cur_adv(c), true, list_cons(tk, acc)) end
//
else if b = 92 then   // backslash: line continuation if next is '\n' (opt. CR)
  let
    val b1 = cur_byte_at(c, 1)
  in
    if b1 = 10 then scan_loop(src, cur_advn(c, 2), bol, acc)       // '\' '\n'
    else if band(b1 = 13, cur_byte_at(c, 2) = 10)
      then scan_loop(src, cur_advn(c, 3), bol, acc)                // '\' CR LF
    else // a lone backslash is not valid here → PT_ERROR(1)
      let val @(tk, c1) = scan_op(src, c) in scan_loop(src, c1, false, list_cons(tk, acc)) end
  end
//
else if band(bol, b = 9) then   // a TAB in LEADING indentation: HARD ERROR (§3)
  // emit a 1-byte PT_ERROR over the tab; stay in leading-whitespace (bol) and keep
  // scanning (non-fail-fast). The cursor still advances past the tab so the first
  // real token's byte column is unchanged and downstream layout is not mis-counted.
  let
    val c1 = cur_adv(c)
    val tk = mk_tok(src, PT_ERROR(PYL_slice(c.0, c1.0)), c, c1)
  in scan_loop(src, c1, true, list_cons(tk, acc)) end
//
else if is_inws(b) then   // inline whitespace: skip (advance, no token); keep bol
  scan_loop(src, cur_adv(c), bol, acc)
//
else if b = 35 then   // '#' line comment: skip to (not past) end-of-line; keep bol
  // (a comment-only line carries NO real token, so the line stays "at line start"
  //  for the indentation rule — the next real content is on a later line.)
  let
    fun skip(c: cur): cur =
      let val bb = cur_byte(c) in
        if bor(bb < 0, bb = 10) then c else skip(cur_adv(c)) end
  in scan_loop(src, skip(c), bol, acc) end
//
else if band(b = 40, cur_byte_at(c, 1) = 42) then
  // '(*' opens a NESTABLE block comment (ATS-parity). Skip the WHOLE comment body
  // (tracking nesting depth: each inner `(*` bumps depth, each `*)` drops it; the
  // comment ends when depth returns to 0). EOF inside an open comment -> a PT_ERROR
  // over the opening `(*` (the lexer never throws; recovery is M2's). A block comment
  // may span newlines; we DROP the comment but must keep the cursor's row/col exact
  // (cur_adv tracks '\n'). `bol` is preserved (a comment carries no real token), so a
  // comment-only / leading-whitespace block comment keeps the line "at line start".
  //
  // Note `//` line comments are DEFERRED: `//` is already the int-division op
  // (PT_SLASH2). ATS uses `//` for line comments but we keep our existing int-div role
  // (a parity-vs-existing-choice conflict; flagged in the report). Only `(* *)` is added.
  let
    // skip from just-AFTER the opening `(*`; `depth` is the count of still-open `(*`.
    // returns (cursor-after-the-close, closed?) — closed=false means EOF before close.
    fun
    skipblk(c: cur, depth: sint): @(cur, bool) =
      let val bb = cur_byte(c) in
        if bb < 0 then @(c, false)                       // EOF inside an open comment
        else if band(bb = 40, cur_byte_at(c, 1) = 42)    // a nested `(*` -> depth+1
          then skipblk(cur_advn(c, 2), depth + 1)
        else if band(bb = 42, cur_byte_at(c, 1) = 41)    // a `*)` -> depth-1
          then (if depth <= 1 then @(cur_advn(c, 2), true)  // outermost close: done
                else skipblk(cur_advn(c, 2), depth - 1))
        else skipblk(cur_adv(c), depth)                  // any other byte (incl. '\n')
      end
    val @(c1, closed) = skipblk(cur_advn(c, 2), 1)
  in
    if closed
      then scan_loop(src, c1, bol, acc)                  // comment skipped; keep bol
      else // unterminated block comment: a PT_ERROR over the opening `(*` (recover).
        let val cerr = cur_advn(c, 2)
            val tk = mk_tok(src, PT_ERROR(PYL_slice(c.0, cerr.0)), c, cerr)
        in scan_loop(src, c1, false, list_cons(tk, acc)) end
  end
//
else if is_idstart(b) then
  let val @(tk, c1) = scan_ident(src, c) in scan_loop(src, c1, false, list_cons(tk, acc)) end
//
else if is_digit(b) then
  let val @(tk, c1) = scan_number(src, c) in scan_loop(src, c1, false, list_cons(tk, acc)) end
//
else if b = 34 then   // '"' string
  let val @(tk, c1) = scan_quoted(src, c, 34) in scan_loop(src, c1, false, list_cons(tk, acc)) end
//
else if b = 39 then   // "'" char
  let val @(tk, c1) = scan_quoted(src, c, 39) in scan_loop(src, c1, false, list_cons(tk, acc)) end
//
else
  let val @(tk, c1) = scan_op(src, c) in scan_loop(src, c1, false, list_cons(tk, acc)) end
//
end (* end of [scan_loop] *)
//
(* ****** ****** *)
//
// ---- the public raw-scan entry ---------------------------------------------
//
#implfun
pylex_text(src, text) = let
  val _ = PYL_load(text)     // (re)load the byte buffer for THIS lex (pure per call)
in
  // bol=true: input starts at the beginning of (logical) line 0.
  scan_loop(src, cur_init(), true, list_nil())
end (* end of [pylex_text] *)
//
(* ****** ****** *)
//
(*
end of [frontend/DATS/pylexing_token.dats]
*)
