(* ****** ****** *)
(*
** M1 — Python-surface frontend: the TOKEN datatype + lexer/layout entry (SATS).
**
** THIS FILE IS THE CONTRACT M2 (the parser) WILL CONSUME. The `pytoken` datatype
** below is the surface-token vocabulary; every token carries a real `loctn`
** (0-based rows/cols, ncol in UTF-8 BYTES) borrowed from the compiler's location
** model (srcgen2/SATS/locinfo.sats) so spans flow into L2 nodes and diagnostics
** land on the .py source for free (PYTHON-FRONTEND-PLAN.md §5.1, §6.3).
**
** Authority for the surface lexical structure: frontend/docs/SURFACE-GRAMMAR.md
** §5.1 (lexical), §5.6 (operators), the identifier-case convention (§5 preamble),
** and the keyword/role tables (§4).
**
** PURELY ADDITIVE: nothing under srcgen2/ or language-server/ is modified. We only
** CALL the compiler-as-a-library (the location model) — we do NOT reuse the ATS
** lexer (the surface lexical grammar is different; plan §5.1).
**
** RE-ENTRANCY (plan §6.2): the lexer is pure per call. `pylex_text`/`pylex_layout`
** take the source text as an argument, scan it, and return a fresh token list; no
** module-global lexer state persists between calls. (The byte buffer the FFI scans
** is loaded and fully consumed within a single call.)
*)
(* ****** ****** *)
//
// Bring in the location model: loctn / postn / lcsrc + makers/printers.
// (libxatsopt.hats is SATS-only; we additionally staload locinfo for loctn etc.,
// exactly as the M0a driver does.)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
//
// xatsopt_sats.hats is the pure prelude+libcats SATS bundle (gbas/strn/list/...
// + FILR=FILEref). We need it here because the print signatures below NAME `FILR`;
// without it, `FILR` is unknown and the param types resolve to "none". It is SATS-
// only and disjoint from libxatsopt.hats, so including both is safe.
//
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
(* ****** ****** *)
//
// ====================================================================
// The token KIND: `ptnode`. A `pytoken` is a (ptnode, loctn) pair.
// ====================================================================
//
// Design rationale (the M2 contract):
//
//  * KEYWORDS get one constructor each (PT_KW_*). They are RESERVED words from
//    SURFACE-GRAMMAR §5.1; an identifier whose lexeme equals a keyword lexes as
//    the keyword, NOT as an LIDENT. `true`/`false` are literal keywords (lexed as
//    PT_TRUE/PT_FALSE, a boolean literal), NOT data constructors (§5 preamble).
//    `and`/`or`/`not` are *keyword operators* — kept as keywords (PT_KW_AND/OR/NOT)
//    because the parser owns their precedence (§5.6); M2 treats them as operators.
//
//  * IDENTIFIERS are split by INITIAL CASE (the load-bearing convention, §5):
//      PT_UIDENT — uppercase-initial: a type- or data-constructor (Int, List, Leaf).
//      PT_LIDENT — lowercase-initial: a var / fun / type-var / field (x, sum, a).
//    The lexer does the case split so the parser never consults name resolution.
//    Both carry their lexeme (the identifier text). Slash-separated segments with
//    no whitespace (`name/part`) are one identifier token; lowering maps `/` back
//    to ATS `$` so pretty-printed compiler/prelude names resolve.
//
//  * LITERALS carry their *exact source lexeme* (quotes/prefix INCLUDED) as a strn
//    plus a byte length, so the lowering can re-synthesize the ATS leaf token and
//    diagnostics can show the literal verbatim:
//      PT_INT   — INT lexeme as written (incl. 0x/0o/0b prefix).
//      PT_FLOAT — FLOAT lexeme as written.
//      PT_STRING— the WHOLE string literal INCLUDING the surrounding double quotes.
//      PT_CHAR  — the WHOLE char literal INCLUDING the surrounding single quotes.
//      PT_TRUE / PT_FALSE — the boolean literal keywords.
//    (Numeric value parsing / escape decoding is M2/lowering's job — the lexer keeps
//    the lexeme faithful. It DOES validate well-formedness enough to delimit.)
//
//  * OPERATORS & PUNCTUATION each get a distinct nullary constructor so M2 matches
//    on the kind, not on a re-scanned lexeme. Roles per SURFACE-GRAMMAR §4/§5.6:
//      arithmetic : PT_PLUS PT_MINUS PT_STAR PT_SLASH PT_SLASH2(//) PT_PERCENT PT_STAR2(**)
//      compare    : PT_EQEQ(==) PT_NEQ(!=) PT_LT PT_LTE(<=) PT_GT PT_GTE(>=)
//      roles      : PT_EQ(=) bind/reassign · PT_FATARROW(=>) lambda · PT_ARROW(->) type
//                   PT_COLON(:) annotation/block-header
//      separators : PT_COMMA PT_DOT
//      brackets   : PT_LPAREN PT_RPAREN PT_LBRACK PT_RBRACK PT_LBRACE PT_RBRACE
//
//  * LAYOUT tokens are synthesized by the layout pass (pylayout.dats), NOT by the
//    raw scanner: PT_NEWLINE (logical line end), PT_INDENT, PT_DEDENT. PT_EOF marks
//    end of input. (The raw scanner instead emits PT_NL_RAW for a physical newline
//    and PT_EOF; the layout pass rewrites those into NEWLINE/INDENT/DEDENT.)
//
//  * ERROR token: PT_ERROR carries the offending lexeme so the parser can recover
//    (matching the compiler's non-fail-fast spirit). The lexer never throws.
//
datatype
ptnode =
//
// ---- keywords (reserved; SURFACE-GRAMMAR §5.1) ----
//
| PT_KW_LET     of ()   // let
| PT_KW_MUT     of ()   // mut  (only meaningful right after `let`; lexed as a kw)
| PT_KW_VAR     of ()   // var  (ATS-parity mutable CELL declaration; distinct from
                        //       `let mut` SSA rebinding — `var` is an aliasable
                        //       in-place cell, NOT a loop accumulator.)
