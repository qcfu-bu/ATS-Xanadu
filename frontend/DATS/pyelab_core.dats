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
| PyPcon(loc, nm, sargs, args) => PCPcon(loc, nm, sargs, el_patlst(args))
| PyPtup(loc, ps0) => PCPtup(loc, el_patlst(ps0))
| PyPrec(loc, knd, fs) => PCPrec(loc, knd, el_pfields(fs))
| PyPlit(loc, lit) => PCPlit(loc, el_lit(lit))
// M7: `p as x` -> PCPas(loc, x, <elaborated p>). The surface PyPas is `(loc, inner, name)`;
// PCPas reorders to `(loc, name, inner)`. The binding is no longer dropped — M3 lowers it to a
// D2Prfpt so `x` is usable in the arm body.
| PyPas(loc, p1, nm) => PCPas(loc, nm, el_pat(p1))
| PyPann(_, p1, _) => el_pat(p1)
| PyPbang(loc, p1) => PCPbang(loc, el_pat(p1))
| PyPflat(loc, p1) => PCPflat(loc, el_pat(p1))
// B-LINEAR: `~p` -> PCPfree(loc, <elaborated p>). M3 lowers it to D2Pfree wrapping the inner.
| PyPfree(loc, p1) => PCPfree(loc, el_pat(p1))
// GAP C (crash-safety): a malformed pattern (e.g. `case list_cons(a,b):` — a lowercase
// con-application the parser flagged as PyPerror) lowers to an UNRESOLVED constructor pattern
// (`_ERRPAT_` is uppercase-shaped + can never be a real con), so M3's pl_pat routes it through
// the unbound-con path -> a counted poison that tread3a COUNTS (nerror>0). Previously this was
// a benign `PCPvar("_error")` binder that typechecked silently (nerror=0), so a malformed
// pattern slipped through with only a parse diagnostic. The parser already emitted the survivable
// diagnostic + advanced past the bogus args (no loop); this makes the error COUNT at typecheck.
| PyPerror(loc, _) => PCPcon(loc, "_ERRPAT_", list_nil(), list_nil())
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
// ============================================================================
//  M7-closures: the `@func` CAPTURE CHECK (free-variable / scope analysis).
//
//  The surface default is "uniform cloref": every lambda is a CAPTURING first-class
//  closure (F2CLfun / CXFREF) and may freely reference enclosing locals — no check.
//  `@func` opts a lambda into being NON-capturing, ENFORCED here: a `@func (params) =>
//  body` lambda may reference ONLY (a) its own params + names bound INSIDE its body,
//  and (b) module-level / global / imported / prelude names. It may NOT reference a
//  variable bound by an ENCLOSING function or lambda (a "captured local") — that is an
//  error.
//
//  The analysis is over the PyAST. We thread `encl` — the set of ENCLOSING FUNCTION-
//  LOCAL bindings (a def/lambda's params + `let`s bound inside a function body) — down
//  through `el_exp`. Module-level `def`/`let`/`import` names never enter `encl`
//  (referencing them from a @func lambda is fine). At a `@func` lambda we compute:
//
//    FV(body)  = (LIDENTs referenced in body)
//                  \ (the lambda's own params + names bound by inner lets/binders)
//    CAPTURES  = FV(body) ∩ encl
//
//  Each captured name yields a PCEerror poison on the lambda's span (harvested into the
//  diagnostics AND lowered to a none-node so tread3a errcks -> nerror>0). A non-capturing
//  @func lambda passes clean; a NON-@func lambda is NEVER checked.
//
//  EDGE CASES handled: nested @func lambdas (each checked against the locals visible AT
//  it; an inner lambda's own params are bound for it but ARE enclosing-locals for a
//  deeper lambda); inner `let`/`for`-pattern/nested-`def`-param binders subtracted from
//  FV; module-level + imported + prelude refs pass (they are not in `encl`); `match`
//  arm pattern binders + `as`-patterns + guards handled.
// ============================================================================
//
// the LIDENT binder names introduced by a pattern (var, tuple, con-args, record fields,
// `as`-name, annotated inner) — used both to SUBTRACT a lambda's bound names from its FV
// and to EXTEND `encl` when descending past a binding.
fun
fc_pat_names(s: nameset, p: pypat): nameset =
(
case+ p of
| PyPvar(_, nm)     => nameset_add(s, nm)
| PyPwild(_)        => s
| PyPcon(_, _, _, args) => fc_pat_names_lst(s, args)
| PyPtup(_, ps0)    => fc_pat_names_lst(s, ps0)
| PyPrec(_, _, fs)  => fc_pfield_names(s, fs)
| PyPlit(_, _)      => s
| PyPas(_, p1, nm)  => nameset_add(fc_pat_names(s, p1), nm)
| PyPann(_, p1, _)  => fc_pat_names(s, p1)
| PyPbang(_, p1)    => fc_pat_names(s, p1)
| PyPflat(_, p1)    => fc_pat_names(s, p1)
// B-LINEAR: `~p` binds the names of its inner consumed pattern (x, rest in `~VCons(x, rest)`).
| PyPfree(_, p1)    => fc_pat_names(s, p1)
| PyPerror(_, _)    => s
)
and
fc_pat_names_lst(s: nameset, ps0: list(pypat)): nameset =
(
case+ ps0 of
| list_nil() => s
| list_cons(p, rest) => fc_pat_names_lst(fc_pat_names(s, p), rest)
)
and
fc_pfield_names(s: nameset, fs: list(pypfield)): nameset =
(
case+ fs of
| list_nil() => s
| list_cons(PyPField(_, _, p), rest) => fc_pfield_names(fc_pat_names(s, p), rest)
)
//
// the param-name set of a lambda/def parameter list.
fun
fc_param_names(s: nameset, ps0: list(pyparam)): nameset =
(
case+ ps0 of
| list_nil() => s
| list_cons(PyParam(_, nm, _), rest) => fc_param_names(nameset_add(s, nm), rest)
)
//
// FREE VARIABLES of an expression, given the set `bnd` of names bound at this point
// (the lambda's own params + already-seen inner binders). A bare LIDENT NOT in `bnd` is
// free. UIDENT constructors are not vars. Nested lambdas extend `bnd` with their params.
fun
fc_fv_exp(bnd: nameset, fv: nameset, e: pyexp): nameset =
(
case+ e of
| PyEvar(_, nm)   => if nameset_mem(bnd, nm) then fv else nameset_add(fv, nm)
| PyEcon(_, _)    => fv
| PyElit(_, _)    => fv
| PyEwild(_)      => fv
| PyEapp(_, hd, args) => fc_fv_app(bnd, fv, hd, args)
| PyEbin(_, _, l, r)  => fc_fv_exp(bnd, fc_fv_exp(bnd, fv, l), r)
| PyEuna(_, _, e1)    => fc_fv_exp(bnd, fv, e1)
| PyEif(_, gs, els)   => fc_fv_exp(bnd, fc_fv_guards(bnd, fv, gs), els)
| PyEmatch(_, scrut, arms) => fc_fv_arms(bnd, fc_fv_exp(bnd, fv, scrut), arms)
| PyEllazy(_, body) => fc_fv_stmts(bnd, fv, body)
| PyElazy(_, body) => fc_fv_stmts(bnd, fv, body)
| PyEtup(_, es)   => fc_fv_explst(bnd, fv, es)
| PyElist(_, es)  => fc_fv_explst(bnd, fv, es)
| PyErec(_, _, fs) => fc_fv_efields(bnd, fv, fs)
| PyEfield(_, e1, _) => fc_fv_exp(bnd, fv, e1)
| PyEindex(_, e1, ix) => fc_fv_exp(bnd, fc_fv_exp(bnd, fv, e1), ix)
| PyElam(_, _, params, body) =>
    // a nested lambda: its params are bound WITHIN its body; collect its body's FV.
    fc_fv_stmts(fc_param_names(bnd, params), fv, body)
// MISC (Cluster E): a recursive lambda `fix f(params) => body` — the self-name `f` AND the params
// are bound within the body; collect the body's free vars under that extended binding set.
| PyEfix(_, nm, params, _, body) =>
    fc_fv_stmts(fc_param_names(nameset_add(bnd, nm), params), fv, body)
// MISC (Cluster E): `exists {W..}(S..)` names no LOCAL (only int literals) — no free vars.
| PyEexists(_, _, _) => fv
| PyEann(_, e1, _) => fc_fv_exp(bnd, fv, e1)
// EXN: raise scans its sub-expr; try scans its body suite + the except arms (the arm
// patterns bind names in their own handlers — fc_fv_arms handles that subtraction).
| PyEraise(_, e1) => fc_fv_exp(bnd, fv, e1)
| PyEtry(_, body, hs) => fc_fv_arms(bnd, fc_fv_stmts(bnd, fv, body), hs)
| PyEop(_, _)     => fv     // an operator-as-value names no LOCAL — contributes no free vars
// A-TEMPLATE: `@inst[types] e` — the type-args name no LOCAL; the free vars are those of `e`.
| PyEinst(_, _, e1) => fc_fv_exp(bnd, fv, e1)
| PyEsapp(_, _, e1) => fc_fv_exp(bnd, fv, e1)
// B-LINEAR: `&x` / `!p` — the free vars are those of the inner l-value / pointer expr.
| PyEaddr(_, e1)  => fc_fv_exp(bnd, fv, e1)
| PyEderef(_, e1) => fc_fv_exp(bnd, fv, e1)
// GAP B: `r[]` ref-cell deref — its free vars are those of the ref expr `r`.
| PyEderefcell(_, e1) => fc_fv_exp(bnd, fv, e1)
| PyEerror(_, _)  => fv
)
and
fc_fv_app(bnd: nameset, fv: nameset, hd: pyexp, args: list(pyexp)): nameset =
(
case+ hd of
| PyEvar(_, nm) =>
    if strn_eq(nm, "llazy")
    then (
      case+ args of
      | list_cons(arg, list_nil()) => fc_fv_exp(bnd, fv, arg)
      | _ => fc_fv_explst(bnd, fc_fv_exp(bnd, fv, hd), args))
    else (
      if strn_eq(nm, "fold")
      then (
        case+ args of
        | list_cons(arg, list_nil()) => fc_fv_exp(bnd, fv, arg)
        | _ => fc_fv_explst(bnd, fc_fv_exp(bnd, fv, hd), args))
      else fc_fv_explst(bnd, fc_fv_exp(bnd, fv, hd), args))
| _ => fc_fv_explst(bnd, fc_fv_exp(bnd, fv, hd), args)
)
and
fc_fv_explst(bnd: nameset, fv: nameset, es: list(pyexp)): nameset =
(
case+ es of
| list_nil() => fv
| list_cons(e, rest) => fc_fv_explst(bnd, fc_fv_exp(bnd, fv, e), rest)
)
and
fc_fv_efields(bnd: nameset, fv: nameset, fs: list(pyefield)): nameset =
(
case+ fs of
| list_nil() => fv
| list_cons(PyEField(_, _, e), rest) => fc_fv_efields(bnd, fc_fv_exp(bnd, fv, e), rest)
)
and
fc_fv_guards(bnd: nameset, fv: nameset, gs: list(pyguard)): nameset =
(
case+ gs of
| list_nil() => fv
| list_cons(PyGuard(_, c, body), rest) =>
    fc_fv_guards(bnd, fc_fv_stmts(bnd, fc_fv_exp(bnd, fv, c), body), rest)
)
and
fc_fv_arms(bnd: nameset, fv: nameset, arms: list(pyarm)): nameset =
(
case+ arms of
| list_nil() => fv
| list_cons(PyArm(_, p, gopt, body), rest) =>
    let
      // the arm's pattern binds names visible in its guard + body.
      val bnd1 = fc_pat_names(bnd, p)
      val fv1  = (case+ gopt of PyExpNone() => fv | PyExpSome(g) => fc_fv_exp(bnd1, fv, g))
      val fv2  = fc_fv_stmts(bnd1, fv1, body)
    in
      fc_fv_arms(bnd, fv2, rest)
    end
)
// FV of a STATEMENT SUITE: a `let`/`for`-pattern/inner-`def`-name binder extends `bnd`
// for the REST of the suite (Python-ish: a binding is visible to later statements).
and
fc_fv_stmts(bnd: nameset, fv: nameset, ss: list(pystmt)): nameset =
(
case+ ss of
| list_nil() => fv
| list_cons(s, rest) =>
  (
  case+ s of
  | PyDlet(_, _, _, p, _, rhs) =>
      // RHS sees the OLD bnd; later stmts see the binder. (DECORATOR REWORK: the new decorator
      // field — index 2 — is irrelevant to free-variable analysis; ignored.)
      fc_fv_stmts(fc_pat_names(bnd, p), fc_fv_exp(bnd, fv, rhs), rest)
  | PySvar(_, nm, _, rhs) =>
      // a `var` cell: the init RHS (if present) sees the OLD bnd; the cell NAME is bound for
      // later stmts (a function-local, exactly like a `let` binder — so a later @func lambda
      // referencing it is caught as a capture). A no-init `var x: T` references nothing.
      let val fv1 = (case+ rhs of | PyExpSome(e) => fc_fv_exp(bnd, fv, e) | PyExpNone() => fv) in
        fc_fv_stmts(nameset_add(bnd, nm), fv1, rest)
      end
  | PySassign(_, lv, rhs) =>
      // a cell assignment `lv := rhs`: lvalue + rhs both referenced under the current bnd
      // (it binds NO new name — the cell already exists).
      fc_fv_stmts(bnd, fc_fv_exp(bnd, fc_fv_exp(bnd, fv, lv), rhs), rest)
  // B-LINEAR: move/swap — like a cell assignment, both sides referenced, bind no new name.
  | PySmove(_, lv, rhs) =>
      fc_fv_stmts(bnd, fc_fv_exp(bnd, fc_fv_exp(bnd, fv, lv), rhs), rest)
  | PySswap(_, lv, rhs) =>
      fc_fv_stmts(bnd, fc_fv_exp(bnd, fc_fv_exp(bnd, fv, lv), rhs), rest)
  | PySreassign(_, lv, rhs) =>
      // lvalue + rhs both referenced under the current bnd (a reassign does not bind a NEW name).
      fc_fv_stmts(bnd, fc_fv_exp(bnd, fc_fv_exp(bnd, fv, lv), rhs), rest)
  | PySexpr(_, e) => fc_fv_stmts(bnd, fc_fv_exp(bnd, fv, e), rest)
  | PySif(_, gs, els) =>
      fc_fv_stmts(bnd, fc_fv_else(bnd, fc_fv_guards(bnd, fv, gs), els), rest)
  | PySwhile(_, c, body, els) =>
      fc_fv_stmts(bnd,
        fc_fv_else(bnd, fc_fv_stmts(bnd, fc_fv_exp(bnd, fv, c), body), els), rest)
  | PySfor(_, p, iter, body, els) =>
      // the loop pattern binds inside the body; the iterable sees the OLD bnd.
      let val bnd1 = fc_pat_names(bnd, p) in
        fc_fv_stmts(bnd,
          fc_fv_else(bnd1, fc_fv_stmts(bnd1, fc_fv_exp(bnd, fv, iter), body), els), rest)
      end
  | PySreturn(_, eopt) =>
      (case+ eopt of
       | PyExpNone() => fc_fv_stmts(bnd, fv, rest)
       | PyExpSome(e) => fc_fv_stmts(bnd, fc_fv_exp(bnd, fv, e), rest))
  | PySblock(_, body) => fc_fv_stmts(bnd, fc_fv_stmts(bnd, fv, body), rest)
  | PySdecl(_, d) =>
      // an inner `def` binds its NAME for later stmts; its body's FV are collected with its
      // own params bound (its params are NOT free in the enclosing scope).
      (case+ d of
       // SCOPING: a where-block on an inner def is ignored for FV purposes (its decls bind their own
       // names; the body's own FV over the def's params is what the capture-check needs).
       | PyCfun(_, _, nm, _, _, params, _, fbody, _) =>
           let val fv1 = fc_fv_stmts(fc_param_names(bnd, params), fv, fbody) in
             fc_fv_stmts(nameset_add(bnd, nm), fv1, rest) end
       | _ => fc_fv_stmts(bnd, fv, rest))
  | PySbreak(_) => fc_fv_stmts(bnd, fv, rest)
  | PyScontinue(_) => fc_fv_stmts(bnd, fv, rest)
  | PySerror(_, _) => fc_fv_stmts(bnd, fv, rest)
  )
)
and
fc_fv_else(bnd: nameset, fv: nameset, els: pystmtlstopt): nameset =
(
case+ els of
| PyElseNone() => fv
| PyElseSome(body) => fc_fv_stmts(bnd, fv, body)
)
//
// intersect the lambda's FREE vars with the enclosing locals -> the CAPTURED names.
fun
fc_captures(loc: loctn, params: list(pyparam), body: list(pystmt), encl: nameset): nameset =
let
  val bnd = fc_param_names(list_nil(), params)
  val fv  = fc_fv_stmts(bnd, list_nil(), body)
