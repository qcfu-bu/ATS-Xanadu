(* ****** ****** *)
(*
** M1 — Python-surface frontend: the LAYOUT PASS (DATS).
**
** The CPython off-side rule. Consumes the RAW token stream (from pylex_text:
** real tokens + PT_NL_RAW physical-newline markers + a trailing PT_EOF) and emits
** the LOGICAL token stream the parser (M2) consumes: real tokens interleaved with
** PT_NEWLINE / PT_INDENT / PT_DEDENT, ending in PT_EOF.
**
** ===================== the rules we implement (and chose) =====================
**
** R1. Indent stack. A stack of indentation byte-columns, bottom = 0. The TOP is
**     the current block's indent.
**
** R2. Logical-line boundary. At the start of each LOGICAL line (one not joined by
**     brackets or a continuation — those are already handled by the raw scanner /
**     bracket depth here), compare the line's leading indentation `ind` (the byte
**     column of its first real token) to the stack top `t`:
**       ind  > t  → push ind, emit ONE PT_INDENT.
**       ind == t  → emit nothing.
**       ind  < t  → pop while top > ind, emitting ONE PT_DEDENT per pop. If we land
**                   on a column that does NOT equal `ind`, the indentation is
**                   inconsistent; CPython raises — we instead emit the DEDENTs to
**                   the nearest enclosing level and continue (non-fail-fast; M2 can
**                   flag it). (Documented deviation: recover, don't throw.)
**
** R3. NEWLINE. A PT_NL_RAW that ENDS a non-blank logical line (we are at bracket
**     depth 0) emits ONE PT_NEWLINE. Consecutive PT_NL_RAW (blank lines) and
**     comment-only lines emit NOTHING (the raw scanner already dropped comments, so
**     a comment-only line shows up as an immediate PT_NL_RAW → blank).
**
** R4. Bracket suppression. While bracket depth > 0 (inside (), [], {}), PT_NL_RAW
**     is DROPPED (implicit line join) and NO INDENT/DEDENT is computed — layout is
**     suppressed, exactly as in Python. Depth tracks ( [ { vs ) ] }.
**     [NOTE: SURFACE-GRAMMAR §3 says a block-opener (`:`/`=>`) may still open a
**      layout context even inside brackets (trailing block lambdas). That nuance is
**      an OPEN item in the grammar (§3, "finalized during M1–M2") and belongs to the
**      parser/lambda handling, NOT the byte-level layout pass. v1 layout takes the
**      standard CPython rule: brackets fully suppress layout. FLAGGED in the report.]
**
** R5. EOF. At end of input: if the last logical line was non-empty, emit a final
**     PT_NEWLINE; then emit a PT_DEDENT for every indent level above 0 (closing all
**     open blocks); then PT_EOF.
**
** R6. Leading blank/indented-blank lines. A line containing only whitespace then a
**     newline is blank → no NEWLINE, no INDENT/DEDENT (its indentation is ignored).
**     Handled naturally: indentation is computed from the FIRST REAL token of a
**     line; a line whose first non-NL token is another PT_NL_RAW is blank.
**
** Synthetic tokens carry a ZERO-WIDTH loctn at the relevant position (the column
** where the change is detected) so they still report on the .py source.
**
** PURE per call (plan §6.2): pylex_layout runs pylex_text then this transform;
** all state (indent stack, bracket depth, "at line start") is local to the call.
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
// is this raw node a physical newline?
fun is_nlraw(nod: ptnode): bool = (case+ nod of PT_NL_RAW() => true | _ => false)
fun is_eof(nod: ptnode): bool = (case+ nod of PT_EOF() => true | _ => false)
//
// bracket-depth delta of a node: +1 for open, -1 for close, 0 otherwise.
fun brk_delta(nod: ptnode): sint =
(
case+ nod of
| PT_LPAREN() => 1 | PT_LBRACK() => 1 | PT_LBRACE() => 1
| PT_RPAREN() => (-1) | PT_RBRACK() => (-1) | PT_RBRACE() => (-1)
| _ => 0
)
//
// a zero-width synthetic token at the pbeg of `loc`
fun synth(nod: ptnode, loc: loctn): pytoken =
  PYTOKEN(nod, loctn_make_arg3(loc.lsrc(), loc.pbeg(), loc.pbeg()))
//
(* ****** ****** *)
//
// emit n PT_DEDENTs (zero-width at loc) onto acc (REVERSED accumulator)
fun
emit_dedents
(acc: pytokenlst, n: sint, loc: loctn): pytokenlst =
  if n <= 0 then acc
  else emit_dedents(list_cons(synth(PT_DEDENT(), loc), acc), n - 1, loc)
//
(* ****** ****** *)
//
// ---- the indent stack (a plain sint list; head = TOP) ----------------------
//
// process a new logical line whose leading indentation column is `ind`, at loc
// `loc`. Returns (new-stack, acc-with-INDENT/DEDENTs-appended). Compares to top.
//
fun
do_indent
( stk: list(sint)
, acc: pytokenlst
, ind: sint, loc: loctn): @(list(sint), pytokenlst) = let
  val top = (case+ stk of list_cons(t, _) => t | list_nil() => 0)
in
  if ind > top then
    @(list_cons(ind, stk), list_cons(synth(PT_INDENT(), loc), acc))
  else if ind = top then
    @(stk, acc)
  else // ind < top: pop while top > ind, one DEDENT per pop
    let
      fun
      pop
      ( stk: list(sint)
      , acc: pytokenlst, k: sint): @(list(sint), pytokenlst, sint) =
      (
        case+ stk of
        | list_cons(t, rest) =>
          if t > ind
            then pop(rest, list_cons(synth(PT_DEDENT(), loc), acc), k + 1)
            else @(stk, acc, k)
        | list_nil() => @(stk, acc, k)
      )
      val @(stk1, acc1, _) = pop(stk, acc, 0)
    in
      @(stk1, acc1)
    end
end (* end of [do_indent] *)
//
(* ****** ****** *)
//
// ---- the main layout transform ---------------------------------------------
//
// State:
//   stk    : indent stack (head = current block indent), bottom 0 implicit/explicit.
//   depth  : bracket nesting depth (>0 ⇒ suppress layout).
//   bol    : "beginning of (logical) line" — the NEXT real token determines indent.
//   pend   : whether a PT_NEWLINE is pending to be emitted at the next line break
//            (i.e. the current logical line produced at least one real token).
//   acc    : REVERSED output accumulator.
//
fun
layout_loop
( toks: pytokenlst
, stk: list(sint)
, depth: sint
, bol: bool
, pend: bool
, acc: pytokenlst): pytokenlst = let
in
//
case+ toks of
//
| list_nil() =>
  // (should not happen: raw stream ends in PT_EOF) — close out gracefully.
  let
    val acc1 = if pend then list_cons(synth(PT_NEWLINE(), loctn_dummy()), acc) else acc
    // emit one DEDENT per OPEN level (all levels ABOVE the base column 0).
    val acc2 = emit_dedents(acc1, stklen(stk) - 1, loctn_dummy())
  in list_reverse(list_cons(synth(PT_EOF(), loctn_dummy()), acc2)) end
//
| list_cons(tk, rest) =>
  let
    val nod = tk.node()
    val loc = tk.loctn()
  in
  //
  if is_eof(nod) then
    // R5. EOF: optional final NEWLINE, then DEDENT per OPEN level, then EOF.
    // (stklen-1: the base column-0 level is never closed, so it gets no DEDENT.)
    let
      val acc1 = if pend then list_cons(synth(PT_NEWLINE(), loc), acc) else acc
      val acc2 = emit_dedents(acc1, stklen(stk) - 1, loc)
    in list_reverse(list_cons(PYTOKEN(PT_EOF(), loc), acc2)) end
  //
  else if is_nlraw(nod) then
    (
      if depth > 0 then
        // R4. inside brackets: drop the newline (implicit join), stay un-bol.
        layout_loop(rest, stk, depth, bol, pend, acc)
      else if bol then
        // a newline while still at beginning-of-line ⇒ blank line: emit nothing.
        layout_loop(rest, stk, depth, true, pend, acc)
      else
        // R3. end of a non-empty logical line: emit NEWLINE, back to bol.
        layout_loop
        ( rest, stk, depth, true, false
        , list_cons(synth(PT_NEWLINE(), loc), acc) )
    )
  //
  else
    // a REAL token.
    let
      // if we are at beginning-of-line AND not inside brackets, this token's column
      // sets the line's indentation (R2). Otherwise no indent computation.
      val at_line_start = (if bol then (depth = 0) else false)
      val @(stk1, acc1) =
        if at_line_start
          then do_indent(stk, acc, (loc.pbeg()).ncol(), loc)
          else @(stk, acc)
      val depth1 = depth + brk_delta(nod)
      // emit the real token; we are now mid-line; a NEWLINE will be pending.
      val acc2 = list_cons(tk, acc1)
    in
      layout_loop(rest, stk1, depth1, false, true, acc2)
    end
  //
  end
//
end (* end of [layout_loop] *)
//
(* ****** ****** *)
//
// stack length helper
and
stklen(stk: list(sint)): sint =
(case+ stk of list_cons(_, r) => 1 + stklen(r) | list_nil() => 0)
//
(* ****** ****** *)
//
// the public layout entry: raw scan + off-side rule.
//
#implfun
pylex_layout(src, text) = let
  val raw = pylex_text(src, text)
in
  // initial stack: just [0] (column-0 base block); bol=true; nothing pending yet.
  layout_loop(raw, list_cons(0, list_nil()), 0, true, false, list_nil())
end (* end of [pylex_layout] *)
//
(* ****** ****** *)
//
(*
end of [frontend/DATS/pylayout.dats]
*)