| PT_KW_DEF     of ()   // def
| PT_KW_IF      of ()   // if
| PT_KW_ELIF    of ()   // elif
| PT_KW_ELSE    of ()   // else
| PT_KW_WHILE   of ()   // while
| PT_KW_FOR     of ()   // for
| PT_KW_IN      of ()   // in
| PT_KW_MATCH   of ()   // match
| PT_KW_CASE    of ()   // case
| PT_KW_BREAK   of ()   // break
| PT_KW_CONTINUE of ()  // continue
| PT_KW_RETURN  of ()   // return
| PT_KW_IMPORT  of ()   // import
| PT_KW_FROM    of ()   // from
| PT_KW_TYPE    of ()   // type
| PT_KW_ENUM    of ()   // enum   (type declaration; SURFACE-GRAMMAR §5.7)
| PT_KW_STRUCT  of ()   // struct (type declaration; SURFACE-GRAMMAR §5.7)
| PT_KW_EXCEPTION of () // exception (exception-constructor declaration; EXN)
| PT_KW_RAISE   of ()   // raise  (raise an exception; EXN)
| PT_KW_TRY     of ()   // try    (try/except expression; EXN)
| PT_KW_EXCEPT  of ()   // except (an except clause of a try; EXN)
| PT_KW_AS      of ()   // as  (pattern alias; SURFACE-GRAMMAR §5.5)
| PT_KW_FORALL  of ()   // forall (EXPLICIT universal quantifier in a type; A-QUANT, §A)
| PT_KW_EXISTS  of ()   // exists (EXPLICIT existential quantifier in a type; A-QUANT, §A)
| PT_KW_AT      of ()   // at  (AT-VIEW relation in a type: `A at l`; B-LINEAR, §B. `@` stays
                        //      decorators-only — `at` is a genuine keyword/relation, not a decorator.)
