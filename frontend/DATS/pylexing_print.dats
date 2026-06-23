(* ****** ****** *)
(*
** M1 — Python-surface frontend: token PRETTY-PRINTER (DATS).
**
** For golden tests + M2 debugging. Prints each token as
**     KIND[lexeme]@(r0:c0-r1:c1)
** where (r0:c0) = pbeg (0-based row:byte-col), (r1:c1) = pend, half-open. The
** lexeme is shown only for tokens that carry one (idents, literals, errors).
**
** Spans are read directly off the loctn via the verified locinfo.sats accessors
** (pbeg/pend → postn → nrow/ncol), so the dump is the GROUND TRUTH of the spans.
**
** Output primitives are the prelude's `strn_fprint(strn,FILR)` and
** `gint_fprint$sint(sint,FILR)` (libcats.sats) — argument order is (value, out).
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
// local print helpers (value, out) → ()
//
fun ps(out: FILR, s: strn): void = strn_fprint(s, out)
fun pi(out: FILR, n: sint): void = gint_fprint$sint(n, out)
//
(* ****** ****** *)
//
// the printable name of a kind (without lexeme)
//
fun
ptnode_name(nod: ptnode): strn =
(
case+ nod of
| PT_KW_LET() => "KW_LET"
| PT_KW_MUT() => "KW_MUT"
| PT_KW_VAR() => "KW_VAR"
| PT_KW_DEF() => "KW_DEF"
| PT_KW_IF() => "KW_IF"
| PT_KW_ELIF() => "KW_ELIF"
| PT_KW_ELSE() => "KW_ELSE"
| PT_KW_WHILE() => "KW_WHILE"
| PT_KW_FOR() => "KW_FOR"
| PT_KW_IN() => "KW_IN"
| PT_KW_MATCH() => "KW_MATCH"
| PT_KW_CASE() => "KW_CASE"
| PT_KW_BREAK() => "KW_BREAK"
| PT_KW_CONTINUE() => "KW_CONTINUE"
| PT_KW_RETURN() => "KW_RETURN"
| PT_KW_IMPORT() => "KW_IMPORT"
| PT_KW_FROM() => "KW_FROM"
| PT_KW_INCLUDE() => "KW_INCLUDE"
| PT_KW_TYPE() => "KW_TYPE"
| PT_KW_ENUM() => "KW_ENUM"
| PT_KW_STRUCT() => "KW_STRUCT"
| PT_KW_EXCEPTION() => "KW_EXCEPTION"
| PT_KW_RAISE() => "KW_RAISE"
| PT_KW_TRY() => "KW_TRY"
| PT_KW_EXCEPT() => "KW_EXCEPT"
| PT_KW_AS() => "KW_AS"
| PT_KW_FORALL() => "KW_FORALL"
| PT_KW_EXISTS() => "KW_EXISTS"
| PT_KW_AT() => "KW_AT"
| PT_KW_WHERE() => "KW_WHERE"
| PT_KW_PRIVATE() => "KW_PRIVATE"
| PT_KW_AND() => "KW_AND"
| PT_KW_OR() => "KW_OR"
| PT_KW_NOT() => "KW_NOT"
//
| PT_UIDENT(_) => "UIDENT"
| PT_LIDENT(_) => "LIDENT"
| PT_USCORE() => "USCORE"
//
| PT_INT(_) => "INT"
| PT_FLOAT(_) => "FLOAT"
| PT_STRING(_) => "STRING"
| PT_CHAR(_) => "CHAR"
| PT_TRUE() => "TRUE"
| PT_FALSE() => "FALSE"
//
| PT_PLUS() => "PLUS"
| PT_MINUS() => "MINUS"
| PT_STAR() => "STAR"
| PT_SLASH() => "SLASH"
| PT_SLASH2() => "SLASH2"
| PT_PERCENT() => "PERCENT"
| PT_STAR2() => "STAR2"
| PT_EQEQ() => "EQEQ"
| PT_NEQ() => "NEQ"
| PT_LT() => "LT"
| PT_LTE() => "LTE"
| PT_GT() => "GT"
| PT_GTE() => "GTE"
| PT_EQ() => "EQ"
| PT_COLONEQ() => "COLONEQ"
| PT_MOVE() => "MOVE"
| PT_SWAP() => "SWAP"
| PT_AMP() => "AMP"
| PT_BANG() => "BANG"
| PT_TILDE() => "TILDE"
| PT_FATARROW() => "FATARROW"
| PT_ARROW() => "ARROW"
| PT_COLON() => "COLON"
| PT_AT() => "AT"
| PT_BAR() => "BAR"
| PT_COMMA() => "COMMA"
| PT_DOT() => "DOT"
| PT_LPAREN() => "LPAREN"
| PT_RPAREN() => "RPAREN"
| PT_LBRACK() => "LBRACK"
| PT_RBRACK() => "RBRACK"
| PT_LBRACE() => "LBRACE"
| PT_RBRACE() => "RBRACE"
//
| PT_NL_RAW() => "NL_RAW"
| PT_NEWLINE() => "NEWLINE"
| PT_INDENT() => "INDENT"
| PT_DEDENT() => "DEDENT"
| PT_EOF() => "EOF"
//
| PT_ERROR(_) => "ERROR"
//
| PT_QMARK() => "QMARK"  // QMARK-TYPE: the `?` static/top-view operator
) (* end of [ptnode_name] *)
//
(* ****** ****** *)
//
// the lexeme carried by a kind, as an option-like: prints "[lexeme]" for the
// lexeme-bearing kinds; nothing for the rest.
//
fun
ptnode_print_lexeme(out: FILR, nod: ptnode): void =
(
case+ nod of
| PT_UIDENT(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| PT_LIDENT(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| PT_INT(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| PT_FLOAT(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| PT_STRING(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| PT_CHAR(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| PT_ERROR(s) => (ps(out, "["); ps(out, s); ps(out, "]"))
| _ => ()
) (* end of [ptnode_print_lexeme] *)
//
(* ****** ****** *)
//
#implfun
ptnode_fprint(out, nod) =
  (ps(out, ptnode_name(nod)); ptnode_print_lexeme(out, nod))
//
(* ****** ****** *)
//
// print a postn as "row:col" (0-based; col in bytes)
//
fun
postn_print(out: FILR, p: postn): void =
  (pi(out, p.nrow()); ps(out, ":"); pi(out, p.ncol()))
//
(* ****** ****** *)
//
#implfun
pytoken_fprint(out, tok) = let
  val nod = tok.node()
  val loc = tok.loctn()
  val pb  = loc.pbeg()
  val pe  = loc.pend()
in
  ptnode_fprint(out, nod);
  ps(out, "@(");
  postn_print(out, pb);
  ps(out, "-");
  postn_print(out, pe);
  ps(out, ")")
end (* end of [pytoken_fprint] *)
//
(* ****** ****** *)
//
#implfun
pytokenlst_fprint(out, toks) =
(
case+ toks of
| list_nil() => ()
| list_cons(tk, rest) =>
  (pytoken_fprint(out, tk); ps(out, "\n"); pytokenlst_fprint(out, rest))
) (* end of [pytokenlst_fprint] *)
//
(* ****** ****** *)
//
(*
end of [frontend/DATS/pylexing_print.dats]
*)