in
  nameset_inter(fv, encl)
end
//
// build a poison-node chain naming each captured local; nil captures -> the clean inner exp.
fun
fc_poison(loc: loctn, caps: nameset, inner: pcexp): pcexp =
(
case+ caps of
| list_nil() => inner
| list_cons(nm, rest) =>
    PCEseq(loc,
      PCEerror(loc, strn_append(
        strn_append("@func lambda captures local `", nm),
        "` (a @func lambda may not capture enclosing locals)")),
      fc_poison(loc, rest, inner))
)
//
(* ****** ****** *)
//
// ---- EXPRESSION elaboration (mutually recursive: exp -> func_body -> pure -> exp) ----
//   `encl` = the set of ENCLOSING FUNCTION-LOCAL names in scope (M7-closures capture check).
//
fun
el_exp(encl: nameset, e: pyexp): pcexp =
(
case+ e of
| PyEvar(loc, nm) => PCEvar(loc, nm)
| PyEcon(loc, nm) => PCEcon(loc, nm)
| PyElit(loc, lit) => PCElit(loc, el_lit(lit))
| PyEwild(loc) => PCEtop(loc)
| PyEapp(loc, hd, args) => el_app(encl, loc, hd, args)
| PyEbin(loc, b, l, r) => el_binop(encl, loc, b, l, r)
| PyEuna(loc, u, e1) => el_unop(encl, loc, u, e1)
| PyEif(loc, gs, els) => el_eguards(encl, gs, el_exp(encl, els))
| PyEmatch(loc, scrut, arms) => PCEcase(loc, el_exp(encl, scrut), el_arms(encl, arms))
| PyEllazy(loc, body) => PCEllazy(loc, el_func_body(encl, loc, body))
| PyElazy(loc, body) => PCElazy(loc, el_func_body(encl, loc, body))
| PyEtup(loc, es) => PCEtup(loc, el_explst(encl, es))
| PyElist(loc, es) => PCElist(loc, el_explst(encl, es))
| PyErec(loc, knd, fs) => PCErec(loc, knd, el_efields(encl, fs))
| PyEfield(loc, e1, nm) => PCEfield(loc, el_exp(encl, e1), nm)
| PyEindex(loc, e1, ix) =>
    PCEapp(loc, PCEvar(loc, "[]"), list_cons(el_exp(encl, e1), list_sing(el_exp(encl, ix))))
// GAP B: `r[]` (read THROUGH a ref cell) -> a `a0ref_get(r)` call (the prelude ref-get, re-
// exported in pyrt.sats). DISTINCT from PyEindex (`r[i]` -> the `[]` overload). In an LVALUE
// position (`r[] := e`) the PySassign arm rewrites it to `a0ref_set(r, e)` instead.
| PyEderefcell(loc, e1) =>
    PCEapp(loc, PCEvar(loc, "a0ref_get"), list_sing(el_exp(encl, e1)))
| PyElam(loc, is_func, params, body) =>
    // M7-closures: the lambda's own params are bound IN its body (and are enclosing-locals
    // for any DEEPER lambda). If @func, check captures against the CURRENT `encl` and wrap a
    // poison-node chain naming each captured local (else the clean lambda).
    let
      val encl_inner = fc_param_names(encl, params)
      val lamexp =
        PCElam(loc, is_func, el_param_names(params), el_param_types(params),
               el_func_body(encl_inner, loc, body))
    in
      if is_func
        then fc_poison(loc, fc_captures(loc, params, body, encl), lamexp)
        else lamexp
    end
| PyEann(_, e1, _) => el_exp(encl, e1)
// MISC (Cluster E): a recursive lambda `fix f(params)[: R] => body` -> PCEfix. The self-name `f` and
// the params are bound IN the body (recursion); el_func_body folds the body suite to one value-expr.
// (Not @func — a fix is a first-class recursive closure; no capture check, mirroring an undecorated
// lambda.)
| PyEfix(loc, nm, params, retopt, body) =>
    let
      val encl_inner = fc_param_names(nameset_add(encl, nm), params)
    in
      PCEfix(loc, nm, el_param_names(params), el_param_types(params), retopt,
             el_func_body(encl_inner, loc, body))
    end
// MISC (Cluster E): `exists {W..}(S..)` -> PCEexists (pass-through; the witness/scope are literal
// lexemes, no name resolution).
| PyEexists(loc, ws, ss) => PCEexists(loc, ws, ss)
// EXN: raise -> PCEraise. The raised value (a con application) is an ordinary expr.
| PyEraise(loc, e1) => PCEraise(loc, el_exp(encl, e1))
// EXN: try -> PCEtry. The body SUITE folds to one value-expr via el_func_body (same as a
// def/branch body). The except clauses reuse el_arms (the match-arm elaborator) — each
// `except <pat>:` is a case-arm over the caught exn; its pattern binders scope its handler.
| PyEtry(loc, body, hs) => PCEtry(loc, el_func_body(encl, loc, body), el_arms(encl, hs))
// `op+` (operator-as-value): the operator's symbol name as a BARE value reference -> PCEvar. M3's
// pl_var resolves the operator name (the prelude overload symbol) to a d2exp_sym0 VALUE, exactly as
// the call-head path resolves a head `+` — so `op+` IS the `+` function value (e.g. reduce(xs, op+)).
| PyEop(loc, nm) => PCEvar(loc, nm)
// A-TEMPLATE: `@inst[types] e` -> PCEinst, carrying the type-args + the elaborated inner expr.
// M3 (pl_exp) lowers it to a tapp-nested-in-dapp (foo<Int>(args)) / a bare tapp.
| PyEinst(loc, ts, e1) => PCEinst(loc, ts, el_exp(encl, e1))
// Static `{...}` application: generated pyprint uses this for ATS implicit/static arguments.
| PyEsapp(loc, ts, e1) => PCEsapp(loc, ts, el_exp(encl, e1))
// B-LINEAR: `&x` -> PCEaddr (D2Eaddr) ; `!p` -> PCEderef (D2Eeval).
| PyEaddr(loc, e1) => PCEaddr(loc, el_exp(encl, e1))
| PyEderef(loc, e1) => PCEderef(loc, el_exp(encl, e1))
| PyEerror(loc, msg) => PCEerror(loc, msg)
)
//
and
el_app(encl: nameset, loc: loctn, hd: pyexp, args: list(pyexp)): pcexp =
(
case+ hd of
| PyEvar(_, nm) =>
    if strn_eq(nm, "llazy")
    then (
      case+ args of
      | list_cons(arg, list_nil()) => PCEllazy(loc, el_exp(encl, arg))
      | _ => PCEapp(loc, el_exp(encl, hd), el_explst(encl, args)))
    // NON-LINEAR inline lazy `lazy(e)` -> PCElazy (sibling of the llazy(e) case above). A non-
    // 1-arg `lazy(...)` is an ordinary call (recovery). Mirrors the `$lazy` head in stock trans12.
    else (if strn_eq(nm, "lazy")
    then (
      case+ args of
      | list_cons(arg, list_nil()) => PCElazy(loc, el_exp(encl, arg))
      | _ => PCEapp(loc, el_exp(encl, hd), el_explst(encl, args)))
    else (
      if strn_eq(nm, "fold")
      then (
        case+ args of
        | list_cons(arg, list_nil()) => PCEfold(loc, el_exp(encl, arg))
        | _ => PCEapp(loc, el_exp(encl, hd), el_explst(encl, args)))
      // `$eval(e)` (the lazy-FORCE builtin, DEVAL_symbl) prints as `eval(e)` ($-stripped) and lowers
      // to D2Eeval — the SAME node as a deref `!p` (PCEderef). DISTINCT from the prelude's overloaded
      // `eval` (`#symload eval with strm_vt_eval`), which is reached only via `$eval` in the bootstrap
      // (the corpus has 41 `$eval` calls and 0 bare-`eval` overload calls), so this routing is safe.
      else (if strn_eq(nm, "eval")
      then (
        case+ args of
        | list_cons(arg, list_nil()) => PCEderef(loc, el_exp(encl, arg))
        | _ => PCEapp(loc, el_exp(encl, hd), el_explst(encl, args)))
      else PCEapp(loc, el_exp(encl, hd), el_explst(encl, args)))))
| _ => PCEapp(loc, el_exp(encl, hd), el_explst(encl, args))
)
//
and
el_explst(encl: nameset, es: list(pyexp)): list(pcexp) =
(
case+ es of
| list_nil() => list_nil()
| list_cons(e, rest) => list_cons(el_exp(encl, e), el_explst(encl, rest))
)
//
// GAP B: elaborate a CELL ASSIGNMENT `lv := rhs`. If the lvalue is a ref-cell deref `r[]`
// (PyEderefcell), the assignment writes THROUGH the ref cell -> a `a0ref_set(r, rhs)` call
// (the prelude ref-set, re-exported in pyrt.sats). Otherwise it is a `var`-cell assignment
// to a named lvalue -> PCEassign (the existing D2Eassgn path). Shared by every PySassign
// site (el_pure + el_stmt below, and the loop-body elaborator pyelab_loop.dats).
and
el_cellassign(encl: nameset, loc: loctn, lv: pyexp, rhs: pyexp): pcexp =
(
case+ lv of
| PyEderefcell(_, r) =>
    PCEapp(loc, PCEvar(loc, "a0ref_set"),
           list_cons(el_exp(encl, r), list_sing(el_exp(encl, rhs))))
| _ => PCEassign(loc, el_exp(encl, lv), el_exp(encl, rhs))
)
//
and
el_efields(encl: nameset, fs: list(pyefield)): list(pcefield) =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PyEField(loc, nm, e), rest) =>
    list_cons(PCEField(loc, nm, el_exp(encl, e)), el_efields(encl, rest))
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
// M5a: the PARALLEL list of each param's OPTIONAL surface type annotation (same length as
// el_param_names). An unannotated `def f(x)` param carries PyTypNone(); `def f(x: Int)` -> Some.
and
el_param_types(ps0: list(pyparam)): list(pytypopt) =
(
case+ ps0 of
| list_nil() => list_nil()
| list_cons(PyParam(_, _, topt), rest) => list_cons(topt, el_param_types(rest))
)
//
and
el_binop(encl: nameset, loc: loctn, b: pybop, l: pyexp, r: pyexp): pcexp =
(
case+ b of
| PyBand() => PCEif(loc, el_exp(encl, l), el_exp(encl, r), PCElit(loc, PCLbool(loc, false)))
| PyBor()  => PCEif(loc, el_exp(encl, l), PCElit(loc, PCLbool(loc, true)), el_exp(encl, r))
| _ => PCEapp(loc, PCEvar(loc, bop_sym(b)), list_cons(el_exp(encl, l), list_sing(el_exp(encl, r))))
)
//
and
el_unop(encl: nameset, loc: loctn, u: pyuop, e1: pyexp): pcexp =
(
case+ u of
| PyUnot() => PCEif(loc, el_exp(encl, e1), PCElit(loc, PCLbool(loc, false)), PCElit(loc, PCLbool(loc, true)))
| _ => PCEapp(loc, PCEvar(loc, uop_sym(u)), list_sing(el_exp(encl, e1)))
)
//
and
el_eguards(encl: nameset, gs: list(pyguard), els: pcexp): pcexp =
(
case+ gs of
| list_nil() => els
| list_cons(PyGuard(loc, c, body), rest) =>
    PCEif(loc, el_exp(encl, c), el_func_body(encl, loc, body), el_eguards(encl, rest, els))
)
//
and
el_arms(encl: nameset, arms: list(pyarm)): list(pcarm) =
(
case+ arms of
| list_nil() => list_nil()
| list_cons(PyArm(loc, p, gopt, body), rest) =>
  let
    val pc_p = el_pat(p)
    // M7-closures: the arm pattern's binders are FUNCTION-LOCALS in the guard + body (a @func
    // lambda there may not capture them — but it CAN use them, since they bind INSIDE itself
    // only via FV-subtraction; here they enter `encl` for any DEEPER lambda).
    val encl1 = fc_pat_names(encl, p)
    val pc_body = el_func_body(encl1, loc, body)
    // architect ruling (iv): PRESERVE the surface guard — elaborate it and attach it to
    // the arm. Do NOT desugar to an inner `if` (a failed guard must fall through to the
    // NEXT arm; M4 lowers it to ATS's native guarded clause).
    val pc_g =
      (case+ gopt of
       | PyExpNone()   => PCEGNone()
       | PyExpSome(g)  => PCEGSome(el_exp(encl1, g)))
  in
    list_cons(PCArm(loc, pc_p, pc_g, pc_body), el_arms(encl, rest))
  end
)
//
// §5.4 function/branch-body epilogue. `encl` = enclosing function-locals in scope here.
and
el_func_body(encl: nameset, loc: loctn, body: list(pystmt)): pcexp =
let
  val fl = el_flags_stmts(body)
