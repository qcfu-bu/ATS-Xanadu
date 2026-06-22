(* ****** ****** *)
(*
** M3 — Python-surface frontend: type lowering (pytyp -> s2exp) + operator remap.
**
** Mirrors trans12_staexp.dats's type-name resolution (LOWERING-MAP §1.4/§3.5): a surface
** type NAME resolves through tr12env_find_s2itm with prelude fall-through. The Python skin
** capitalizes built-in types (Int/Bool/String); the prelude names them lowercase (int/bool/
** strn), so we ALIAS the capitalized surface name to the prelude name before lookup. An
** unresolved name yields s2exp_none0 (a benign placeholder; trans23 reports it on the span).
**
** PROBE-VERIFIED (2026-06-20, throwaway pyfront_probe.dats over a fresh tr12env):
**   int / sint / bool          => S2ITMcst   (resolvable directly)
**   Int / Bool                 => UNBOUND    (must alias to int/bool)
** So the alias table below is load-bearing, NOT cosmetic.
**
** PURELY ADDITIVE; consumes pycore.sats/pyparsing.sats read-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pylower.sats"
//
(* ****** ****** *)
//
#extern fun PYL_ats_name(s: strn): strn = $extnam()
#extern fun PYL_is_qualified_name(s: strn): bool = $extnam()
#extern fun PYL_ats_qualified_name(s: strn): strn = $extnam()
#extern fun PYL_qual_head_key(s: strn): strn = $extnam()
#extern fun PYL_qual_tail_name(s: strn): strn = $extnam()
#extern fun PYL_uncapitalize(s: strn): strn = $extnam()
//
#implfun
pylower_ats_name(name) = PYL_ats_name(name)
//
fun ats_name(name: strn): strn = pylower_ats_name(name)
fun ats_sym(name: strn): sym_t = symbl_make_name(ats_name(name))
fun ats_qualified_sym(name: strn): sym_t = symbl_make_name(PYL_ats_qualified_name(name))
fun ats_type_name(name: strn): strn = PYL_uncapitalize(ats_name(name))
fun ats_type_sym(name: strn): sym_t = symbl_make_name(ats_type_name(name))
//
(* ****** ****** *)
//
// ---- surface-operator -> prelude-name remap (LOWERING-MAP §3.4, M3-REPORT table) --------
//
// PROBE-VERIFIED (the crux of M3): the prelude binds `+ - * / % == < ...` as OVERLOAD
// SYMBOLS (D2ITMsym), whose resolution trans23 does NOT perform on a directly-constructed L2
// node — it reads the d2rxp the (bypassed) trans12 overload pass would have filled, so a
// D2Esym0 head lowers to D3Enone0/D3Et2pck (a non-runnable errck). The robust direct-L2 path
// resolves each operator to its CONCRETE prelude `sint_*` function (D2ITMcst(single), probe-
// verified), which the D2ITMcst arm lowers cleanly to d2exp_cst — NO overload resolution.
//
// This monomorphizes arithmetic/comparison to `sint` (the E2E uses int operands) — exactly
// the minimal type support the M3 brief asks for. A polymorphic-operator path (filling the
// d2rxp like trans12's trans2a sub-pass) is deferred; flagged in M3-REPORT.
//
// `op_remap` is the BINARY map (2-arg operators). Unary `-`/`+` are handled at the PCEapp
// site (arity 1) via `op_remap_unary`. `//` collapses to `sint_div$sint` (prelude `/` IS
// integer division on sint). `**` has no sint prelude fun -> "" (DEFERRED; resolves UNBOUND,
// trans23 reports it on the .py span). and/or/not never reach here (elaborator -> PCEif).
//
#implfun
op_remap(name) =
(
  if strn_eq(name, "==") then "="       // prelude equality is `=`
  else if strn_eq(name, "//") then "/"  // prelude `/` IS integer division on sint
  else name                             // everything else resolves to its own overload symbol
)
//
// the UNARY map: a 1-arg `-` is negation (prelude `~`/`neg`); a 1-arg `+` is the identity
// prefix ("" -> the PCEapp site returns the operand). Other names are not unary operators.
//
#implfun
op_remap_unary(name) =
(
  if strn_eq(name, "-") then "neg"   // unary minus -> the prelude `neg` overload
  else if strn_eq(name, "+") then ""  // unary plus: a no-op (PCEapp site returns the operand)
  else name
)
//
(* ****** ****** *)
//
// ---- type-name aliasing: surface (capitalized) -> prelude (lowercase) -------
//
// M5a (the load-bearing fix): the capitalized built-ins alias to the prelude's INTERNAL
// `the_s2exp_*0` type names (prelude/INIT/srcgen2_xsetup0.sats), NOT to the surface `int`/`bool`.
//
// WHY: an int literal's TYPE is `the_s2typ_sint() = T2Pcst(<the_s2exp_sint0 s2cst>)`
// (statyp2_inits0.dats). The surface `int` is `#typedef int = sint0 = gint0(sint_k) =
// [i:i0] gint_type(sint_k,i)` — an EXISTENTIAL. A direct-L2 annotation built from `int`
// stpizes to `T2Ps2exp(int)` and never HNFs symmetrically with the literal's already-built
// `T2Pcst`; unify then compares the literal's HNF (reaching the abstract `gint_type`, a
// `T2Pbas`) against the raw annotation, and `unify00_s2typ` has NO `T2Pbas` arm -> a hard
// `XATS000_cfail` (verified: `def f() -> Int: 1` crashed). Aliasing to `the_s2exp_sint0`
// makes the annotation the SAME `T2Pcst(the_s2exp_sint0)` the literal carries, so unify
// short-circuits on stamp equality (`s2c1 = s2c2`) with NO deep HNF -> no crash, types match.
fun
typ_alias(name: strn): strn =
(
  if strn_eq(name, "Int") then "the_s2exp_sint0"
  else if strn_eq(name, "Bool") then "the_s2exp_bool0"
  else if strn_eq(name, "String") then "the_s2exp_strn0"
  else if strn_eq(name, "strn") then "the_s2exp_strn0"
  else if strn_eq(name, "Char") then "the_s2exp_char0"
  else if strn_eq(name, "Float") then "the_s2exp_dflt0"
  else if strn_eq(name, "UInt") then "the_s2exp_uint0"
  else if strn_eq(name, "Uint") then "the_s2exp_uint0"
  // DEP: a BARE `SInt` (no index args) is the EXISTENTIAL int — the SAME `the_s2exp_sint0`
  // that an int literal's type is `T2Pcst(the_s2exp_sint0)` (M5a reasoning), so `-> SInt`
  // unifies with `0`. The INDEXED form `SInt[k]` is routed separately (the_s2exp_sint1) in
  // the PyTcon arm BEFORE this alias runs — so this branch only fires for the bare name.
  else if strn_eq(name, "SInt") then "the_s2exp_sint0"
  else if strn_eq(name, "Sint") then "the_s2exp_sint0"
  else if strn_eq(name, "SBool") then "the_s2exp_bool0"
  else name
)
//
(* ****** ****** *)
//
// DEP (dependent-type surface, Stages 1–2): parse a surface INDEX literal (a digit lexeme kept
// verbatim on PyTidx) to a STATIC int s2exp `s2exp_int(k)` (DEP-spike P1-proven: an index ARG on
// a type con). `gint_parse_sint` (prelude gint000.sats) converts the lexeme; a malformed lexeme
// parses to 0 (benign — the surface lexer only emits PT_INT for a real integer, so this is total).
fun
pylower_index_lit(loc: loctn, raw: strn): s2exp =
  s2exp_int(gint_parse_sint(raw))
//
// DEP (static arithmetic): map a surface index-binop tag (pybop) to its PRELUDE static const NAME
// — the `*_i0_i0` operator on the int index sort (prelude/basics0.sats:266-409, the SAME ops the
// DEP-spike build_binop resolved). Arithmetic yields sort i0; comparisons yield sort bool. An op
// with no static int form (`/`, `%`, `//`, `**`, `and`/`or` — which can't reach an index position)
// maps to "" (unbound -> trans23 reports it; never a crash). Parallel to the M3 dynamic op_remap.
fun
static_op_name(bop: pybop): strn =
(
case+ bop of
| PyBadd() => "add_i0_i0"
| PyBsub() => "sub_i0_i0"
| PyBmul() => "mul_i0_i0"
| PyBlt()  => "lt_i0_i0"
| PyBle()  => "lte_i0_i0"
| PyBgt()  => "gt_i0_i0"
| PyBge()  => "gte_i0_i0"
| PyBeq()  => "eq_i0_i0"
| PyBne()  => "neq_i0_i0"
| _ => ""    // /, %, //, **, and, or, not — not valid in an index position (unbound, no crash)
)
//
(* ****** ****** *)
//
// DEP: resolve a RAW (prelude) static name to its head s2cst s2exp, with NO surface aliasing —
// used for the registered parametric int/bool sexpdefs `the_s2exp_sint1`/`the_s2exp_bool1` (the
// indexed-primitive heads). Mirrors the spike's resolve_typ_name (S2ITMcst -> head). An unbound
// name -> s2exp_none0 (benign; trans23 treats it as an unconstrained tyvar — characterized).
fun
resolve_typ_name(env: !tr12env, name: strn): s2exp = let
  val sopt = tr12env_find_s2itm(env, ats_sym(name))
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then s2exp_none0() else s2exp_cst(s2cs.head())
      | S2ITMvar(s2v)  => s2exp_var(s2v)
      | S2ITMenv(_)    => s2exp_none0()
    )
  | ~optn_vt_nil() => s2exp_none0()
