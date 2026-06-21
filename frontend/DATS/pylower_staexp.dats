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
  else if strn_eq(name, "Char") then "the_s2exp_char0"
  else if strn_eq(name, "Float") then "the_s2exp_dflt0"
  else name
)
//
(* ****** ****** *)
//
// resolve a type NAME to an s2exp (LOWERING-MAP §3.5). On a hit with a single s2cst, emit
// S2Ecst; an overloaded set takes the head; a static var -> S2Evar; unbound -> s2exp_none0.
//
fun
resolve_typ(env: !tr12env, loc: loctn, name: strn): s2exp = let
  val key = symbl_make_name(typ_alias(name))
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
      val lab = LABsym(symbl_make_name(fname))
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
#implfun
pylower_typ(env, t) =
(
case+ t of
| PyTcon(loc, name, args) =>
  if list_nilq(args)
    then resolve_typ(env, loc, name)
    else let
      val s2f = resolve_typ(env, loc, name)
      val s2as = pylower_typlst(env, args)
    in s2exp_apps(loc, s2f, s2as) end
| PyTvar(loc, name) => resolve_typ(env, loc, name)
| PyTidx(loc, _)    => s2exp_none0()  // dependent index — deferred (M4/M5)
// M7 (B): a surface function type `(A, B) -> R` lowers to the L2 con-function type S2Efun1.
// We mirror the PROVEN con-type maker `s2exp_fun1_nil0(npf, argSexps, resSexp)` (M5b.3 con
// types, pylower_decl00.dats:73; staexp2.dats:1037 shows nil0 = fun1_full(F2CLfun, ...)) — the
// SAME maker the frontend already uses to build constructor function types, and the same
// flat-fun arrow the internal `def` lowering's S2Efun1 carries. Arg types lower via
// pylower_typlst, the result via pylower_typ (each inheriting the M5a primitive mitigation).
// M7: surface `(A)->B` uses the flat-fun arrow F2CLfun for now; the fun-vs-cloref (closure)
// arrow kind is being workshopped (task #38) and may change to cloref for capturing-lambda args.
| PyTfun(loc, args, res) =>
    let
      val argSexps = pylower_typlst(env, args)
      val resSexp  = pylower_typ(env, res)
    in
      s2exp_fun1_nil0((-1)(*npf*), argSexps, resSexp)
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
| PyTrec(loc, flds) =>                // M5b.4: a boxed (default) record type — S2Etrcd.
    let val l2flds = pylower_tfields(env, flds) in
      s2exp_make_node(the_sort2_tbox, S2Etrcd(TRCDbox0, (-1)(*npf*), l2flds))
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