in
  if ~(fl.0)  // no return: control-pure body — fast path with the tail value.
    then el_pure(encl, body, list_nil(), list_nil(), el_suite_tail(encl, loc, body))
  else // may return: flow mode (no accumulators) + the §5.4 epilogue match.
    let
      val flowexp = elab_flow(encl, body, list_nil(), list_nil(), list_nil())
      val a_ret =
        PCArm(el_dloc0(), PCPcon(el_dloc0(), "flow_return", list_nil()(*sargs*), list_sing(PCPvar(el_dloc0(), "r"))),
              PCEGNone(), PCEvar(el_dloc0(), "r"))
      val a_next =
        PCArm(el_dloc0(), PCPcon(el_dloc0(), "flow_next", list_nil()(*sargs*), list_sing(PCPwild(el_dloc0()))),
              PCEGNone(), el_suite_tail(encl, loc, body))
    in
      PCEcase(loc, flowexp, list_cons(a_ret, list_sing(a_next)))
    end
end
//
and
el_suite_tail(encl: nameset, loc: loctn, body: list(pystmt)): pcexp =
(
case+ body of
| list_nil() => PCEunit(loc)
| list_cons(s, list_nil()) =>
    (case+ s of PySexpr(_, e) => el_exp(encl, e) | _ => PCEunit(pystmt_loctn(s)))
| list_cons(_, rest) => el_suite_tail(encl, loc, rest)
)
//
(* ****** ****** *)
//
// ---- §5.1 control-pure fast path --------------------------------------------
//
// M7-closures: `encl` carries the enclosing function-locals visible at this point; a `let`/
// `for`-pattern/inner-`def`-name binder EXTENDS it for the REST of the suite, so a later @func
// lambda that references such a binder is caught as a capture.
and
el_pure(encl: nameset, ss: list(pystmt), muts: nameset, mts: muttypes, tail: pcexp): pcexp =
  el_pure_go(encl, ss, muts, mts, tail, true)