end
//
// resolve a type NAME to an s2exp (LOWERING-MAP §3.5). On a hit with a single s2cst, emit
// S2Ecst; an overloaded set takes the head; a static var -> S2Evar; unbound -> s2exp_none0.
//
fun
resolve_typ_key(env: !tr12env, key: sym_t): s2exp = let
  val sopt = tr12env_find_s2itm(env, key)
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
        if list_nilq(s2cs) then s2exp_none0() else s2exp_cst(s2cs.head())
      | S2ITMvar(s2v)  => s2exp_var(s2v)
      | S2ITMenv(_)    => s2exp_none0()
    )
  | ~optn_vt_nil() => s2exp_none0()
end
//
fun
s2itm_to_typ(s2i: s2itm): s2exp =
(
  case+ s2i of
  | S2ITMcst(s2cs) =>
    if list_nilq(s2cs) then s2exp_none0() else s2exp_cst(s2cs.head())
  | S2ITMvar(s2v)  => s2exp_var(s2v)
  | S2ITMenv(_)    => s2exp_none0()
)
//
fun
resolve_typ_qua_key(env: !tr12env, key: sym_t): s2exp = let
  val sopt = tr12env_find_s2qua(env, key)
in
  case+ sopt of
  | ~optn_vt_cons(s2i) => s2itm_to_typ(s2i)
  | ~optn_vt_nil() => s2exp_none0()
