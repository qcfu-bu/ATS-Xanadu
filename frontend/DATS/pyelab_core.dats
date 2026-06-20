(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the IMPERATIVE ELABORATOR — core (DATS).
**
** The total PyAST -> PyCore pass (LOOP-DESUGARING). This file holds: expression/pattern
** elaboration, the §4 accumulator-set analysis, the §3.1 control-flag analysis, the §5.1
** control-pure fast path, the §5.4 function epilogue, and the accumulator-tuple builders.
** The flow-mode suite elaboration + the §5.2/§5.3 loop combinators are in pyelab_loop.dats;
** the module driver + public entry are in pyelab_decl.dats.
**
** ATS3-dialect structure rule (M2 Δ3): an `#implfun` must NOT head a `fun ... and ...`
** group that contains non-`#impl` helpers (the helper is left unresolved). So every
** mutually-recursive worker is a plain `fun el_* / and ...` group, and the SATS entries
** (elab_exp, elab_pure, ...) are thin standalone `#implfun` wrappers at the end.
**
** PURE / re-entrant; consumes pyparsing.sats / pycore.sats / pyelab.sats read-only.
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
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
//
(* ****** ****** *)
//
#define LOOPNAME "loop"
//
fun el_dloc0(): loctn = loctn_dummy()
//
(* ****** ****** *)
//
// ---- operator-symbol strings (a surface binop -> a prelude var reference) ------------
//
fun
bop_sym(b: pybop): strn =
(
case+ b of
| PyBor()   => "or"   | PyBand()  => "and"
| PyBeq()   => "=="    | PyBne()   => "!="
| PyBlt()   => "<"     | PyBle()   => "<="
| PyBgt()   => ">"     | PyBge()   => ">="
| PyBadd()  => "+"     | PyBsub()  => "-"
| PyBmul()  => "*"     | PyBdiv()  => "/"
| PyBmod()  => "%"     | PyBfdiv() => "//"
| PyBpow()  => "**"
)
//
fun
uop_sym(u: pyuop): strn =
( case+ u of PyUnot() => "not" | PyUneg() => "-" | PyUpos() => "+" )
//
(* ****** ****** *)
//
// ---- §4 accumulator-set analysis: assigned-mut names of a suite ----------------------
//
fun
lv_name(e: pyexp): strn =
( case+ e of PyEvar(_, nm) => nm | _ => "" )
//
fun
el_assigned_stmt(s: pystmt): nameset =
(
case+ s of
| PySreassign(_, lv, _) =>
    let val nm = lv_name(lv) in if strn_eq(nm, "") then list_nil() else list_sing(nm) end
| PySif(_, gs, els) => nameset_union(el_assigned_guards(gs), el_assigned_else(els))
| PySwhile(_, _, body, els) => nameset_union(el_assigned_stmts(body), el_assigned_else(els))
| PySfor(_, _, _, body, els) => nameset_union(el_assigned_stmts(body), el_assigned_else(els))
| PySblock(_, body) => el_assigned_stmts(body)
| _ => list_nil()
)
//
and
el_assigned_guards(gs: list(pyguard)): nameset =
(
case+ gs of
| list_nil() => list_nil()
| list_cons(PyGuard(_, _, body), rest) =>
    nameset_union(el_assigned_stmts(body), el_assigned_guards(rest))
)
//
and
el_assigned_else(els: pystmtlstopt): nameset =
( case+ els of PyElseNone() => list_nil() | PyElseSome(body) => el_assigned_stmts(body) )
//
and
el_assigned_stmts(ss: list(pystmt)): nameset =
(
case+ ss of
| list_nil() => list_nil()
| list_cons(s, rest) => nameset_union(el_assigned_stmt(s), el_assigned_stmts(rest))
)
//
(* ****** ****** *)
//
// ---- §3.1 control-flag analysis ----------------------------------------------
//
fun b_or(a: bool, b: bool): bool = if a then true else b
//
fun fl_or(a: pcflags, b: pcflags): pcflags = @(b_or(a.0, b.0), b_or(a.1, b.1), b_or(a.2, b.2))
fun fl_none(): pcflags = @(false, false, false)
//
fun
el_flags_stmt(s: pystmt): pcflags =
(
case+ s of
| PySreturn(_, _) => @(true, false, false)
| PySbreak(_)     => @(false, true, false)
| PyScontinue(_)  => @(false, false, true)
| PySif(_, gs, els) => fl_or(el_flags_guards(gs), el_flags_else(els))
| PySwhile(_, _, body, els) =>
    let val fb = fl_or(el_flags_stmts(body), el_flags_else(els)) in @(fb.0, false, false) end
| PySfor(_, _, _, body, els) =>
    let val fb = fl_or(el_flags_stmts(body), el_flags_else(els)) in @(fb.0, false, false) end
| PySblock(_, body) => el_flags_stmts(body)
| _ => fl_none()
)
//
and
el_flags_guards(gs: list(pyguard)): pcflags =
(
case+ gs of
| list_nil() => fl_none()
| list_cons(PyGuard(_, _, body), rest) => fl_or(el_flags_stmts(body), el_flags_guards(rest))
)
//
and
el_flags_else(els: pystmtlstopt): pcflags =
( case+ els of PyElseNone() => fl_none() | PyElseSome(body) => el_flags_stmts(body) )
//
and
el_flags_stmts(ss: list(pystmt)): pcflags =
(
case+ ss of
| list_nil() => fl_none()
| list_cons(s, rest) => fl_or(el_flags_stmt(s), el_flags_stmts(rest))
)
//
fun control_any(fl: pcflags): bool = b_or(fl.0, b_or(fl.1, fl.2))
//
(* ****** ****** *)
//
// ---- literal / pattern elaboration -------------------------------------------
//
fun
el_lit(lit: pylit): pclit =
(
case+ lit of
| PyLint(loc, s)  => PCLint(loc, s)  | PyLflt(loc, s)  => PCLflt(loc, s)
| PyLstr(loc, s)  => PCLstr(loc, s)  | PyLchr(loc, s)  => PCLchr(loc, s)
| PyLbool(loc, b) => PCLbool(loc, b)
)
//
fun
el_pat(p: pypat): pcpat =
(
case+ p of
| PyPvar(loc, nm) => PCPvar(loc, nm)
| PyPwild(loc) => PCPwild(loc)
| PyPcon(loc, nm, args) => PCPcon(loc, nm, el_patlst(args))
| PyPtup(loc, ps0) => PCPtup(loc, el_patlst(ps0))
| PyPrec(loc, fs) => PCPrec(loc, el_pfields(fs))
| PyPlit(loc, lit) => PCPlit(loc, el_lit(lit))
| PyPas(_, p1, _) => el_pat(p1)
| PyPann(_, p1, _) => el_pat(p1)
| PyPerror(loc, _) => PCPvar(loc, "_error")
)
//
and
el_patlst(ps0: list(pypat)): list(pcpat) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(p, rest) => list_cons(el_pat(p), el_patlst(rest))
)
//
and
el_pfields(fs: list(pypfield)): list(pcpfield) =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PyPField(loc, nm, p), rest) =>
    list_cons(PCPField(loc, nm, el_pat(p)), el_pfields(rest))
)
//
(* ****** ****** *)
//
// ---- accumulator-tuple builders ---------------------------------------------
//
fun
el_accs_exp(loc: loctn, accs: nameset): pcexp =
(
case+ accs of
| list_nil() => PCEunit(loc)
| list_cons(nm, list_nil()) => PCEvar(loc, nm)
| _ => PCEtup(loc, el_accs_var_exps(loc, accs))
)
//
and
el_accs_var_exps(loc: loctn, accs: nameset): list(pcexp) =
(
case+ accs of
| list_nil() => list_nil()
| list_cons(nm, rest) => list_cons(PCEvar(loc, nm), el_accs_var_exps(loc, rest))
)
//
fun
el_accs_pat(loc: loctn, accs: nameset): pcpat =
(
case+ accs of
| list_nil() => PCPwild(loc)
| list_cons(nm, list_nil()) => PCPvar(loc, nm)
| _ => PCPtup(loc, el_accs_var_pats(loc, accs))
)
//
and
el_accs_var_pats(loc: loctn, accs: nameset): list(pcpat) =
(
case+ accs of
| list_nil() => list_nil()
| list_cons(nm, rest) => list_cons(PCPvar(loc, nm), el_accs_var_pats(loc, rest))
)
//
fun
el_add_pat_names(muts: nameset, p: pypat): nameset =
(
case+ p of
| PyPvar(_, nm) => nameset_add(muts, nm)
| PyPtup(_, ps0) => el_add_pat_names_lst(muts, ps0)
| _ => muts
)
//
and
el_add_pat_names_lst(muts: nameset, ps0: list(pypat)): nameset =
(
case+ ps0 of
| list_nil() => muts
| list_cons(p, rest) => el_add_pat_names_lst(el_add_pat_names(muts, p), rest)
)
//
(* ****** ****** *)
//
// ---- EXPRESSION elaboration (mutually recursive: exp -> func_body -> pure -> exp) ----
//
fun
el_exp(e: pyexp): pcexp =
(
case+ e of
| PyEvar(loc, nm) => PCEvar(loc, nm)
| PyEcon(loc, nm) => PCEcon(loc, nm)
| PyElit(loc, lit) => PCElit(loc, el_lit(lit))
| PyEwild(loc) => PCEunit(loc)
| PyEapp(loc, hd, args) => PCEapp(loc, el_exp(hd), el_explst(args))
| PyEbin(loc, b, l, r) => el_binop(loc, b, l, r)
| PyEuna(loc, u, e1) => el_unop(loc, u, e1)
| PyEif(loc, gs, els) => el_eguards(gs, el_exp(els))
| PyEmatch(loc, scrut, arms) => PCEcase(loc, el_exp(scrut), el_arms(arms))
| PyEtup(loc, es) => PCEtup(loc, el_explst(es))
| PyElist(loc, es) => PCElist(loc, el_explst(es))
| PyErec(loc, fs) => PCErec(loc, el_efields(fs))
| PyEfield(loc, e1, nm) => PCEfield(loc, el_exp(e1), nm)
| PyEindex(loc, e1, ix) =>
    PCEapp(loc, PCEvar(loc, "[]"), list_cons(el_exp(e1), list_sing(el_exp(ix))))
| PyElam(loc, params, body) => PCElam(loc, el_param_names(params), el_func_body(loc, body))
| PyEann(_, e1, _) => el_exp(e1)
| PyEerror(loc, msg) => PCEerror(loc, msg)
)
//
and
el_explst(es: list(pyexp)): list(pcexp) =
(
case+ es of
| list_nil() => list_nil()
| list_cons(e, rest) => list_cons(el_exp(e), el_explst(rest))
)
//
and
el_efields(fs: list(pyefield)): list(pcefield) =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PyEField(loc, nm, e), rest) =>
    list_cons(PCEField(loc, nm, el_exp(e)), el_efields(rest))
)
//
and
el_param_names(ps0: list(pyparam)): list(strn) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(PyParam(_, nm, _), rest) => list_cons(nm, el_param_names(rest))
)
//
and
el_binop(loc: loctn, b: pybop, l: pyexp, r: pyexp): pcexp =
(
case+ b of
| PyBand() => PCEif(loc, el_exp(l), el_exp(r), PCElit(loc, PCLbool(loc, false)))
| PyBor()  => PCEif(loc, el_exp(l), PCElit(loc, PCLbool(loc, true)), el_exp(r))
| _ => PCEapp(loc, PCEvar(loc, bop_sym(b)), list_cons(el_exp(l), list_sing(el_exp(r))))
)
//
and
el_unop(loc: loctn, u: pyuop, e1: pyexp): pcexp =
(
case+ u of
| PyUnot() => PCEif(loc, el_exp(e1), PCElit(loc, PCLbool(loc, false)), PCElit(loc, PCLbool(loc, true)))
| _ => PCEapp(loc, PCEvar(loc, uop_sym(u)), list_sing(el_exp(e1)))
)
//
and
el_eguards(gs: list(pyguard), els: pcexp): pcexp =
(
case+ gs of
| list_nil() => els
| list_cons(PyGuard(loc, c, body), rest) =>
    PCEif(loc, el_exp(c), el_func_body(loc, body), el_eguards(rest, els))
)
//
and
el_arms(arms: list(pyarm)): list(pcarm) =
(
case+ arms of
| list_nil() => list_nil()
| list_cons(PyArm(loc, p, gopt, body), rest) =>
  let
    val pc_p = el_pat(p)
    val pc_body = el_func_body(loc, body)
    // architect ruling (iv): PRESERVE the surface guard — elaborate it and attach it to
    // the arm. Do NOT desugar to an inner `if` (a failed guard must fall through to the
    // NEXT arm; M4 lowers it to ATS's native guarded clause).
    val pc_g =
      (case+ gopt of
       | PyExpNone()   => PCEGNone()
       | PyExpSome(g)  => PCEGSome(el_exp(g)))
  in
    list_cons(PCArm(loc, pc_p, pc_g, pc_body), el_arms(rest))
  end
)
//
// §5.4 function/branch-body epilogue.
and
el_func_body(loc: loctn, body: list(pystmt)): pcexp =
let
  val fl = el_flags_stmts(body)