and
el_pure_go(encl: nameset, ss: list(pystmt), muts: nameset, mts: muttypes, tail: pcexp, tail_expr: bool): pcexp =
(
case+ ss of
| list_nil() => tail
| list_cons(s, rest) =>
  (
  case+ s of
  | PyDlet(loc, _decos, ismut, p, ann, rhs) =>
      // M5a: an annotated `let p : T = e` carries its annotation onto the binding (PCElet).
      // A `let mut x : T` ALSO records the annotation in `mts` so a synthesized loop that
      // accumulates `x` is typed (the M16 untyped-loop-var fix). (DECORATOR REWORK: the new
      // decorator field — a `@proof let` inside a body — is irrelevant to control-flow
      // elaboration here; a proof let in a function body lowers as an ordinary let-binding.)
      let
        val newmuts = (if ismut then el_add_pat_names(muts, p) else muts)
        val newmts = (if ismut then el_add_mut_types(mts, p, ann) else mts)
        // the binder is a FUNCTION-LOCAL for everything after it (capture-check scope).
        val encl1 = fc_pat_names(encl, p)
      in
        PCElet(loc, el_pat(p), ann, el_exp(encl, rhs), el_pure_go(encl1, rest, newmuts, newmts, tail, tail_expr))
      end
  | PySvar(loc, nm, ann, rhs) =>
      // a MUTABLE CELL `var nm [: T] = rhs`. CRITICAL: a `var` is an IN-PLACE cell, NOT a
      // `let mut` SSA accumulator — it does NOT enter `muts`/`mts` (so the loop desugaring
      // never threads it). It DOES extend `encl` (a function-local for the capture check)
      // and scopes the rest of the suite via PCEvarcell's body.
      let
        val encl1 = nameset_add(encl, nm)
        // init is OPTIONAL: `var x: T` (no `=`) -> PCEGNone (uninitialized cell).
        val initopt =
          (case+ rhs of
           | PyExpSome(e) => PCEGSome(el_exp(encl, e))
           | PyExpNone() => PCEGNone()): pcexpopt
      in
        PCEvarcell(loc, nm, ann, initopt, el_pure_go(encl1, rest, muts, mts, tail, tail_expr))
      end
  | PySassign(loc, lv, rhs) =>
      // a CELL ASSIGNMENT `lv := rhs` -> PCEassign (lowers to D2Eassgn). DISTINCT from the
      // `=` SSA-reassign path below (which rebinds in `muts`). A var cell is mutated in place;
      // there is no SSA shadowing here, so `muts`/`mts`/`encl` are unchanged for the rest.
      // GAP B: a ref-cell lvalue `r[] := rhs` becomes `a0ref_set(r, rhs)`; a named `var` cell
      // `x := rhs` stays PCEassign (D2Eassgn). el_cellassign dispatches on the lvalue shape.
      PCEseq(loc, el_cellassign(encl, loc, lv, rhs),
             el_pure_go(encl, rest, muts, mts, tail, tail_expr))
  // B-LINEAR: MOVE `lv :=> rhs` -> PCEmove (D2Exazgn) ; SWAP `lv :=: rhs` -> PCEswap (D2Exchng).
  // Both sides are existing l-values (var cells); they bind no new name. UNLIKE `:=` (D2Eassgn,
  // returns void), `:=>`/`:=:` return the l-value's TYPE — so a NON-TAIL move/swap cannot go in a
  // void seq-init position (f0_seqn tpck's inits against void). When it is the LAST statement it IS
  // the suite tail (produces its value); otherwise we bind it to a `_` wildcard let so its non-void
  // result is absorbed, then continue. (Mirrors the PySexpr tail-vs-nontail split below.)
  | PySmove(loc, lv, rhs) =>
      (case+ rest of
       | list_nil() => PCEmove(loc, el_exp(encl, lv), el_exp(encl, rhs))
       | list_cons(_, _) =>
           PCElet(loc, PCPwild(loc), PyTypNone(), PCEmove(loc, el_exp(encl, lv), el_exp(encl, rhs)),
                  el_pure_go(encl, rest, muts, mts, tail, tail_expr)))
  | PySswap(loc, lv, rhs) =>
      (case+ rest of
       | list_nil() => PCEswap(loc, el_exp(encl, lv), el_exp(encl, rhs))
       | list_cons(_, _) =>
           PCElet(loc, PCPwild(loc), PyTypNone(), PCEswap(loc, el_exp(encl, lv), el_exp(encl, rhs)),
                  el_pure_go(encl, rest, muts, mts, tail, tail_expr)))
  | PySreassign(loc, lv, rhs) =>
      let val nm = lv_name(lv) in
        if strn_eq(nm, "")
          then PCEseq(loc, PCEapp(loc, PCEvar(loc, "set!"),
                                  list_cons(el_exp(encl, lv), list_sing(el_exp(encl, rhs)))),
                      el_pure_go(encl, rest, muts, mts, tail, tail_expr))
        else if nameset_mem(muts, nm)
          then PCElet(loc, PCPvar(pyexp_loctn(lv), nm), PyTypNone(), el_exp(encl, rhs), el_pure_go(encl, rest, muts, mts, tail, tail_expr))
        else PCEseq(loc, PCEerror(loc, strn_append("reassignment to non-mut binding: ", nm)),
                    el_pure_go(encl, rest, muts, mts, tail, tail_expr))
      end
  | PySexpr(loc, e) =>
      // M4 FIX: the LAST expression-statement of a suite IS the suite's tail value (el_suite_tail
      // already returns it). Emitting it ALSO as a PCEseq init double-evaluates it AND forces the
      // first copy to `void` (D2Eseqn checks its init list in effect position) — a spurious
      // type error on every value-returning body (match/if/tuple/record arms). When this is the
      // final statement (rest = nil), produce the tail directly; otherwise it is a genuine
      // effect-then-continue, so keep the seq. (Mirrors trans12: a tail expression is not seq'd.)
      // M7-closures: recompute the FINAL tail under the EXTENDED `encl` so a @func lambda in the
      // tail position is checked against the body's earlier lets (the precomputed `tail` used the
      // def-level encl). Identical PyCore otherwise — el_exp is pure.
      (case+ rest of
       | list_nil() => if tail_expr then el_exp(encl, e) else PCEseq(loc, el_exp(encl, e), tail)
       | list_cons(_, _) => PCEseq(loc, el_exp(encl, e), el_pure_go(encl, rest, muts, mts, tail, tail_expr)))
  | PySif(loc, gs, els) => el_pure_if(encl, loc, gs, els, muts, mts, rest, tail, tail_expr)
  | PySwhile(loc, cond, body, wels) =>
      elab_while_value(encl, loc, cond, body, wels, muts, mts, el_pure_go(encl, rest, muts, mts, tail, tail_expr))
  | PySfor(loc, pat, iter, body, fels) =>
      elab_for_value(encl, loc, pat, iter, body, fels, muts, mts, el_pure_go(fc_pat_names(encl, pat), rest, muts, mts, tail, tail_expr))
  | PySblock(loc, body) =>
      let
        val kont = el_pure_go(encl, rest, muts, mts, tail, tail_expr)
        val btail = (case+ rest of list_nil() => tail_expr | _ => false)
      in
        el_pure_go(encl, body, muts, mts, kont, btail)
      end
  | PySdecl(loc, d) =>
      if local_groupable_fun(d) then
        let
          val @(fds, rest1, fnms) = take_local_fungroup(encl, ss)
          val encl1 = nameset_union(encl, fnms)
        in
          PCEletfun(loc, fds, el_pure_go(encl1, rest1, muts, mts, tail, tail_expr))
        end
      else
        el_local_decl(encl, loc, d, el_pure_go(el_decl_name(encl, d), rest, muts, mts, tail, tail_expr))
  | PySreturn(loc, _) => PCEerror(loc, "return outside a function")
  | PySbreak(loc) => PCEerror(loc, "break outside a loop")
  | PyScontinue(loc) => PCEerror(loc, "continue outside a loop")
  | PySerror(loc, msg) => PCEseq(loc, PCEerror(loc, msg), el_pure_go(encl, rest, muts, mts, tail, tail_expr))
  )
)
//
and
el_pure_if
(encl: nameset, loc: loctn, gs: list(pyguard), els: pystmtlstopt, muts: nameset, mts: muttypes,
 rest: list(pystmt), tail: pcexp, tail_expr: bool): pcexp =