| PT_KW_WHERE   of ()   // where (SCOPING: a `where:` block trailing a def → D2Ewhere; bootstrap P1)
| PT_KW_PRIVATE of ()   // private (SCOPING: a `private` decl-modifier / `private:` block → D2Clocal0)
//
// NOTE (decorator rework): the ATS-specific def/let variants are NO LONGER keywords. They are
// expressed as @decorators on a plain `def`/`let` — `@proof def`/`@proof let`/`@proof @extern def`
// (was prfun/prval/praxi), `@extern def` (was extern), `@impl def` (was implement), `@overload def`
// (was overload) — and `op+` became the parenthesized operator form `(+)`. So PT_KW_EXTERN /
// PT_KW_IMPLEMENT / PT_KW_OVERLOAD / PT_KW_WITH / PT_KW_OP / PT_KW_PRFUN / PT_KW_PRVAL / PT_KW_PRAXI
// were REMOVED; `extern`/`impl`/`proof`/`overload`/`op`/`with` now lex as ordinary LIDENTs.
//
// NOTE (decorator rework, slice 2): the ATS-specific enum/type VARIANTS are NO LONGER keywords
// either. They are @decorators on a plain `enum`/`type`/`let`:
//   `@prop enum` / `@view enum`   (was dataprop / dataview),
//   `@abstract type` (no `= rhs`) (was abstype),  `@impl type T = R` (was assume),
//   `@sort type N = SInt`         (was sortdef),
//   `@static type X = e` / `@static let x = e` (was stadef),  `@static let c: SInt` (was stacst).
// So PT_KW_DATAPROP / PT_KW_DATAVIEW / PT_KW_ABSTYPE / PT_KW_ASSUME / PT_KW_SORTDEF / PT_KW_STACST /
// PT_KW_STADEF were REMOVED; `prop`/`view`/`abstract`/`impl`/`sort`/`static` now lex as ordinary
// LIDENTs (decorator names).
//
| PT_KW_AND     of ()   // and (keyword operator, §5.6 lvl 2)
| PT_KW_OR      of ()   // or  (keyword operator, §5.6 lvl 1)
| PT_KW_NOT     of ()   // not (keyword operator, §5.6 lvl 3)
//
// ---- identifiers (case-split; SURFACE-GRAMMAR §5 preamble) ----
//
| PT_UIDENT of strn     // Uppercase-initial: type- or data-constructor
| PT_LIDENT of strn     // lowercase-initial: var / fun / type-var / field
| PT_USCORE of ()       // `_` wildcard (its own token; §5.5)
//
// ---- literals (lexeme kept verbatim) ----
//
| PT_INT    of strn     // integer literal lexeme (incl. 0x/0o/0b)
| PT_FLOAT  of strn     // float literal lexeme
| PT_STRING of strn     // string literal lexeme INCLUDING the surrounding quotes
| PT_CHAR   of strn     // char   literal lexeme INCLUDING the surrounding quotes
| PT_TRUE   of ()       // true  (boolean literal keyword)
| PT_FALSE  of ()       // false (boolean literal keyword)
//
// ---- operators & punctuation ----
//
| PT_PLUS    of ()  // +
| PT_MINUS   of ()  // -
| PT_STAR    of ()  // *
| PT_SLASH   of ()  // /
| PT_SLASH2  of ()  // //   (integer division)
| PT_PERCENT of ()  // %
| PT_STAR2   of ()  // **   (power, right-assoc)
| PT_EQEQ    of ()  // ==
| PT_NEQ     of ()  // !=
| PT_LT      of ()  // <
| PT_LTE     of ()  // <=
| PT_GT      of ()  // >
| PT_GTE     of ()  // >=
| PT_EQ      of ()  // =    (bind / reassign)
| PT_COLONEQ of ()  // :=   (var-cell assignment; ATS-parity var/mutation — distinct
                    //       from `=` SSA reassign. Lexed as ONE token when `:` is
                    //       IMMEDIATELY followed by `=` (no intervening space).)
| PT_MOVE    of ()  // :=>  (MOVE / consume-assign; B-LINEAR, §B. Lowers to D2Exazgn.
                    //       Lexed BEFORE `:=` so the 3-byte form wins the longest match.)
| PT_SWAP    of ()  // :=:  (SWAP; B-LINEAR, §B. Lowers to D2Exchng. Lexed BEFORE `:=`.)
| PT_AMP     of ()  // &    (ADDRESS-OF prefix; B-LINEAR, §B. Lowers to D2Eaddr.)
| PT_BANG    of ()  // !    (DEREFERENCE prefix in expr position / view-read prefix in pattern
                    //       position; B-LINEAR, §B. Lowers to D2Eeval or D2Pbang. Single `!` —
                    //       `!=` is matched first as PT_NEQ.)
| PT_TILDE   of ()  // ~    (LINEAR-CONSUME pattern prefix `~p`; B-LINEAR, §B. Lowers to D2Pfree.)
| PT_FATARROW of () // =>   (lambda arrow)
| PT_ARROW   of ()  // ->   (type / return arrow)
| PT_COLON   of ()  // :    (annotation / block-header)
| PT_AT      of ()  // @    (decorator marker; '@' LIDENT, SURFACE-GRAMMAR §5.7; also
                    //       generated flat/viewbox pattern prefix `@(C)(...)` -> D2Pflat)
| PT_BAR     of ()  // |    (sum-type / data-constructor separator; SURFACE-GRAMMAR
                    //       §5.2 `datacon { '|' datacon }`. NOTE: `|` is used in the
                    //       grammar but is MISSING from the §5.1 lexical list and the
                    //       §5.6 operator table — a spec gap flagged in M1-REPORT.md.)
