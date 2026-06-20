(* ****** ****** *)
(*
** M2 — Python-surface frontend: shared parser UTILITIES (DATS).
**
** The token-stream cursor + error-recovery primitives shared by the three parser
** DATS (staexp / dynexp / decl00). The `pstate` (remaining tokens + reversed
** diagnostics) is threaded BY VALUE — pure, re-entrant (plan §6.2); there is no
** module-global parser state.
**
** ERROR RECOVERY: the parser NEVER throws. `ps_diag` records a recovery message;
** `ps_resync` drops tokens to the next NEWLINE (or stops at DEDENT/EOF without
** consuming them — those close the enclosing suite). Mirrors the compiler's …errck
** spirit.
**
** PURELY ADDITIVE; consumes pyparsing.sats / pylexing.sats / locinfo.sats read-only.
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
#staload "./../SATS/pyparsing.sats"
//
(* ****** ****** *)
//
// ---- node location accessors (uniform getter; the SATS declares these) ------
//
#implfun
pyexp_loctn(e) =
(
case+ e of
| PyEvar(loc, _) => loc       | PyEcon(loc, _) => loc
| PyElit(loc, _) => loc       | PyEwild(loc) => loc
| PyEapp(loc, _, _) => loc    | PyEbin(loc, _, _, _) => loc
| PyEuna(loc, _, _) => loc    | PyEif(loc, _, _) => loc
| PyEmatch(loc, _, _) => loc  | PyEtup(loc, _) => loc
| PyElist(loc, _) => loc      | PyErec(loc, _) => loc
| PyEfield(loc, _, _) => loc  | PyEindex(loc, _, _) => loc
| PyElam(loc, _, _) => loc    | PyEann(loc, _, _) => loc
| PyEerror(loc, _) => loc
)
//
#implfun
pypat_loctn(p) =
(
case+ p of
| PyPvar(loc, _) => loc       | PyPwild(loc) => loc
| PyPcon(loc, _, _) => loc    | PyPtup(loc, _) => loc
| PyPrec(loc, _) => loc       | PyPlit(loc, _) => loc
| PyPas(loc, _, _) => loc     | PyPann(loc, _, _) => loc
| PyPerror(loc, _) => loc
)
//
#implfun
pytyp_loctn(t) =
(
case+ t of
| PyTcon(loc, _, _) => loc    | PyTvar(loc, _) => loc
| PyTidx(loc, _) => loc       | PyTfun(loc, _, _) => loc
| PyTtup(loc, _) => loc       | PyTrec(loc, _) => loc
| PyTerror(loc, _) => loc
)
//
#implfun
pystmt_loctn(s) =
(
case+ s of
| PyDlet(loc, _, _, _, _) => loc | PySreassign(loc, _, _) => loc
| PySexpr(loc, _) => loc         | PySif(loc, _, _) => loc
| PySwhile(loc, _, _, _) => loc  | PySfor(loc, _, _, _, _) => loc
| PySbreak(loc) => loc           | PyScontinue(loc) => loc
| PySreturn(loc, _) => loc       | PySblock(loc, _) => loc
| PySdecl(loc, _) => loc         | PySerror(loc, _) => loc
)
//
#implfun
pydecl_loctn(d) =
(
case+ d of
| PyCfun(loc, _, _, _, _, _) => loc | PyCtype(loc, _, _, _) => loc
| PyCimport(loc, _) => loc          | PyCstmt(loc, _) => loc
| PyCerror(loc, _) => loc
)
//
(* ****** ****** *)
//
// ---- pstate cursor primitives ----------------------------------------------
//
#implfun
ps_peek(st) = let
  val+ PState(toks, _) = st
in
  case+ toks of
  | list_cons(tk, _) => tk.node()
  | list_nil() => PT_EOF()
end
//
#implfun
ps_peek_loctn(st) = let
  val+ PState(toks, _) = st
in
  case+ toks of
  | list_cons(tk, _) => tk.loctn()
  | list_nil() => loctn_dummy()
end
//
#implfun
ps_peek2(st) = let
  val+ PState(toks, _) = st
in
  case+ toks of
  | list_cons(_, rest) =>
    (case+ rest of list_cons(tk, _) => tk.node() | list_nil() => PT_EOF())
  | list_nil() => PT_EOF()
end
//
#implfun
ps_advance(st) = let
  val+ PState(toks, ds) = st
in
  case+ toks of
  | list_cons(_, rest) => PState(rest, ds)
  | list_nil() => st
end
//
#implfun
ps_at_eof(st) = (case+ ps_peek(st) of PT_EOF() => true | _ => false)
//
#implfun
ps_diag(st, loc, msg) = let
  val+ PState(toks, ds) = st
in
  PState(toks, list_cons(PyDiag(loc, msg), ds))
end
//
#implfun
loc_span(l1, l2) = add_loctn_loctn(l1, l2)
//
(* ****** ****** *)
//
// ---- layout-aware skipping + resync ----------------------------------------
//
// is this a layout token (NEWLINE/INDENT/DEDENT)?
fun is_layout(nod: ptnode): bool =
(
case+ nod of
| PT_NEWLINE() => true | PT_INDENT() => true | PT_DEDENT() => true | _ => false
)
//
// skip leading NEWLINE/INDENT/DEDENT tokens (e.g. blank logical lines between decls).
// NOTE: callers that need to TRACK indent (suite parsing) must NOT use this — they
// consume INDENT/DEDENT explicitly. This is for the module top level, where stray
// NEWLINEs separate decls.
#implfun
ps_skip_newlines(st) =
(
case+ ps_peek(st) of
| PT_NEWLINE() => ps_skip_newlines(ps_advance(st))
| _ => st
)
//
// resync: consume up to AND INCLUDING the next NEWLINE; stop (without consuming) at
// DEDENT or EOF (those terminate the enclosing suite, so the caller's suite loop
// handles them). This is the non-fail-fast recovery point (§ error recovery).
#implfun
ps_resync(st) =
(
case+ ps_peek(st) of
| PT_NEWLINE() => ps_advance(st)       // consume the NEWLINE, recovery done
| PT_DEDENT() => st                    // leave for the suite loop
| PT_EOF() => st                       // leave for the top loop
| _ => ps_resync(ps_advance(st))       // drop the offending token, keep going
)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyparsing_util.dats]
*)