in
  if ~(fl.0)  // no return: control-pure body — fast path with the tail value.
    then el_pure(body, list_nil(), el_suite_tail(loc, body))
  else // may return: flow mode (no accumulators) + the §5.4 epilogue match.
    let
      val flowexp = elab_flow(body, list_nil(), list_nil())
      val a_ret =
        PCArm(el_dloc0(), PCPcon(el_dloc0(), "flow_return", list_sing(PCPvar(el_dloc0(), "r"))),
              PCEGNone(), PCEvar(el_dloc0(), "r"))
      val a_next =
        PCArm(el_dloc0(), PCPcon(el_dloc0(), "flow_next", list_sing(PCPwild(el_dloc0()))),
              PCEGNone(), el_suite_tail(loc, body))
    in
      PCEcase(loc, flowexp, list_cons(a_ret, list_sing(a_next)))
    end
end
//
and
el_suite_tail(loc: loctn, body: list(pystmt)): pcexp =
(
case+ body of
| list_nil() => PCEunit(loc)
| list_cons(s, list_nil()) =>
    (case+ s of PySexpr(_, e) => el_exp(e) | _ => PCEunit(pystmt_loctn(s)))
| list_cons(_, rest) => el_suite_tail(loc, rest)
)
//
(* ****** ****** *)
//
// ---- §5.1 control-pure fast path --------------------------------------------
//
and
el_pure(ss: list(pystmt), muts: nameset, tail: pcexp): pcexp =
(
case+ ss of
| list_nil() => tail
| list_cons(s, rest) =>
  (
  case+ s of
  | PyDlet(loc, ismut, p, _, rhs) =>
      let val newmuts = (if ismut then el_add_pat_names(muts, p) else muts) in
        PCElet(loc, el_pat(p), el_exp(rhs), el_pure(rest, newmuts, tail))
      end
  | PySreassign(loc, lv, rhs) =>
      let val nm = lv_name(lv) in
        if strn_eq(nm, "")
          then PCEseq(loc, PCEapp(loc, PCEvar(loc, "set!"),
                                  list_cons(el_exp(lv), list_sing(el_exp(rhs)))),
                      el_pure(rest, muts, tail))
        else if nameset_mem(muts, nm)
          then PCElet(loc, PCPvar(pyexp_loctn(lv), nm), el_exp(rhs), el_pure(rest, muts, tail))
        else PCEseq(loc, PCEerror(loc, strn_append("reassignment to non-mut binding: ", nm)),
                    el_pure(rest, muts, tail))
      end
  | PySexpr(loc, e) =>
      // M4 FIX: the LAST expression-statement of a suite IS the suite's tail value (el_suite_tail
      // already returns it). Emitting it ALSO as a PCEseq init double-evaluates it AND forces the
      // first copy to `void` (D2Eseqn checks its init list in effect position) — a spurious
      // type error on every value-returning body (match/if/tuple/record arms). When this is the
      // final statement (rest = nil), produce the tail directly; otherwise it is a genuine
      // effect-then-continue, so keep the seq. (Mirrors trans12: a tail expression is not seq'd.)
      (case+ rest of
       | list_nil() => tail
       | list_cons(_, _) => PCEseq(loc, el_exp(e), el_pure(rest, muts, tail)))
  | PySif(loc, gs, els) => el_pure_if(loc, gs, els, muts, rest, tail)
  | PySwhile(loc, cond, body, wels) =>
      elab_while_value(loc, cond, body, wels, muts, el_pure(rest, muts, tail))
  | PySfor(loc, pat, iter, body, fels) =>
      elab_for_value(loc, pat, iter, body, fels, muts, el_pure(rest, muts, tail))
  | PySblock(loc, body) => el_pure(body, muts, el_pure(rest, muts, tail))
  | PySdecl(loc, d) => el_local_decl(loc, d, el_pure(rest, muts, tail))
  | PySreturn(loc, _) => PCEerror(loc, "return outside a function")
  | PySbreak(loc) => PCEerror(loc, "break outside a loop")
  | PyScontinue(loc) => PCEerror(loc, "continue outside a loop")
  | PySerror(loc, msg) => PCEseq(loc, PCEerror(loc, msg), el_pure(rest, muts, tail))
  )
)
//
and
el_pure_if
(loc: loctn, gs: list(pyguard), els: pystmtlstopt, muts: nameset,
 rest: list(pystmt), tail: pcexp): pcexp =