end
//
fun
resolve_typ_qualified_envs(envs: f2envlst, name: strn): s2exp =
(
  if PYL_is_qualified_name(name) then let
    val head = PYL_qual_head_key(name)
    val tail = PYL_qual_tail_name(name)
    val sopt = f2envlst_find_s2itm(envs, symbl_make_name(head))
  in
    case+ sopt of
    | ~optn_vt_cons(s2i) =>
      (
        case+ s2i of
        | S2ITMenv(envs1) => resolve_typ_qualified_envs(envs1, tail)
        | _ => s2exp_none0()
      )
    | ~optn_vt_nil() => s2exp_none0()
  end else let
    val sopt = f2envlst_find_s2itm(envs, ats_sym(name))
  in
    case+ sopt of
    | ~optn_vt_cons(s2i) => s2itm_to_typ(s2i)
    | ~optn_vt_nil() => s2exp_none0()
  end
)
//
fun
resolve_typ_qualified(env: !tr12env, name: strn): s2exp = let
  val head = PYL_qual_head_key(name)
  val tail = PYL_qual_tail_name(name)
  val sopt = tr12env_find_s2itm(env, symbl_make_name(head))
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMenv(envs) => resolve_typ_qualified_envs(envs, tail)
      | _ => s2exp_none0()
    )
  | ~optn_vt_nil() => resolve_typ_qua_key(env, ats_qualified_sym(name))