| PT_COMMA   of ()  // ,
| PT_DOT     of ()  // .
| PT_LPAREN  of ()  // (
| PT_RPAREN  of ()  // )
| PT_LBRACK  of ()  // [
| PT_RBRACK  of ()  // ]
| PT_LBRACE  of ()  // {
| PT_RBRACE  of ()  // }
//
// ---- layout & control ----
//
| PT_NL_RAW  of ()  // a PHYSICAL newline, emitted ONLY by the raw scanner;
                    //   the layout pass consumes these and emits NEWLINE/INDENT/DEDENT.
| PT_NEWLINE of ()  // a LOGICAL line terminator (layout pass output)
| PT_INDENT  of ()  // indentation increase (layout pass output)
| PT_DEDENT  of ()  // indentation decrease (layout pass output)
| PT_EOF     of ()  // end of input
//
// ---- error recovery ----
//
| PT_ERROR  of strn // an un-lexable lexeme (kept for diagnostics; never throws)
//
// QMARK-TYPE: the `?` STATIC operator — ATS `#sexpdef ? = top0_vt_t0` (prelude
// basics0.sats:460). In a TYPE/static-application position `?[A]` is the "maybe-
// uninitialized" / top-view of `A`: the stock parser lexes `?` as `T_IDSYM("?")`
// and resolves it via the prelude alias to the abstype `top0_vt_t0`, so `{?a}` is
// the ordinary static application `S2Eapps([?, a])` -> S2Etop0(a). We keep a
// DEDICATED token (rather than folding `?` into a generic symbolic-ident lexeme)
// because the surface has no other use for a bare `?`; `p_type_atom` turns it into
// `PyTcon("?", [A])` and lowering resolves the head `?` against the prelude sexpdef.
// APPENDED LAST so its constructor tag (81) does not renumber any existing token
// (the CATS scanner must emit PT_QMARK with the SAME tag — see pylexing.cats).
| PT_QMARK  of ()   // ?  (the `?` static / top-view operator in a TYPE position)
//
(* ****** ****** *)
//
// A `pytoken` pairs a kind with its source span (half-open [pbeg, pend)).
// Synthetic layout tokens (NEWLINE/INDENT/DEDENT/EOF) carry a zero-width span at
// the relevant position so they still report on the .py source.
//
datatype
pytoken =
| PYTOKEN of (ptnode, loctn)
//
#typedef pytokenlst = list(pytoken)
//
(* ****** ****** *)
//
fun pytoken_get_node(tok: pytoken): ptnode
fun pytoken_get_loctn(tok: pytoken): loctn
//
#symload node with pytoken_get_node
#symload loctn with pytoken_get_loctn
//
(* ****** ****** *)
//
// ---- the raw scanner (pylexing_token.dats) ---------------------------------
//
// `pylex_text(src, text)` scans the WHOLE `text` (a strn; bytes counted in UTF-8)
// into a raw token list terminated by PT_EOF. `src` is the source identity
// (LCSRCfpath for a real file, LCSRCsome1/none for buffers) stamped into every
// token's loctn. Physical newlines appear as PT_NL_RAW; comments and inter-token
// whitespace are discarded (but advance the position so spans stay correct).
// PURE: no global state; safe to call repeatedly.
//
fun
pylex_text
(src: lcsrc, text: strn): pytokenlst
//
(* ****** ****** *)
//
// ---- the layout pass (pylayout.dats) ---------------------------------------
//
// `pylex_layout(src, text)` = the raw scan followed by the CPython off-side rule:
// PT_NL_RAW between logical lines becomes PT_NEWLINE; indentation increases/decreases
// become PT_INDENT/PT_DEDENT(s); open `(`/`[`/`{` SUPPRESS layout until matched;
// blank/comment-only lines and line continuations are skipped; trailing DEDENTs are
// emitted at EOF. This is the token stream the parser (M2) consumes.
//
fun
pylex_layout
(src: lcsrc, text: strn): pytokenlst
//
(* ****** ****** *)
//
// ---- pretty-printing (pylexing_print.dats) ---------------------------------
//
// For golden tests + M2 debugging. `pytoken_fprint` prints `KIND@span`;
// `pytokenlst_fprint` prints one token per line.
//
fun
ptnode_fprint(out: FILR, nod: ptnode): void
fun
pytoken_fprint(out: FILR, tok: pytoken): void
fun
pytokenlst_fprint(out: FILR, toks: pytokenlst): void
//
(* ****** ****** *)
(*
end of [frontend/SATS/pylexing.sats]
*)