(
case+ gs of
| list_nil() =>
    (case+ els of
     | PyElseNone() => el_pure(rest, muts, tail)
     | PyElseSome(body) => el_pure(body, muts, el_pure(rest, muts, tail)))
| list_cons(PyGuard(gloc, c, body), grest) =>
    PCEif(gloc, el_exp(c),
          el_pure(body, muts, el_pure(rest, muts, tail)),
          el_pure_if(loc, grest, els, muts, rest, tail))
)
//
and
el_local_decl(loc: loctn, d: pydecl, kont: pcexp): pcexp =
(
case+ d of
| PyCfun(floc, nm, _, params, _, body) =>
    PCEletfun(loc,
      list_sing(PCFundcl(floc, nm, el_param_names(params), el_func_body(floc, body), false)),
      kont)
| _ => kont
)
//
(* ****** ****** *)
//
// ---- thin #implfun wrappers for the SATS entries ---------------------------
//
#implfun
elab_else(loc, body, muts) = el_pure(body, muts, PCEunit(loc))
//
#implfun el_dloc() = el_dloc0()
#implfun assigned_stmts(ss) = el_assigned_stmts(ss)
#implfun flags_stmts(ss) = el_flags_stmts(ss)
#implfun elab_exp(e) = el_exp(e)
#implfun elab_pat(p) = el_pat(p)
#implfun elab_func_body(loc, body) = el_func_body(loc, body)
#implfun elab_pure(ss, muts, tail) = el_pure(ss, muts, tail)
#implfun accs_tuple_exp(loc, accs) = el_accs_exp(loc, accs)
#implfun accs_tuple_pat(loc, accs) = el_accs_pat(loc, accs)
#implfun lvalue_name(e) = lv_name(e)
#implfun add_pat_names(muts, p) = el_add_pat_names(muts, p)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_core.dats]
*)