end
//
fun
resolve_typ(env: !tr12env, loc: loctn, name: strn): s2exp = let
  val name0 = typ_alias(name)
  val exact =
    if PYL_is_qualified_name(name0)
    then resolve_typ_qualified(env, name0)
    else resolve_typ_key(env, ats_sym(name0))
in
  if PYL_is_qualified_name(name0)
  then exact
  else (
    case+ exact.node() of
    | S2Enone0() => resolve_typ_key(env, ats_type_sym(name0))
    | _ => exact
  )
end
//
(* ****** ****** *)
//
// DEP: the HEAD s2exp for an APPLIED type-con `name[...]`. The indexed primitives `SInt`/`SBool`
// (when applied) route to the registered parametric int/bool s2cst the_s2exp_sint1/the_s2exp_bool1
// (resolve_typ_name, NO surface aliasing — the raw prelude name); every other name resolves via
// the usual surface-aliased resolve_typ (so `Vec`/`List`/`Tree` keep working). Factored OUT of
// pylower_typ's PyTcon arm so the arm is a single application expression (the standalone
// transpiler rejects an inline `let`-in-`else if` cascade inside a case arm). Defined AFTER
// resolve_typ/resolve_typ_name so the forward references resolve (a plain `fun` sees earlier funs).
fun
pytcon_head(env: !tr12env, name: strn): s2exp =
(
  if strn_eq(name, "Int") then resolve_typ_name(env, "the_s2exp_sint1")
  else if strn_eq(name, "SInt") then resolve_typ_name(env, "the_s2exp_sint1")
  else if strn_eq(name, "Sint") then resolve_typ_name(env, "the_s2exp_sint1")
  else if strn_eq(name, "UInt") then resolve_typ_name(env, "the_s2exp_uint1")
  else if strn_eq(name, "Uint") then resolve_typ_name(env, "the_s2exp_uint1")
  else if strn_eq(name, "Bool") then resolve_typ_name(env, "the_s2exp_bool1")
  else if strn_eq(name, "SBool") then resolve_typ_name(env, "the_s2exp_bool1")
  else if strn_eq(name, "Char") then resolve_typ_name(env, "the_s2exp_char1")
  else if strn_eq(name, "String") then resolve_typ_name(env, "the_s2exp_strn1")
  else if strn_eq(name, "strn") then resolve_typ_name(env, "the_s2exp_strn1")
  // B-LINEAR: the surface pointer type `ptr[l]` (an addr-arg application) routes to the registered
  // prelude ptr s2cst `the_s2exp_p2tr0` (ptr : (addr) -> type). (SPIKE BL-AT2/BL-DERF used it.)
  else if strn_eq(name, "ptr") then resolve_typ_name(env, "the_s2exp_p2tr0")
  else resolve_typ(env, loctn_dummy(), name)
)
//
// DEP (static arithmetic): lower an INDEX BINOP `a <op> b` to the L2 static application
// `s2exp_apps(s2exp_cst(<prelude *_i0_i0 const>), [a', b'])` (DEP-spike P1/P3/P4 recipe). The
// const is resolved BY NAME from the env (the SAME tr12env fall-through that resolves any prelude
// name) via resolve_typ_name (head s2cst). The operands lower recursively via pylower_typ (so a
// nested `n+1` / `i*2` / a var / a literal all flow). On an UNBOUND op (resolve -> none0, e.g. the
// "" name for a non-index op), we degrade to s2exp_none0 (trans23 reports it; never a crash) — but
// for the supported arithmetic/comparison set the const resolves and the application typechecks.
// Defined BEFORE pylower_typ; the forward call to the #implfun pylower_typ resolves (same pattern
// pytcon_head uses to forward-call pylower_typlst).
fun
pylower_index_binop(env: !tr12env, loc: loctn, bop: pybop, a: pytyp, b: pytyp): s2exp = let
  val opname = static_op_name(bop)
  val s2c_head = resolve_typ_name(env, opname)
  val s2e_a = pylower_typ(env, a)
  val s2e_b = pylower_typ(env, b)
