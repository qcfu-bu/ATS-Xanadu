(* ****** ****** *)
(*
** M3 — Python-surface frontend: the PyCore -> L2 LOWERING (SATS).
**
** This is the cross-DATS contract for the M3 lowering. PyCore (frontend/SATS/pycore.sats)
** is the functional-core IR the elaborator produces; M3 maps it STRUCTURALLY to the stock
** compiler's level-2 AST (d2exp/d2pat/d2ecl/s2exp), mirroring the trans12_*.dats templates
** (LOWERING-MAP §4) against a LIVE tr12env (fresh per call; names fall through to the
** prelude). The lowered top-level decl list is wrapped by d2parsed_make_args and handed to
** d3parsed_of_trans23, exactly as the stock frontend does — so a type error lands on the
** REAL Python span threaded into every L2 node (the whole point of hooking at L2).
**
** The split mirrors trans12_{staexp,dynexp,decl00}:
**   pylower_staexp.dats : pytyp -> s2exp (type-name resolution; surface Int/Bool aliasing)
**                         + the surface-operator -> prelude-name remap.
**   pylower_dynexp.dats : pclit/pcexp/pcpat -> d2exp/d2pat (templates A/B/C/D/E + literals).
**   pylower_decl00.dats : pcdecl -> d2ecl (the fun-group template F, val, staload) + the
**                         module driver (lower a pcdecl list -> a d2eclist).
**
** Cross-DATS entries MUST be SATS-declared (not `extern fun` in a DATS) so they get a
** STABLE cross-file symbol — exactly the discipline the M2 parser / M2.5 elaborator split
** proved (pyelab.sats preamble). The DATS implement them with `#implfun`.
**
** PURELY ADDITIVE: consumes pycore.sats / pyparsing.sats READ-ONLY; nothing under srcgen2/
** or language-server/ is touched. Three-header discipline + the M0a/M0b verified API set.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
//
(* ****** ****** *)
//
// ---- staexp (types) --------------------------------------------------------
//
// `pylower_typ(env, t)` lowers a surface type to an s2exp, resolving a type NAME via
// tr12env_find_s2itm with the prelude fall-through. Surface capitalized names that have a
// lowercase prelude counterpart are aliased here (Int->int, Bool->bool, String->strn,...);
// an unresolved name yields s2exp_none0 (a benign placeholder trans23 will flag).
//
fun pylower_typ(env: !tr12env, t: pytyp): s2exp
fun pylower_typlst(env: !tr12env, ts: list(pytyp)): s2explst
//
// `pylower_sres(env, t)` = the function/lambda RETURN-type signature S2RESsome from a
// surface type (the `-> T`). S2RESnone() when no annotation is supplied.
fun pylower_sres(env: !tr12env, t: pytyp): s2res
//
// the surface-operator -> prelude-name remap (LOWERING-MAP §3.4; M3-REPORT operator table).
// `op_remap(name)` = the BINARY map: surface operator (or `print`) -> its concrete prelude
// `sint_*` function name (D2ITMcst, resolves cleanly direct-to-L2; the overloaded D2ITMsym
// form does NOT). `op_remap_unary(name)` = the UNARY map (a 1-arg application of `-`/`+`):
// `-` -> `sint_neg`, `+` -> the operand unchanged-name's identity (no-op prefix). Names that
// are not operators pass through unchanged (so ordinary fun/var calls are untouched).
fun op_remap(name: strn): strn
fun op_remap_unary(name: strn): strn
//
// Surface identifier fidelity: pretty-printing maps ATS `$` names to Koka-style `/`
// segments; lowering maps those identifier names back before symbol lookup/registration.
// This is for identifiers, not operator tokens.
fun pylower_ats_name(name: strn): strn
//
(* ****** ****** *)
//
// ---- dynexp (expressions / patterns / literals) ----------------------------
//
// the literal-token synthesizer: a PyCore literal's verbatim lexeme -> the token-based L2
// leaf node (D2Eint/D2Eflt/D2Estr/D2Echr/D2Ebtf). Token-based (NOT unboxed D2E*00), the
// only form proven through codegen (LOWERING-MAP §2.1, M0b §5.5).
fun pylower_lit(loc: loctn, lit: pclit): d2exp
//
// expression lowering (templates A/B/C/D/E). `env` is mutated only by scope push/pop and
// name binding (mirrors trans12); never the global env.
fun pylower_exp(env: !tr12env, e: pcexp): d2exp
fun pylower_explst(env: !tr12env, es: list(pcexp)): d2explst
//
// identifier-reference (template A): resolve `sym` to a d2exp via tr12env_find_d2itm,
// branching on the d2itm. `d1eproxy` is a synthetic D1Eid0(sym) the D2ITMsym (operator
// overload) arm needs for d2exp_sym0; the helper builds it internally.
fun pylower_var(env: !tr12env, loc: loctn, sym: sym_t): d2exp
//
// pattern lowering. Every binder is a FRESH d2var; the caller registers the pattern's vars
// with tr12env_add0_d2pat in the appropriate scope (templates C/E binding rule).
fun pylower_pat(env: !tr12env, p: pcpat): d2pat
fun pylower_patlst(env: !tr12env, ps: list(pcpat)): d2patlst
//
// a parameter-name list -> a single f2arglst (one F2ARGdapp of fresh-d2var patterns).
// Shared by template D (lambda) and template F (fun member). Param types are inferred (v1).
fun params_to_f2arglst(env: !tr12env, loc: loctn, params: list(strn)): f2arglst
//
// VAL-BINDER STYP (M4): set a `val/let p = rhs` binder's styp so a CONCRETE-typed RHS unifies
// against the untyped binder (trans23_d2valdcl checks RHS vs dpat.styp). A `D2Pvar` binder gets
// a FRESH existential tyvar EXCEPT when the RHS is the bare `D2Enone0` recovery node (an unbound
// name) — there it is left `none` so the unbound-name errck survives (4b). Shared by PCElet
// (pylower_dynexp) and PCCval (pylower_decl00). Mirrors trans2a's f0_var binder typing.
fun bind_let_styp(d2p: d2pat, d2rhs: d2exp): void
//
// lower one recursive `fun` group (the PCEletfun/PCCfun member list) to a D2Cfundclst d2ecl
// (template F). The group's names are bound into `env` BEFORE the bodies (a Python def group
// is recursive), so self/mutual calls resolve to the same d2var. Shared by the let-form
// (PCEletfun, in pylower_dynexp) and the top-level form (PCCfun, in pylower_decl00).
//
// DEP (Stages 1–2): `tvs` are the def's §5.7 type/INDEX params (`def f[A, n: SInt](...)`). When
// non-empty, lower_fungroup builds an s2var per param at its psort2_of sort (a `[n: SInt]` -> an
// int-sorted s2var), pushes them into a lam-scope BEFORE lowering the param/return types (so
// `Vec[A, n]` / `SInt` resolve `n`/`A` via resolve_typ's S2ITMvar arm), and quantifies the
// D2Cfundclst over them (its t2qag `tqas` field — the stock f0_fundclst mechanism). EMPTY `tvs`
// => the byte-identical NON-generic path (no scope push, empty tqas). The PCEletfun (loop) caller
// passes `[]` — a generated loop is never index-quantified.
//
// C-PROOF: `mets` is the OPTIONAL `@terminates[n]` termination metric (the index-exprs). When
// non-empty, lower_fungroup lowers each metric index WITHIN the typaram lam-scope (so `n` resolves
// to its s2var) and PREPENDS an `F2ARGmets([<lowered s2exps>])` f2arg onto the FIRST member's
// f2arglst (the stock totality-metric position — trans2a/trans23 carry it type-agnostically). EMPTY
// `mets` => no metric (byte-identical). The PCEletfun (loop) caller passes `[]`.
fun lower_fungroup
  (env: !tr12env, loc: loctn, tvs: list(pcparam), mets: list(pytyp), fdcls: list(pcfundcl)): d2ecl
//
// DEP: map a pcparam's surface sort name (+ @unboxed) to its L2 sort2 (the SInt/SBool index sorts
// + the Type/Linear/Prop type sorts). EXPORTED so the def quantifier (pylower_dynexp) + the
// data/alias/struct generics (pylower_decl00) share ONE source of truth. `mk_param_s2vars` makes
// one s2var per param at its psort2_of sort, in order (the quantifier's bound vars).
fun psort2_of(p: pcparam): sort2
fun mk_param_s2vars(params: list(pcparam)): s2varlst
//
// lower an `implement NAME(params) [-> Ret]: body` (PCCimplement) to a D2Cimplmnt0 (ATS-parity).
// RESOLVES the pre-declared d2cst by NAME (DIMPLone1), binds the (typed) params in a lam scope,
// lowers the body, and assembles D2Cimplmnt0. Lives in pylower_dynexp (where pl_exp /
// pl_params_typed / pl_sres are in scope); called from decl00. SPIKE-PROVEN (pyfront_surf1_spike
// case 3 + pyfront_atmpl_spike build_implement_id; mirrors stock f0_implmnt0_dimp).
// A-TEMPLATE: `tias_typs` are the `@impl[Int, ..]` INSTANTIATION type-args (the impl's `tias`); []
// for a bare `@impl def` (the non-template implement, byte-identical). When the resolved d2cst is a
// TEMPLATE (non-empty tqas), a fresh impl-side tqas of the same shape is built + bound.
fun
lower_implement
( env: !tr12env, loc: loctn, name: strn
, has_darg: bool, pnames: list(strn), ptypes: list(pytypopt), ret: pytypopt, body: pcexp
, tias_typs: list(pytyp)): d2ecl
//
// A-TEMPLATE: lower a `@template[A, B] def foo[C, D](params) [-> Ret] [: body]` TEMPLATE
// declaration (PCCtempl) to ONE-or-TWO d2ecls. SPIKE-PROVEN (pyfront_atmpl_spike build_template_id/
// build_template_foo): build a TEMPLATE extern d2cst — its `tqas = [ t2qag_make_s2vs(loc, <A,B
// s2vars>) ]` (a NON-EMPTY tqas makes d2cst_tempq=true), its fn type wrapped in `s2exp_uni0(<C,D
// s2vars>, [], inner)` when polymorphic params are present — register it + emit D2Cextern. When an
// INLINE body is present, ALSO emit the GENERIC implement (via lower_implement with tias=[]). Lives
// in pylower_decl00 (where build_extern's d2cst/extern machinery is); the inline-body implement is
// delegated to lower_implement (pylower_dynexp). `targs`/`pargs` are the template/polymorphic param
// binders; `bodyopt` is the optional inline body (PCEGNone ⇒ declaration-only).
fun
lower_template
( env: !tr12env, loc: loctn
, targs: list(pcparam), name: strn, pargs: list(pcparam)
, pnames: list(strn), ptypes: list(pytypopt), ret: pytypopt, bodyopt: pcexpopt ): d2eclist
//
// PROOF parity (ATS-parity prfun/prval/praxi). All three live in pylower_dynexp (where pl_exp /
// pl_pat / pl_params_typed / the fun-group machinery are in scope); called from pylower_decl00.
//   * lower_prfungroup : a `prfun` proof FUNCTION group -> D2Cfundclst with the FNKprfn1 funkind
//     (the ONLY delta from a value `def` group; reuses the funkind-parameterized fun-group). The
//     proof body is lowered exactly like a def body. SPIKE-PROVEN (dep-spike P5(A)).
//   * lower_prval : a `prval` proof VALUE -> D2Cvaldclst with the VLKprval valkind (the only delta
//     from a `val`); an OPTIONAL `: T` annotation wraps the RHS in D2Eannot. SPIKE-PROVEN (P5(B)).
//   * lower_praxi : a `praxi` proof AXIOM -> a BODYLESS D2Cstatic(D2Cdynconst(FNKpraxi)) — the
//     extern-signature recipe with the proof funkind. The d2cst is registered so uses resolve.
fun lower_prfungroup
  (env: !tr12env, loc: loctn, tvs: list(pcparam), fdcls: list(pcfundcl)): d2ecl
fun lower_prval
  (env: !tr12env, loc: loctn, p: pcpat, ann: pytypopt, rhs: pcexp): d2ecl
fun lower_praxi
  ( env: !tr12env, loc: loctn, name: strn
  , pnames: list(strn), ptypes: list(pytypopt), ret: pytypopt): d2ecl
//
(* ****** ****** *)
//
// ---- decl00 (declarations) + the module driver -----------------------------
//
// a single top-level decl -> a d2ecl. Binds top-level names into `env` (so later decls and
// uses resolve), recursion-aware for fun groups (template F).
fun pylower_decl(env: !tr12env, d: pcdecl): d2ecl
//
// the module driver: lower a PyCore decl list into a d2eclist, threading `env` left-to-right
// (each decl's bindings visible to the following decls). Mirrors trans12.dats:528-556.
fun pylower_decls(env: !tr12env, ds: list(pcdecl)): d2eclist
//
(* ****** ****** *)
(*
end of [frontend/SATS/pylower.sats]
*)