(
case+ gs of
| list_nil() =>
    (case+ els of
     | PyElseNone() => el_pure_go(encl, rest, muts, mts, tail, tail_expr)
     | PyElseSome(body) =>
         let
           val kont = el_pure_go(encl, rest, muts, mts, tail, tail_expr)
           val btail = (case+ rest of list_nil() => tail_expr | _ => false)
         in
           el_pure_go(encl, body, muts, mts, kont, btail)
         end)
| list_cons(PyGuard(gloc, c, body), grest) =>
    let
      val kont = el_pure_go(encl, rest, muts, mts, tail, tail_expr)
      val btail = (case+ rest of list_nil() => tail_expr | _ => false)
    in
      PCEif(gloc, el_exp(encl, c),
            el_pure_go(encl, body, muts, mts, kont, btail),
            el_pure_if(encl, loc, grest, els, muts, mts, rest, tail, tail_expr))
    end
)
//
and
core_decos_has(decos: list(pydecorator), name: strn): bool =
(
case+ decos of
| list_nil() => false
| list_cons(PyDecor(_, nm, _), rest) =>
    if strn_eq(nm, name) then true else core_decos_has(rest, name)
)
and
core_decos_has_unboxed(decos: list(pydecorator)): bool =
(
case+ decos of
| list_nil() => false
| list_cons(PyDecor(_, nm, _), rest) =>
    if strn_eq(nm, "unboxed") then true else core_decos_has_unboxed(rest)
)
and
core_decos_impl_types(decos: list(pydecorator)): list(pytyp) =
(
case+ decos of
| list_nil() => list_nil()
| list_cons(PyDecor(_, nm, dargs), rest) =>
    if strn_eq(nm, "impl")
    then (case+ dargs of PyDAtypes(ts) => ts | _ => list_nil())
    else core_decos_impl_types(rest)
)
and
core_elab_typarams(tps: list(pytyparam)): list(pcparam) =
(
case+ tps of
| list_nil() => list_nil()
| list_cons(PyTyParam(ploc, nm, sortopt, decos, _gopt), rest) =>
    let
      val sname = (case+ sortopt of PySortSome(_, s) => s | PySortNone() => "")
      val unboxed = core_decos_has_unboxed(decos)
    in
      list_cons(PCParam(ploc, nm, sname, unboxed), core_elab_typarams(rest))
    end
)
and
local_groupable_fun(d: pydecl): bool =
(
case+ d of
| PyCfun(_, list_nil(), _, list_nil(), _, _, _, _, _) => true
| _ => false
)
//
and
local_fun_fundcl(encl: nameset, d: pydecl): pcfundcl =
(
case+ d of
| PyCfun(floc, _decos, nm, _, _, params, ret, body, wheres) =>
    let
      val ibody0 = el_func_body(fc_param_names(encl, params), floc, body)
      val ibody1 =
        ( case+ wheres of
          | list_nil() => ibody0
          | _ => PCEwhere(floc, ibody0, elab_decls(wheres)) )
    in
      PCFundcl(floc, nm, el_param_names(params), el_param_types(params), ret, ibody1, false)
    end
| _ =>
    let val loc = pydecl_loctn(d) in
      PCFundcl(loc, "__pyfront_internal_bad_local_fun_group", list_nil(), list_nil(), PyTypNone(),
               PCEerror(loc, "internal: non-function in local def group"), false)
    end
)
//
and
local_fun_name(ds: nameset, d: pydecl): nameset =
(
case+ d of
| PyCfun(_, _, nm, _, _, _, _, _, _) => nameset_add(ds, nm)
| _ => ds
)
//
and
take_local_fungroup(encl: nameset, ss: list(pystmt)): @(list(pcfundcl), list(pystmt), nameset) =
(
case+ ss of
| list_cons(PySdecl(_, d), rest) =>
    if local_groupable_fun(d) then
      let
        val fd = local_fun_fundcl(encl, d)
        val @(fds, tail, fnms) = take_local_fungroup(encl, rest)
      in
        @(list_cons(fd, fds), tail, local_fun_name(fnms, d))
      end
    else @(list_nil(), ss, list_nil())
| _ => @(list_nil(), ss, list_nil())
)
//
and
el_local_decl(encl: nameset, loc: loctn, d: pydecl, kont: pcexp): pcexp =
(
case+ d of
| PyCfun(floc, decos, nm, tps, has_darg, params, ret, body, wheres) =>
    // an inner `def` binds its NAME (a function-local for later stmts: el_decl_name handles that);
    // its OWN params seed the inner body's enclosing-locals.
    // SCOPING: an inner def MAY carry a trailing `where:` block — wrap its body in PCEwhere (M3 ->
    // D2Ewhere), the SAME backwards-scoping as a top-level def (EMPTY where => no wrap).
    if core_decos_has(decos, "impl") then
      let
        val body0 = el_func_body(fc_param_names(encl, params), floc, body)
        val body1 =
          ( case+ wheres of
            | list_nil() => body0
            | _ => PCEwhere(floc, body0, elab_decls(wheres)) )
        val decl =
          PCCimplement(floc, nm, core_elab_typarams(tps), has_darg,
                       el_param_names(params), el_param_types(params), ret,
                       body1, core_decos_impl_types(decos))
      in
        PCEwhere(loc, kont, list_sing(decl))
      end
    else
      let
        val fd = local_fun_fundcl(encl, d)
      in
        PCEletfun(loc, list_sing(fd), kont)
      end
| PyCtype(_, _, _, _, _) =>
    PCEwhere(loc, kont, elab_decls(list_sing(d)))
// EXN: a local `exception E(T...)` statement in a body suite declares an exn CONSTRUCTOR
// scoped over the REST of the suite (a `raise E` / `except E` that follows must resolve it).
// Mirror the PyCtype arm: backwards-scope the decl over `kont` via PCEwhere (M3 -> D2Ewhere),
// which lowers `PCCexcept` to a registered D2Cexcptcon BEFORE the continuation is checked.
// Without this the decl was silently dropped by the catch-all (-> unresolved D1Eid0(E) errck).
| PyCexcept(_, _, _) =>
    PCEwhere(loc, kont, elab_decls(list_sing(d)))
// SCOPING (bootstrap P1): a `private:` block INSIDE a function body is the body-suite form of
// ATS `local D1 in D2 end` — the private decls (D1) are visible to the REST of the suite (D2 =
// `kont`) but do NOT leak past it. Backwards-scope the elaborated private run over `kont` via
// PCEwhere (M3 -> D2Ewhere), the SAME recipe as PyCtype/PyCexcept. Without this the privates fell
// to the catch-all and were silently DROPPED, so any later use of a private binder (the
// `local val s2td=… in val s2t1=S2Tbas(T2Btdat(s2td)) end` idiom) resolved to an unbound name.
| PyCprivate(_, privs) =>
    PCEwhere(loc, kont, elab_decls(privs))
| _ => kont
)
//
// the function-local NAME a local `def` decl introduces (for the rest-of-suite encl).
and
el_decl_name(encl: nameset, d: pydecl): nameset =
(
case+ d of
| PyCfun(_, decos, nm, _, _, _, _, _, _) =>
    if core_decos_has(decos, "impl") then encl else nameset_add(encl, nm)
| _ => encl
)
//
// M5a: register a `let mut p : T` pattern's annotation into the mut-type map. Only a simple
// `PyPvar` mut binder with an annotation is recorded (the loop accumulators are always plain
// var names; tuple/other mut patterns carry no single annotation and stay untyped).
and
el_add_mut_types(mts: muttypes, p: pypat, ann: pytypopt): muttypes =
(
case+ p of
| PyPvar(_, nm) => muttypes_add(mts, nm, ann)
| _ => mts
)
//
(* ****** ****** *)
//
// ---- thin #implfun wrappers for the SATS entries ---------------------------
//
#implfun
elab_else(encl, loc, body, muts, mts) = el_pure(encl, body, muts, mts, PCEunit(loc))
//
#implfun el_dloc() = el_dloc0()
#implfun assigned_stmts(ss) = el_assigned_stmts(ss)
#implfun flags_stmts(ss) = el_flags_stmts(ss)
#implfun elab_exp(encl, e) = el_exp(encl, e)
#implfun elab_pat(p) = el_pat(p)
#implfun elab_func_body(encl, loc, body) = el_func_body(encl, loc, body)
#implfun elab_pure(encl, ss, muts, mts, tail) = el_pure(encl, ss, muts, mts, tail)
#implfun fc_param_names_pub(encl, ps0) = fc_param_names(encl, ps0)
#implfun accs_tuple_exp(loc, accs) = el_accs_exp(loc, accs)
#implfun accs_tuple_pat(loc, accs) = el_accs_pat(loc, accs)
#implfun lvalue_name(e) = lv_name(e)
#implfun add_pat_names(muts, p) = el_add_pat_names(muts, p)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_core.dats]
*)