in
  case+ s2c_head.node() of
  | S2Enone0() => s2exp_none0()   // unbound op (or "" name): benign placeholder
  | _ => s2exp_apps(loc, s2c_head, list_cons(s2e_a, list_sing(s2e_b)))
end
//
(* ****** ****** *)
//
// A-QUANT: convert a SURFACE typaram (`a: SInt`) to a PyCore `pcparam` so the SHARED
// mk_param_s2vars/psort2_of (the def-param + data/alias generics' ONE source of truth) build its
// s2var at the declared index/type sort. Mirrors pyelab_decl's elab_typarams (sort name = the
// `: SORT` annotation, "" = default Type; @unboxed flattens). PyTquant's binders arrive as RAW
// surface typarams (a TYPE annotation is lowered straight from the AST), so we convert here.
fun
quant_binder_to_pcparam(tp: pytyparam): pcparam =
( case+ tp of
  | PyTyParam(ploc, nm, sortopt, decos, _gopt) =>
    let
      val sname = (case+ sortopt of PySortSome(_, s) => s | PySortNone() => "")
      val unboxed = quant_decos_has_unboxed(decos)
    in
      PCParam(ploc, nm, sname, unboxed)
    end )
//
and
quant_decos_has_unboxed(decos: list(pydecorator)): bool =
( case+ decos of
  | list_nil() => false
  | list_cons(PyDecor(_, nm, _), rest) =>
      if strn_eq(nm, "unboxed") then true else quant_decos_has_unboxed(rest) )
//
fun
quant_binders_to_pcparams(tps: list(pytyparam)): list(pcparam) =
( case+ tps of
  | list_nil() => list_nil()
  | list_cons(tp, rest) =>
      list_cons(quant_binder_to_pcparam(tp), quant_binders_to_pcparams(rest)) )
//
// A-QUANT: push the quantifier's bound s2vars into the current lam-scope so the body type + the
// guards resolve them (the resolve_typ S2ITMvar arm yields s2exp_var). Caller brackets pshlam0/
// poplam0. (A pylower_staexp-local twin of pylower_decl00's file-local bind_param_s2vars.)
fun
bind_quant_s2vars(env: !tr12env, s2vs: s2varlst): void =
( case+ s2vs of
  | list_nil() => ()
  | list_cons(s2v, rest) =>
      let val () = tr12env_add0_s2var(env, s2v) in bind_quant_s2vars(env, rest) end )
//
// A-QUANT: lower the quantifier GUARD list — each guard is a bool-index `pytyp` (a PyTbin
// comparison), lowered via pylower_typ (-> pylower_index_binop, sort bool). These become the
// uni0/exi0 s2ps (DEP-spike P3-proven for uni0; a-quant SX-EXI keeps exi0 collapsing gracefully).
fun
lower_quant_guards(env: !tr12env, gopt: pyguardopt): s2explst =
( case+ gopt of
  | PyGuardNone() => list_nil()
  | PyGuardSome(_, g) => list_sing(pylower_typ(env, g)) )
