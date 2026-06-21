(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the PyCore IR (SATS).
**
** ============================ THE M3 LOWERING CONTRACT ============================
**
** PyCore is the FUNCTIONAL CORE the imperative elaborator (frontend/DATS/pyelab_*.dats)
** produces from the surface PyAST (frontend/SATS/pyparsing.sats). It is what M3
** (`pylower`) lowers to L2. By the time PyCore exists, ALL imperative control has been
** ELIMINATED (LOOP-DESUGARING §2):
**
**   * `let mut`            -> an ordinary immutable `PCElet` (mutability was a binding-
**                            class fact the elaborator's analysis used; the core binding
**                            is immutable).
**   * reassignment `x = e` -> an SSA shadowing `PCElet` (a fresh immutable binding that
**                            shadows the old one; later reads see the new value).
**   * `while` / `for`      -> a recursive `PCEletfun` loop group whose self-call is in
**                            TAIL position (LOOP-DESUGARING §5.2/§5.3/§6) — the backend
**                            then compiles the tail self-call to a real `while` loop.
**   * `break`/`continue`/  -> applications of the `pyrt` `flow` constructors
**     `return`               (flow_break/flow_cont/flow_return) threaded by `flow_bind`;
**                            in CONTROL-PURE suites these never appear (the §3.1 fast
**                            path emits plain let-threading, no `flow`).
**
** So PyCore has NO `mut`, NO loop, NO break/continue/return nodes. There is NOTHING
** imperative left for M3 to desugar — M3 is a STRAIGHT structural map PyCore -> L2.
**
** WHY `flow`/iterators/`foldleft` ARE NOT PyCore NODES (read before adding any):
**   The control machinery (`flow` datatype + `flow_bind`, the `iter_open`/`iter_step`
**   protocol, `list_foldleft`) lives in the `pyrt` prelude (frontend/pyrt/*), NOT in
**   PyCore. The elaborator references them as ORDINARY con/var names (`PCEcon "flow_next"`,
**   `PCEvar "flow_bind"`, ...). M3 resolves those by the SAME `tr12env` fall-through that
**   resolves any prelude name (LOOP-DESUGARING §9, plan §4) — it never special-cases them.
**   Keeping them out of the node set is what lets the §8 join-point optimization swap the
**   `flow` REPRESENTATION later without touching PyCore or M3.
**
** WHY THE UIDENT/LIDENT SPLIT IS PRESERVED (same as the PyAST, M2-REPORT §2.2):
**   M3 must tell a data CONSTRUCTOR from a VAR off the NODE KIND, without re-resolving
**   names (the load-bearing case convention). So:
**     * `PCEvar`  (LIDENT) -> a d2var lookup (variable / function / loop name / pyrt fun).
**     * `PCEcon`  (UIDENT) -> a d2con lookup (data constructor, incl. the pyrt flow ctors).
**     * `PCPvar`  (LIDENT) -> a fresh pattern binder.
**     * `PCPcon`  (UIDENT) -> a constructor pattern (must resolve to a d2con).
**   A constructor APPLICATION `Node(l,x,r)` is `PCEapp(PCEcon "Node", [...])`; a flow
**   build `flow_next(a)` is `PCEapp(PCEcon "flow_next", [a])`.
**
** SPANS (LOOP-DESUGARING §9): every node carries a REAL `loctn` = the surface span of
**   the construct it came from, so a type error inside a desugared loop reports on the
**   user's `while`/`for` line and the pyrt machinery stays invisible. Only genuinely
**   synthesized binders with no surface origin (the generated `loop` NAME) use
**   `loctn_dummy()`.
**
** EXPRESSION-BODIED LAMBDAS (LOOP-DESUGARING §2): unlike the PyAST `PyElam` (whose body
**   is a stmt SUITE), a PyCore lambda's body is a PyCore EXPRESSION — the elaborator has
**   already turned the suite into a function-epilogue expression (§5.4). Same for the
**   generated `loop` bodies.
**
** PURELY ADDITIVE: consumes pyparsing.sats / pylexing.sats / locinfo.sats READ-ONLY;
** nothing under srcgen2/ or language-server/ is touched. Same 3-header discipline +
** list-alias-after-datatype + monomorphic-option-datatype dialect rules the M1/M2 SATS
** proved (ENGINEERING.md §2, M2-REPORT §2.6).
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
//
(* ****** ****** *)
//
// ==================================================================
//  pclit — PyCore literals. Same faithful-lexeme model as the PyAST `pylit`
//  (M2-REPORT §2.2): the SOURCE LEXEME is kept verbatim (quotes/prefix included)
//  so M3 synthesizes the L2 leaf token from it (ENGINEERING.md §3). true/false are
//  their own literal nodes (NOT data constructors).
// ==================================================================
//
datatype
pclit =
| PCLint  of (loctn, strn)
| PCLflt  of (loctn, strn)
| PCLstr  of (loctn, strn)
| PCLchr  of (loctn, strn)
| PCLbool of (loctn, bool)
//
(* ****** ****** *)
//
// ==================================================================
//  pcpat — PyCore PATTERNS (for `match`/`case` arms and let/lambda binders).
//
//   PCPvar  : LIDENT  — a fresh binder (or a `_`-equivalent; the wildcard is PCPwild).
//   PCPwild : `_`.
//   PCPcon  : UIDENT [args] — a constructor pattern (-> d2con). Nullary ctor has [].
//   PCPtup  : a tuple pattern `(p, p)` — emitted at loop boundaries to destructure the
//             accumulator tuple returned by a `loop` call (the §5 `val (i,acc) = loop(...)`).
//   PCPrec  : a record pattern `{ f = p, ... }`.
//   PCPlit  : a literal pattern.
//
//  (No as-pattern / annotated-pattern node in v1: the elaborator never synthesizes them,
//   and surface `as`/`p:T` patterns lower to the head pattern here — kept minimal as the
//   contract. Additive to add later if a surface feature needs it.)
// ==================================================================
//
and
pcpat =
| PCPvar  of (loctn, strn)
| PCPwild of (loctn)
| PCPcon  of (loctn, strn, list(pcpat))
| PCPtup  of (loctn, list(pcpat))
| PCPrec  of (loctn, list(pcpfield))
| PCPlit  of (loctn, pclit)
//
// a record-pattern field `name = pat`.
and
pcpfield =
| PCPField of (loctn, strn, pcpat)
//
(* ****** ****** *)
//
// ==================================================================
//  pcexp — PyCore EXPRESSIONS. THE functional core (LOOP-DESUGARING §2). Every former
//  imperative construct is now one of these.
//
//   PCElit   : a literal.
//   PCEvar   : LIDENT  — variable / function / loop-name / pyrt-fun reference (-> d2var).
//   PCEcon   : UIDENT  — data constructor reference (-> d2con); incl. pyrt flow ctors.
//   PCEapp   : application `f(a, b)`. Head ++ args. A constructor application is
//              `PCEapp(PCEcon ..., args)`; a `flow_break(accs)` is exactly this shape.
//   PCElam   : lambda — params + an EXPRESSION body (NOT a stmt suite; §2). Used for the
//              §5.3 `for` fast-path fold's `lam(a,x) => body_state` and any surface lambda.
//              M5a: a PARALLEL `list(pytypopt)` carries each param's OPTIONAL surface type
//              annotation (`PyTypNone()` for an unannotated param). It is the SAME length as
//              the param-name list; M3 lowers a `PyTypSome(T)` param to an annotated f2arg
//              pattern (`D2Pannot`), an unannotated one to a bare binder (types inferred).
//   PCElet   : immutable let-sequencing `let val p = rhs in body`. This is the workhorse:
//              straight-line state threads as a chain of these (SSA rebind), and a
//              reassignment `x = e` becomes one whose `p` re-binds the same name (§5.1).
//              M5a: carries the binding's OPTIONAL surface type annotation (`let p : T = e`);
//              `PyTypNone()` for an unannotated `let`. M3 wraps an annotated RHS in `D2Eannot`.
//   PCEletfun: a RECURSIVE `fun` group + a body: `let fun f(args)=... and g(args)=... in body`.
//              The generated loop `let fun loop(accs) = ... in <rest>` is exactly this; the
//              loop name is bound BEFORE its body so the self-call resolves to the same
//              d2var the backend's tail-call test keys on (LOOP-DESUGARING §6/§9). The
//              §6 TAIL-POSITION INVARIANT is asserted by the elaborator's lint on the
//              `loop` member before this node is handed to M3.
//   PCEif    : 3-branch `if c then t else f` EXPRESSION (always has both branches; the
//              elaborator supplies the else, even for a statement-if with no surface else).
//   PCEcase  : `case scrut of | p => e ...` — the loop combinators' flow dispatch and any
//              surface `match` lower here. Arms are (pat, body-expr).
//   PCEtup   : tuple `(e, e)` — accumulator tuples at loop boundaries (§5) and surface tuples.
//   PCErec   : record literal `{ f = e, ... }`.
//   PCElist  : list literal `[ e, e ]`.
//   PCEfield : field projection `e.name`.
//   PCEseq   : side-effect sequencing `(e1; e2)` — a bare expression statement `e` in a
//              suite becomes `PCEseq(e, kont)` (the §5.1 `let _ = e in kont`, but as an
//              explicit seq so M3 maps it to L2 `D2Eseqn`).
//   PCEunit  : the unit value `( )` — a control-pure suite that falls off the end with no
//              tail value, and the tail value of an empty function body (§5.4).
//   PCEerror : a poison node carrying a message + span — an elaboration error placeholder
//              (e.g. a reassigned immutable, break outside a loop). Non-fail-fast: the
//              elaborator emits this + a diagnostic and keeps going (matches the parser's
//              recovery spirit). M3 must surface it, never silently drop it.
// ==================================================================
//
and
pcexp =
| PCElit    of (loctn, pclit)
| PCEvar    of (loctn, strn)
| PCEcon    of (loctn, strn)
| PCEapp    of (loctn, pcexp, list(pcexp))
| PCElam    of (loctn, list(strn), list(pytypopt), pcexp)
| PCElet    of (loctn, pcpat, pytypopt, pcexp, pcexp)
| PCEletfun of (loctn, list(pcfundcl), pcexp)
| PCEif     of (loctn, pcexp, pcexp, pcexp)
| PCEcase   of (loctn, pcexp, list(pcarm))
| PCEtup    of (loctn, list(pcexp))
| PCErec    of (loctn, list(pcefield))
| PCElist   of (loctn, list(pcexp))
| PCEfield  of (loctn, pcexp, strn)
| PCEseq    of (loctn, pcexp, pcexp)
| PCEunit   of (loctn)
| PCEerror  of (loctn, strn)
//
// a record-literal field `name = expr`.
and
pcefield =
| PCEField of (loctn, strn, pcexp)
//
// a `case` arm `p [if g] => body`. The OPTIONAL GUARD `pcexpopt` carries the surface
// arm guard ELABORATED but PRESERVED (architect ruling iv, LOOP-DESUGARING §10 (iv)): the
// elaborator does NOT desugar a guarded surface arm to an inner `if` in the body — a
// failed guard must FALL THROUGH to the NEXT arm (ML/ATS `case` semantics), which an
// inner-`if` cannot express. M4 lowers a guarded arm to ATS's native guarded clause
// (`d2cls` `D2GPTgua`), which has the correct fall-through. Synthesized arms the
// elaborator builds itself (the flow/iterator dispatch) carry `PCEGNone()` (no guard).
and
pcarm =
| PCArm of (loctn, pcpat, pcexpopt, pcexp)
//
// the optional arm guard (monomorphic, non-dependent option — same dialect style as the
// PyAST `pyexpopt`, M2-REPORT §2.6: trivially matchable, transpiles cleanly).
and
pcexpopt =
| PCEGNone of ()
| PCEGSome of pcexp
//
// a member of a recursive `fun` group: `name(params) = body`. `name` is an LIDENT
// (the loop name or a surface def name); `params` are LIDENT binders; `body` is a
// PyCore expression (the function-epilogue expression, §5.4). `isloop` flags a
// generated loop member so the §6 tail-lint + M3 can recognize it. The name's `loctn`
// is `loctn_dummy()` for a synthesized loop (§9), a real span for a surface def.
//
// M5a (type-annotation carrying): two OPTIONAL type fields, additive to the original
// shape, are threaded so a typed `def` typechecks with its annotations:
//   * `ptypes` : a PARALLEL `list(pytypopt)`, SAME length as `params` — each entry is the
//                param's surface type annotation (`PyTypSome(T)`) or `PyTypNone()`. M3 lowers
//                a typed param to an annotated f2arg pattern (`D2Pannot`), an untyped one to a
//                bare binder. For a SYNTHESIZED loop the elaborator fills these from the
//                `let mut x : T` accumulator annotations so the loop function is typed
//                (the M16 untyped-loop-var deferral fix).
//   * `ret`    : the function's OPTIONAL return type (`def f(...) -> T`). M3 lowers a
//                `PyTypSome(T)` to `S2RESsome`, a `PyTypNone()` to `S2RESnone()`.
// Both are OPTIONAL end-to-end — an unannotated def carries `PyTypNone()` everywhere and
// lowers exactly as before (types inferred). The printer renders them only when present.
and
pcfundcl =
| PCFundcl of (loctn, strn, list(strn), list(pytypopt), pytypopt, pcexp, bool)
//
(* ****** ****** *)
//
// ==================================================================
//  pcdatacon / pcdecl — top-level PyCore DECLARATIONS.
//
//   PCCdata  : a datatype `enum Name[tvs]: case Con | case Con(types) ...`. Carried through to
//              M3 verbatim from the surface `enum`; the elaborator does not transform it (no
//              imperative content). Constructor arg TYPES are kept as surface `pytyp` (M3 owns
//              type lowering, same split as the PyAST). The trailing `pcmode` (M5b.6a) is the
//              decorator-selected datatype sort: @boxed/none->boxed tbox, @viewtype->linear vtbx
//              (@unboxed has no stock unboxed-datatype primitive -> pinned to BOXED tbox).
//   PCCfun   : a top-level (possibly recursive) `fun` group from one or more surface
//              `def`s — its members are elaborated function bodies (§5.4). Adjacency =
//              mutual recursion (M3's grouping concern, mirrored by order; PYTHON-FRONTEND
//              §5.2). A single `def` is a one-member group.
//   PCCval   : a top-level immutable binding `val p = e` (a module-level `let`/expr-stmt
//              that produced a value/effect). Module-init statements thread here.
//   PCCstaload: a `staload` of `pyrt` (or an imported module). The elaborator EMITS one
//              `PCCstaload("pyrt")` at the head of any module whose elaboration referenced
//              the `flow`/iterator/fold machinery, so the desugared output `staload`s the
//              prelude it depends on (LOOP-DESUGARING §9). M3 turns it into the L2 staload.
//   PCCalias : a plain `type X = T` alias -> a D2Csexpdef. Carries the alias NAME, its
//              type-param names (a non-empty list is the parametric path), and the aliased
//              SURFACE type (`pytyp`). M3 lowers the surface type via `pylower_typ` (inheriting
//              the M5a primitive mitigation) and builds the `D2Csexpdef`. Mode-agnostic (boxed):
//              a plain alias carries no decorator; `struct` carries its mode via PCCrecord.
//   PCCrecord: a `struct` -> a record-type alias (D2Csexpdef + S2Etrcd) carrying its MODE
//              (M5b.6a). Unlike PCCalias, it keeps the RAW field list (`list(pcfield)`) plus a
//              `pcmode`, so M3 selects the S2Etrcd `trcdknd` + the alias sort from the decorator
//              (@boxed/none->boxed TRCDbox0/tbox, @viewtype->linear TRCDbox1/vtbx, @unboxed->flat
//              TRCDflt0/tflt). Parametric structs wrap the body in s2exp_lam1 exactly as PCCalias.
//   PCCerror : an elaboration-error placeholder at decl level (recovery).
// ==================================================================
//
and
pcdecl =
| PCCdata    of (loctn, strn, list(pcparam), list(pcdatacon), pcmode)
| PCCfun     of (loctn, list(pcfundcl))
| PCCval     of (loctn, pcpat, pcexp)
| PCCstaload of (loctn, strn)
| PCCalias   of (loctn, strn, list(pcparam), pytyp)
| PCCrecord  of (loctn, strn, list(pcparam), list(pcfield), pcmode)
| PCCerror   of (loctn, strn)
//
// M5b.6b: a type param carries its surface sort name (Type/VType/Prop, "" = none ⇒ default
// Type) + an @unboxed flag; M3 maps these to the s2var sort. (The names are still all that
// the monomorphic path needs; the parametric path now reads the sort.)
and
pcparam =
| PCParam of (loctn, strn(*name*), strn(*sort name, "" if none*), bool(*unboxed*))
//
// the memory/representation MODE selected by a §5.7 type-declaration decorator:
//   @boxed / none -> PCMbox  (boxed datatype `the_sort2_tbox` / record S2Etrcd(TRCDbox0)),
//   @viewtype     -> PCMlin  (linear  datatype `the_sort2_vtbx` / record S2Etrcd(TRCDbox1)),
//   @unboxed      -> PCMflat (flat record S2Etrcd(TRCDflt0); a flat DATATYPE has no stock
//                             primitive — M5b.6a pins it to BOXED with a code comment).
// M5b.6a: only the DECL-level decorators on `enum`/`struct` select a mode here; the type-PARAM
// sort annotations (`[A: VType @unboxed]`) are a separate later slice (M5b.6b).
and
pcmode =
| PCMbox  of ()
| PCMlin  of ()
| PCMflat of ()
//
// a data constructor in a PyCore datatype: UIDENT + arg types (surface `pytyp`).
and
pcdatacon =
| PCDataCon of (loctn, strn, list(pytyp))
//
// a `struct` field `name: T` (M5b.6a). A `struct` -> a record-type alias (D2Csexpdef +
// S2Etrcd) carrying its mode; PCCrecord keeps the RAW fields (not a desugared PyTrec) so the
// mode threads to the S2Etrcd `trcdknd`/sort at lowering. (Distinct from the surface PyField
// so the PyCore layer is self-contained; same shape.)
and
pcfield =
| PCField of (loctn, strn, pytyp)
//
(* ****** ****** *)
//
// list aliases — declared AFTER the datatype block (the verified M2 ordering rule: a
// forward `#typedef` before the block resolves the element to an impredicative `type`
// and breaks L3 packing). Datatype fields above use the inline `list(...)` form.
//
#typedef pcexplst  = list(pcexp)
#typedef pcpatlst  = list(pcpat)
#typedef pcarmlst  = list(pcarm)
#typedef pcfundclst = list(pcfundcl)
#typedef pcdeclst  = list(pcdecl)
//
(* ****** ****** *)
//
// ==================================================================
//  pcdiag — an elaboration diagnostic (a message + the surface span it is reported at).
//  Severity is implicit (all are errors in v1). The elaborator NEVER throws: a misuse
//  (reassign-immutable, break/continue outside a loop, return outside a function,
//  use-before-init of a mut) records a `PCDiag` AND emits a `PCEerror`/`PCCerror` poison
//  node, then keeps elaborating (non-fail-fast, matches the parser).
// ==================================================================
//
datatype
pcdiag =
| PCDiag of (loctn, strn)
//
#typedef pcdiaglst = list(pcdiag)
//
(* ****** ****** *)
//
// ==================================================================
//  pcmodule — the elaborated module: a PyCore decl list + elaboration diagnostics.
//  The fresh value the (pure, re-entrant) elaborator returns per call.
// ==================================================================
//
datatype
pcmodule =
| PCModule of (list(pcdecl), list(pcdiag))
//
(* ****** ****** *)
//
// ==================================================================
//  Location accessors — uniform getters (the printer / M3 fetch a node's span without
//  re-matching).
// ==================================================================
//
fun pcexp_loctn(e: pcexp): loctn
fun pcpat_loctn(p: pcpat): loctn
fun pcdecl_loctn(d: pcdecl): loctn
//
(* ****** ****** *)
//
// ==================================================================
//  The elaborator entry (frontend/DATS/pyelab_*.dats). PURE per call (plan §6.2): takes
//  a parsed PyAST module, returns a fresh PyCore module + diagnostics; NO global state.
//
//  `pyelab_module(m)` runs the §4 accumulator analysis + §5 elaboration + §6 tail-lint
//  over every decl of `m`, carrying `m`'s parse diagnostics into the result (so the
//  harness shows BOTH parse and elaboration errors).
// ==================================================================
//
fun
pyelab_module(m: pymodule): pcmodule
//
(* ****** ****** *)
//
// ==================================================================
//  The PyCore pretty-printer (frontend/DATS/pyelab_print.dats) — golden tests + debugging.
//  S-expression-ish, one construct per parenthesized form, `@span` on every node (same
//  format as the PyAST printer, so spans are directly comparable). The §10 goldens are
//  diffed against this.
// ==================================================================
//
fun pclit_fprint(out: FILR, lit: pclit): void
fun pcpat_fprint(out: FILR, p: pcpat): void
fun pcexp_fprint(out: FILR, e: pcexp): void
fun pcdecl_fprint(out: FILR, d: pcdecl): void
fun pcdiag_fprint(out: FILR, g: pcdiag): void
//
// dump a whole module (decls, then a `==== diagnostics ====` section) to `out`.
fun pcmodule_fprint(out: FILR, m: pcmodule): void
//
(* ****** ****** *)
(*
end of [frontend/SATS/pycore.sats]
*)