//
(* ****** ****** *)
//
// M5b.4 — lower a record-type field suite `{ name: T, ... }` to an `l2s2elst` of label/s2exp
// pairs (S2LAB(LABsym(name), <lowered T>)). The field type goes through the EXISTING
// pylower_typ, so a primitive field (`x: Int`) inherits the M5a `resolve_typ` mitigation
// (direct T2Pcst `the_s2exp_*0`, NOT the prelude sexpdef — the load-bearing hazard fix).
//
fun
pylower_tfields(env: !tr12env, fs: list(pytfield)): l2s2elst =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PyTField(floc, fname, ftyp), rest) =>
    let
      val lab = LABsym(ats_sym(fname))
      val s2e = pylower_typ(env, ftyp)
    in
      list_cons(S2LAB(lab, s2e), pylower_tfields(env, rest))
    end
)
//
(* ****** ****** *)
//
// M7 (A) — lower a tuple-type element list `(T0, T1, ...)` to an `l2s2elst` with INTEGER
// labels `0, 1, ..., n-1` (S2LAB(LABint(i), <lowered Ti>)). A tuple IS a record with int
// labels in ATS (statyp2.dats f0_labelize:183 builds tuple TYPES exactly this way, threading
// the index from 0). Each element type goes through the EXISTING pylower_typ, so a primitive
// element (`(Int, Bool)`) inherits the M5a `resolve_typ` mitigation (direct T2Pcst the_s2exp_*0).
// The index is threaded; LABint takes a `sint`, so we count with a `sint` accumulator.
//
fun
pylower_tuptypes(env: !tr12env, ts: list(pytyp), i: sint): l2s2elst =
(
case+ ts of
| list_nil() => list_nil()
| list_cons(t, rest) =>
    let
      val lab = LABint(i)
      val s2e = pylower_typ(env, t)
    in
      list_cons(S2LAB(lab, s2e), pylower_tuptypes(env, rest, i + 1))
    end
)
//
(* ****** ****** *)
//
// ARROW-EFFECTS (bootstrap P1): map a surface arrow tag STRING (verbatim CamelCase from the
// `->[Tag]` grammar) to its L2 function class f2clknd. Only the CLASS PREFIX matters — the effect
// digit (`0`/`1`) is erased at the s2exp level (the fun1 maker has no effect slot; nil0==all1), so
// `CloRef0`/`CloRef1` both map to F2CLfun and `CloPtr1` (the only linear class) to F2CLclo(1).
//   ""        -> F2CLfun     bare `->`  (byte-identical to the prior s2exp_fun1_nil0 path)
//   CloRef0/1 -> F2CLfun     boxed nonlinear closure (cloref)
//   Fun0/1    -> F2CLfun     code-ptr / nonlinear — collapses to cloref at this level (the flat
//                            `fun` code-pointer distinction is erased in f2clknd; nonlinearity
//                            preserved by F2CLfun, sort tbox — NOT the linear F2CLclo(0))
//   CloPtr0/1 -> F2CLclo(1)  LINEAR closure (cloptr), sort vtbx — STRUCTURALLY distinct (arrow-
//                            spike AR-DIST: an F2CLclo(1) value is rejected at an F2CLfun param)
// An UNKNOWN tag falls back to F2CLfun (the bare default) — same benign fall-through the type-name
// resolver uses (no diagnostic sink at the lowering layer). `loc` is unused for now (reserved).
fun
pylower_arrow_f2cl(env: !tr12env, loc: loctn, tag: strn): f2clknd =
(
  if strn_eq(tag, "") then F2CLfun()
  else if strn_eq(tag, "CloRef0") then F2CLfun()
  else if strn_eq(tag, "CloRef1") then F2CLfun()
  else if strn_eq(tag, "Fun0") then F2CLfun()
  else if strn_eq(tag, "Fun1") then F2CLfun()
  else if strn_eq(tag, "CloPtr0") then F2CLclo(1)
  else if strn_eq(tag, "CloPtr1") then F2CLclo(1)
  else F2CLfun()    // unknown tag: fall back to the bare cloref default (benign)
)
//
(* ****** ****** *)
//
#implfun
pylower_typ(env, t) =
(
case+ t of
| PyTcon(loc, name, args) =>
  if list_nilq(args)
    then resolve_typ(env, loc, name)
    // DEP: the INDEXED primitives `SInt[k]`/`SInt[n]` (and `SBool[..]`) route through the
    // registered parametric int/bool s2cst the_s2exp_sint1 / the_s2exp_bool1 (NOT the bare-int
    // sexpdef — the M5a/P8 hazard: the bare int hits the unify00 T2Pbas crash). DEP-spike
    // P8-proven: s2exp_apps(the_s2exp_sint1, [idx]) with a literal/var index typechecks (nerror=0).
    // A general parametric type-con (`Vec[A, n]`, `List[A, n]`) -> resolve the head + apply: each
    // arg lowers via pylower_typ — a TYPE arg (`A`/`Int`, an UIDENT -> PyTcon) -> its s2exp; an
    // INDEX LITERAL (`0`, a digit -> PyTidx) -> s2exp_int(k); an INDEX VAR (`n`, a lowercase LIDENT
    // -> PyTvar) -> s2exp_var(<the int-sorted s2var bound by the enclosing quantifier>) via
    // resolve_typ's S2ITMvar arm. (DEP-spike P1-proven: a mixed type+index arg list on a
    // parametric con whose sort is S2Tfun1([type, int0], tbox) typechecks structurally.)
    // pytcon_head resolves the head s2exp; pylower_typlst lowers the (type/index) args.
    else s2exp_apps(loc, pytcon_head(env, name), pylower_typlst(env, args))
| PyTvar(loc, name) => resolve_typ(env, loc, name)
// DEP: an INDEX LITERAL (`0`, `5`) in a type-arg list -> a STATIC int s2exp s2exp_int(k). (A bare
// index variable `n` arrives as PyTvar, not PyTidx — the lexer emits PT_LIDENT for a lowercase
// name; PyTvar's resolve_typ S2ITMvar arm yields s2exp_var. So PyTidx is ONLY the literal case.)
| PyTidx(loc, raw)  => pylower_index_lit(loc, raw)
// DEP (static arithmetic): an INDEX BINOP (`n+1`, `i<n`, `n*2`, `n>=0`, `n==m`) -> a static const
// application `s2exp_apps(<*_i0_i0 const>, [a, b])` (pylower_index_binop). Reachable inside a
// type-arg bracket (`Vec[A, n+1]`) or a guard (`{n | n>=0}`). Arithmetic yields sort i0;
// comparisons yield sort bool — exactly what an index arg / a guard prop expects.
| PyTbin(loc, bop, a, b) => pylower_index_binop(env, loc, bop, a, b)
// M7 (B) + ARROW-EFFECTS (bootstrap P1): a surface function type `(A) -> R` (bare) or
// `(A) ->[Tag] R` lowers to the L2 con-function type S2Efun1 via the CLASS-AWARE maker
// `s2exp_fun1_full(f2cl, npf, args, res)` (staexp2.dats:1060). The tag's CLASS part selects f2cl:
//   ""/CloRef*/Fun*  -> F2CLfun   (cloref; nonlinear boxed; = bare `->`, byte-identical to before
//                                  since s2exp_fun1_nil0 itself pins F2CLfun, staexp2.dats:1044)
//   CloPtr*          -> F2CLclo(1) (cloptr; LINEAR boxed closure, sort vtbx)
// The effect DIGIT (`0`/`1`/`Exn`/...) is COSMETIC — erased at the s2exp level (nil0==all1; the
// fun1 maker has no effect slot), so we only read the class prefix. The arrow-spike proved all
// classes reach nerror=0 as a HOF param AND that the class is structurally enforced (AR-DIST: an
// F2CLclo(1) value is rejected at an F2CLfun param). Arg types lower via pylower_typlst, the result
// via pylower_typ (each inheriting the M5a primitive mitigation).
| PyTfun(loc, args, res, tag) =>
    let
      val argSexps = pylower_typlst(env, args)
      val resSexp  = pylower_typ(env, res)
      val f2cl     = pylower_arrow_f2cl(env, loc, tag)
    in
      s2exp_fun1_full(f2cl, (-1)(*npf*), argSexps, resSexp)
    end
// M7 (A): a surface tuple type `(A, B)` is a FLAT tuple = a record with INTEGER labels
// 0..n-1. CRUCIALLY it must mirror what a surface tuple VALUE `(1, 2)` lowers to so an
// annotation `let xy: (Int, Int) = (1, 2)` unifies: `D2Etup0(-1, ...)` is typed by trans2a's
// f0_tup0 via `s2typ_tup0(-1, ...)` (statyp2.dats:221), which builds
// `T2Ptrcd(TRCDflt0(*flat*), -1, f0_labelize(...))` at sort `the_sort2_type` — NOT the boxed
// TRCDbox0/tbox. (Verified: a TRCDbox0 tuple TYPE fails to unify with the TRCDflt0 tuple LITERAL
// — D3Et2pck(TRCDflt0 vs TRCDbox0).) So we replicate s2typ_tup0's flat shape: TRCDflt0 +
// the_sort2_type. pylower_tuptypes threads the int index from 0 (= f0_labelize's labeling).
| PyTtup(loc, elts)  =>
    let val l2elts = pylower_tuptypes(env, elts, 0(*i0*)) in
      s2exp_make_node(the_sort2_type, S2Etrcd(TRCDflt0, (-1)(*npf*), l2elts))
    end
| PyTparen(_, body) => pylower_typ(env, body)
| PyTrec(loc, flds) =>                // M5b.4: a boxed (default) record type — S2Etrcd.
    let val l2flds = pylower_tfields(env, flds) in
      s2exp_make_node(the_sort2_tbox, S2Etrcd(TRCDbox0, (-1)(*npf*), l2flds))
    end
// A-QUANT: an EXPLICIT quantified type `forall[n: SInt | g] T` / `exists[m: SInt] T`. Mirror the
// def-param quantifier dance (pl_fungroup_fnk / dep-spike P2/P3, a-quant SX-EXI): build one s2var
// per binder at its psort2_of sort (mk_param_s2vars), push a lam-scope + bind them so the BODY
// type + the GUARDS resolve them, lower the body (recursive) + guards WITHIN the scope, pop, then
// s2exp_uni0 (kind=0 forall) / s2exp_exi0 (kind=1 exists) over (s2vs, guards, body). Both collapse
// gracefully on empty binders+guards (== the body), matching stock; index/guard obligations are
// not solver-checked (no constraint solver — same as stock past stpize).
| PyTquant(loc, kind, binders, gopt, body) =>
    let
      val pcps  = quant_binders_to_pcparams(binders)
      val s2vs  = mk_param_s2vars(pcps)
      val () = tr12env_pshlam0(env)
      val () = bind_quant_s2vars(env, s2vs)
      val s2e_body = pylower_typ(env, body)
      val s2ps     = lower_quant_guards(env, gopt)
      val () = tr12env_poplam0(env)
    in
      if kind = 0
        then s2exp_uni0(s2vs, s2ps, s2e_body)   // forall (DEP-spike P2/P3-proven)
        else s2exp_exi0(s2vs, s2ps, s2e_body)   // exists (a-quant SX-EXI-proven)
    end
// B-LINEAR: the AT-VIEW `A at l` -> the at-view s2exp S2Eatx2(carried, addr) at result sort
// the_sort2_vwtp (the viewtype sort the stock trans12 stamps on an at-view; trans12_staexp.dats
// :1388). The carried type + the address each lower via pylower_typ (the address is normally a
// PyTvar naming an `addr`-sorted quantifier bound by the enclosing forall/def). (B-LIN spike
// BL-AT2 proved this rides to nerror=0 as a proof param.)
| PyTat(loc, carr, addr) =>
    let
      val s2e_carr = pylower_typ(env, carr)
      val s2e_addr = pylower_typ(env, addr)
    in
      s2exp_make_node(the_sort2_vwtp, S2Eatx2(s2e_carr, s2e_addr))
    end
| PyTerror(loc, _)  => s2exp_none0()
)
//
#implfun
pylower_typlst(env, ts) =
(
case+ ts of
| list_nil() => list_nil()
| list_cons(t, rest) =>
    list_cons(pylower_typ(env, t), pylower_typlst(env, rest))
)
//
(* ****** ****** *)
//
// a surface return-type `-> T` becomes S2RESsome(S2EFFnone(), <lowered T>). A PyTcon whose
// name is unresolvable still yields s2exp_none0 inside the S2RESsome, which trans23 treats
// as "no constraint" — so an absent/garbage annotation does not spuriously fail the check.
//
#implfun
pylower_sres(env, t) =
let val s2e = pylower_typ(env, t) in S2RESsome(S2EFFnone(), s2e) end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pylower_staexp.dats]
*)
