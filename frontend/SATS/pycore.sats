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
//   PCPcon  : UIDENT [{sargs}] [args] — a constructor pattern (-> d2con). Nullary ctor has [].
//             C-PROOF: the `list(strn)` SARGS field is the EXISTENTIAL-UNPACK static binders
//             (`VCons{n}(x, rest)` — `{n}` binds the con's hidden index). [] = a plain con pattern.
//             M3 lowers a non-empty sargs to `d2pat_sapp(<con>, [<fresh int-sorted s2vars>])`
//             wrapped under the value-arg `D2Pdapp` (CP-UNP-spike-proven nerror=0).
//   PCPtup  : a tuple pattern `(p, p)` — emitted at loop boundaries to destructure the
//             accumulator tuple returned by a `loop` call (the §5 `val (i,acc) = loop(...)`).
//   PCPrec  : a record pattern `{ f = p, ... }`.
//   PCPlit  : a literal pattern.
//   PCPas   : an as-pattern `p as x` (M7) — binds the WHOLE matched value to the LIDENT `x`
//             AND keeps matching the inner pattern `p`. Carries the bound NAME first, then the
//             inner pattern (the surface PyPas's `(loc, inner, name)` is reordered here to put
//             the name adjacent to the loc, mirroring PCPvar's `(loc, name)` head). M3 lowers
//             it to L2 `D2Prfpt(<inner>, AS-tok, D2Pvar x)` (dynexp2.sats:757), so `x` is a
//             fresh, registered binder usable in the arm body (the dropped-binding bug fix).
//
//   PCPbang : `!p` — generated view/read pattern prefix. Lowers to `D2Pbang`.
//   PCPflat : `@p` — generated flat/viewbox pattern prefix. Lowers to `D2Pflat`.
//
//  (No annotated-pattern node in v1: the elaborator drops a surface `p:T` to its head pattern
//   `p`; additive to add later if a surface feature needs the annotation.)
// ==================================================================
//
and
pcpat =
| PCPvar  of (loctn, strn)
| PCPwild of (loctn)
| PCPcon  of (loctn, strn, list(strn)(*sargs*), list(pcpat))
| PCPtup  of (loctn, list(pcpat))
| PCPrec  of (loctn, list(pcpfield))
| PCPlit  of (loctn, pclit)
| PCPas   of (loctn, strn(*name*), pcpat(*inner*))
| PCPbang of (loctn, pcpat(*inner*))
| PCPflat of (loctn, pcpat(*inner*))
// B-LINEAR: the LINEAR-CONSUME pattern `~p` — wraps the inner consumed pattern. Lowers to the
// D2Pfree node (f0_free is a structural pass-through; SPIKE BL-LIN nerror=0).
| PCPfree of (loctn, pcpat(*inner*))
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
//              M7-closures: the leading `bool` is the `@func` HINT (true = the surface lambda
//              was prefixed with `@func` and PASSED the elaborator's non-capture check). It is
//              a recorded hint for future codegen (a flat-fun representation); it does NOT
//              change the L2 closure-kind (the spike showed it's inferred from context). A
//              synthesized loop-fold lambda is `false` (it is internal, not @func).
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
//   PCEllazy : linear lazy value `llazy: suite` / `llazy(expr)` -> D2El1azy.
//              The body is already the suite-folded thunk expression.
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
| PCElam    of (loctn, bool(*@func*), list(strn), list(pytypopt), pcexp)
| PCElet    of (loctn, pcpat, pytypopt, pcexp, pcexp)
//   PCEvarcell : a MUTABLE CELL binding `var name [: T] = init in body` (ATS-parity
//                var/mutation). DISTINCT from `PCElet`: the elaborator emits this for a
//                surface `var` (PySvar), NEVER for a `let`/`let mut`/SSA-rebind. It is a
//                real in-place cell — its name is NOT a loop accumulator (it never enters
//                the loop `muts`/`accs` set; LOOP-DESUGARING). M3 lowers it to a
//                `D2Cvardclst` (via d2vardcl_make_args, vpid=None — views are threaded but
//                not enforced at typecheck) wrapped in a `D2Elet0` over `body`; a later
//                `PCEvar name` reads the cell (typed T, as an lvalue of T).
//   PCEassign  : a CELL ASSIGNMENT `lval := rval` (ATS-parity `:=`). DISTINCT from the
//                SSA-rebind `PCElet` the `=` path emits. M3 lowers it to L2 `D2Eassgn`
//                (typecheck checks rval against lval's type, returns void). The `lval` is a
//                `PCEvar name` for v1 (field/index later).
| PCEvarcell of (loctn, strn, pytypopt, pcexp(*init*), pcexp(*body*))
| PCEassign of (loctn, pcexp(*lval*), pcexp(*rval*))
// B-LINEAR: address-of `&x` -> D2Eaddr ; deref `!p` -> D2Eeval ; move `x :=> y` -> D2Exazgn ;
// swap `x :=: y` -> D2Exchng. All proven nerror=0 (SPIKE BL-ADDR/BL-DERF2/BL-MV/BL-SW). The
// move/swap l-values pair with `var` cells (PCEvarcell).
| PCEaddr   of (loctn, pcexp(*lval*))
| PCEderef  of (loctn, pcexp(*ptr*))
| PCEmove   of (loctn, pcexp(*lval*), pcexp(*rval*))
| PCEswap   of (loctn, pcexp(*lval*), pcexp(*rval*))
| PCEletfun of (loctn, list(pcfundcl), pcexp)
| PCEif     of (loctn, pcexp, pcexp, pcexp)
| PCEcase   of (loctn, pcexp, list(pcarm))
| PCEllazy  of (loctn, pcexp)
| PCEtup    of (loctn, list(pcexp))
| PCErec    of (loctn, list(pcefield))
| PCElist   of (loctn, list(pcexp))
| PCEfield  of (loctn, pcexp, strn)
| PCEseq    of (loctn, pcexp, pcexp)
| PCEunit   of (loctn)
//   PCEraise : `raise e` (EXN) -> D2Eraise. `e` lowers to an exn-typed expr.
//   PCEtry   : `try body except <pat>: handler ...` (EXN) -> D2Etry0. The body is a single
//              elaborated pcexp (the surface body-suite was folded by el_func_body); the
//              except clauses are pcarm (reusing the match-clause machinery, lowered to
//              d2cls over the caught exn).
| PCEraise  of (loctn, pcexp)
| PCEtry    of (loctn, pcexp(*body*), list(pcarm)(*handlers over exn*))
//   PCEinst : `@inst[T1, ..] e` (A-template) — an EXPRESSION-position TEMPLATE INSTANTIATION. It
//             carries the type-ARG list (`list(pytyp)`, the `[T1, ..]` brackets) + the instantiated
//             inner expression. M3 lowers it (pl_exp) to a tapp nested in the value-app: when the
//             inner is a call `PCEapp(f, args)`, `D2Edapp(d2exp_tapp(<f>, <types>), -1, <args>)`;
//             when it is a bare head, `d2exp_tapp(<inner>, <types>)`. The surface `@inst[Int] foo(5)`
//             thus reaches ATS `foo<Int>(5)`. (Resolution/monomorphization is deferred to trtmp3b/3c,
//             AFTER tread3a, so the instantiated form typechecks structurally — SPIKE T3-proven.)
| PCEinst   of (loctn, list(pytyp), pcexp)
//   PCEwhere : SCOPING (bootstrap P1) — a def BODY wrapped in a `where:` block: `e where {decls}`.
//              Carries the body expr + the ELABORATED where-decls. M3 lowers it (pl_exp) to
//              D2Ewhere(<body>, <lowered where-decls>) — the where-decls are BACKWARDS-scoped around
//              the body (ATS `where`), so a body reference to a where-defined helper resolves.
//              SPIKE-PROVEN (S1, nerror=0). Only the elaborator's def-body wrapping builds it.
| PCEwhere  of (loctn, pcexp(*body*), list(pcdecl)(*where-decls*))
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
//              decorator-selected datatype sort: @boxed/none->boxed tbox, @linear->linear vtbx
//              (@unboxed has no stock unboxed-datatype primitive -> pinned to BOXED tbox).
//   PCCfun   : a top-level (possibly recursive) `fun` group from one or more surface
//              `def`s — its members are elaborated function bodies (§5.4). Adjacency =
//              mutual recursion (M3's grouping concern, mirrored by order; PYTHON-FRONTEND
//              §5.2). A single `def` is a one-member group.
//   PCCval   : a top-level immutable binding `val p = e` (a module-level `let`/expr-stmt
//              that produced a value/effect). Module-init statements thread here.
//   PCCstaload: an AUTO `staload` of `pyrt`. The elaborator EMITS one
//              `PCCstaload("pyrt")` at the head of any module whose elaboration referenced
//              the `flow`/iterator/fold machinery, so the desugared output `staload`s the
//              prelude it depends on (LOOP-DESUGARING §9). M3 turns it into a NO-OP — pyrt is
//              loaded out-of-band (globally) by the driver's `pyrt_pvsload()`, so this auto node
//              needs no per-file work. DO NOT route user imports here (they must NOT be global).
//   PCCimport: a USER `import M` / `from M import x` (M7-import; task #34). Carries the RESOLVED
//              XATSHOME-relative `.sats` path (e.g. `/frontend/TEST/m7imp/lib.sats`), the
//              static/dynamic load kind (0=static `.sats` interface — the only supported case),
//              and an `is_python` flag set when the module path pointed at a Python-surface
//              `.psats`/`.pdats` (DEFERRED — those need recursing OUR frontend, which the stock
//              `d0parsed_from_fpath` cannot parse; M3 emits a graceful diagnostic, not a crash).
//              M3 (pylower_decl00) LOADS the module via parse+trans01+trans12, then SCOPED-merges
//              its `f2env` into THIS file's `tr12env` via `tr12env_add1_f2env(env, DLRDT_symbl,
//              fenv)` — per-file, NO global pervasive leak (contrast `filpath_pvsload`, which
//              merges into the GLOBAL pervasive env and would pollute every later check). It emits
//              a real `D2Cstaload` (for the LSP dep-graph), NOT a `D2Cnone0`.
//   PCCalias : a plain `type X = T` alias -> a D2Csexpdef. Carries the alias NAME, its
//              type-param names (a non-empty list is the parametric path), and the aliased
//              SURFACE type (`pytyp`). M3 lowers the surface type via `pylower_typ` (inheriting
//              the M5a primitive mitigation) and builds the `D2Csexpdef`. Mode-agnostic (boxed):
//              a plain alias carries no decorator; `struct` carries its mode via PCCrecord.
//   PCCrecord: a `struct` -> a record-type alias (D2Csexpdef + S2Etrcd) carrying its MODE
//              (M5b.6a). Unlike PCCalias, it keeps the RAW field list (`list(pcfield)`) plus a
//              `pcmode`, so M3 selects the S2Etrcd `trcdknd` + the alias sort from the decorator
//              (@boxed/none->boxed TRCDbox0/tbox, @linear->linear TRCDbox1/vtbx, @unboxed->flat
//              TRCDflt0/tflt). Parametric structs wrap the body in s2exp_lam1 exactly as PCCalias.
//   PCCerror : an elaboration-error placeholder at decl level (recovery).
// ==================================================================
//
and
pcdecl =
| PCCdata    of (loctn, strn, list(pcparam), list(pcdatacon), pcmode)
//   PCCfun : a top-level def group. DEP (Stages 1–2): the `list(pcparam)` carries the def's §5.7
//            type/INDEX params (`def f[A, n: SInt](...)`) — each pcparam its name + sort name +
//            @unboxed flag (the SAME shape PCCdata/PCCalias carry). M3 builds an s2var per param at
//            its psort2_of sort (a `[n: SInt]` -> an int-sorted s2var, via SInt->the_sort2_int0),
//            binds them in scope while lowering the param/return types (so `Vec[A, n]` / `SInt`
//            resolve `n`/`A`), and quantifies the D2Cfundclst over them (the t2qag `tqas` field —
//            the stock f0_fundclst mechanism). EMPTY list = a NON-generic def (byte-identical to
//            before this slice). Loop-generated fun groups (PCEletfun) carry NO typarams.
//            C-PROOF: the 3rd field `list(pytyp)` is the OPTIONAL `@terminates[n]` TERMINATION
//            METRIC — a list of index EXPRESSIONS (`[n]`, `[m, n]`) referencing the def's own
//            typarams. EMPTY = no metric (byte-identical to before C-proof). M3 lowers a non-empty
//            metric to an `F2ARGmets([<lowered index s2exps>])` f2arg PREPENDED to the def member's
//            f2arglst (the stock totality-checker metric; trans2a/trans23 treat it type-agnostically).
| PCCfun     of (loctn, list(pcparam), list(pytyp)(*metric*), list(pcfundcl))
| PCCval     of (loctn, pcpat, pcexp)
| PCCstaload of (loctn, strn)
| PCCimport  of (loctn, strn(*resolved XATSHOME-rel .sats path*), sint(*0=static*), bool(*is_python: defer*))
| PCCalias   of (loctn, strn, list(pcparam), pytyp)
| PCCrecord  of (loctn, strn, list(pcparam), list(pcfield), pcmode)
//   PCCabstype : an `abstype Name [tvs] [<= REP]` OPAQUE type declaration (ATS-parity). Carries
//                the type NAME, its type-param names, the decorator-selected MODE (@boxed/none->
//                boxed tbox, @unboxed->flat tflt; @linear deferred -> boxed with a note), and an
//                OPTIONAL REPRESENTATION witness `<= REP` (TAIL ITEM 1, the stock
//                `abstype stamp_type <= uint`). M3 lowers it to D2Cabstype(s2cst, A2TDFsome())
//                when the rep is absent, or D2Cabstype(s2cst, A2TDFlteq(<lowered REP>)) when
//                present: an s2cst with NO sexp attached (opacity holds at typecheck — a distinct
//                singleton). The `<= REP` is codegen-only / informational (NOT typecheck-
//                constraining — srcgen2 trans23/trans2a pass it through). No imperative content.
//   PCCassume  : an `assume Name [tvs] = T` representation (ATS-parity). Carries the abstract
//                type's NAME + optional static params + the concrete representation SURFACE type.
//                M3 SELECTS the already-registered abstract s2cst by name (tr12env_find_s2itm ->
//                SIMPLone1), lowers T via pylower_typ, wraps parametric reps in s2exp_lam1, and
//                builds D2Cabsimpl(tok, simpl, s2exp).
//   PCCextern  : an `extern def foo[T](params) -> Ret` FFI bodyless SIGNATURE (ATS-parity). Carries
//                the fun NAME, its type params, param names + OPTIONAL types (parallel lists,
//                M5a-style), and the OPTIONAL return type. M3 builds the function type, makes a
//                d2cst, REGISTERS it (so calls resolve), and emits D2Cextern(tok,
//                D2Cdynconst(...)). No body.
| PCCabstype of (loctn, strn, list(pcparam), pcmode, pytypopt(*<= REP*))
| PCCassume  of (loctn, strn, list(pcparam), pytyp)
| PCCextern  of (loctn, strn, list(pcparam), list(strn), list(pytypopt), pytypopt)
//   PCCimplement : an `implement NAME(params) [-> Ret]: <body>` body for a pre-declared function
//                  (ATS-parity). Carries the implemented fun NAME, whether a dynamic `(params)`
//                  group was written, its param names + OPTIONAL types (parallel lists, M5a-style),
//                  the OPTIONAL return type, and the ELABORATED body (a pcexp — the suite was
//                  folded by el_func_body, like a def). M3 (SPIKE-PROVEN recipe,
//                  pyfront_surf1_spike.dats; mirrors stock f0_implmnt0_dimp @
//                  trans12_decl00.dats:3373) RESOLVES the pre-declared d2cst by NAME (DIMPLone1),
//                  binds the params in a lam scope when present, lowers the body, and emits
//                  D2Cimplmnt0.
//   PCCoverload  : an `overload NAME with IMPL` (ATS-parity `#symload`). Carries the overloaded NAME +
//                  the IMPL NAME (an already-registered def/extern). M3 (SPIKE-PROVEN; mirrors stock
//                  f0_symload @ trans12_decl00.dats:2056) resolves IMPL's d2itm, REGISTERS NAME -> a
//                  D2ITMsym bucket via tr12env_add0_d2itm (the load-bearing step), emits D2Csymload.
//   A-TEMPLATE: PCCimplement carries both the def's own polymorphic params (`def f[A]`) and the
//   TRAILING `list(pytyp)` = the `@impl[Int, ..]` template-arg INSTANTIATION list (the `tias`).
//   A bare `@impl def` (no brackets) carries `[]` for both lists (byte-identical to before this
//   slice). `@impl def f[A]` lowers `A` as impl-side tqas; `@impl[Int] def f` lowers the decorator
//   payload as `tias`.
| PCCimplement of (loctn, strn, list(pcparam)(*tvs*), bool(*has darg*), list(strn), list(pytypopt), pytypopt, pcexp, list(pytyp)(*tias*))
| PCCoverload  of (loctn, strn(*name*), strn(*impl*))
//   PCCsymalias : a STANDALONE overload-ALIAS decl `@overload NAME = TARGET` (+ optional
//                 precedence `@overload[N] NAME = TARGET`) — the ATS-parity `#symload NAME with
//                 TARGET [of N]` (2012× corpus-wide). UNLIKE PCCoverload (which the `@overload def`
//                 path emits as a SELF-overload NAME->NAME right after defining NAME), this RE-EXPORTS
//                 an ALREADY-EXISTING function TARGET into the overload set of a DIFFERENT symbol NAME
//                 — there is NO def being defined here. `precopt` carries the resolution precedence:
//                 `~1` = no `[N]` given (the stock default 0 is used at lowering), else the parsed N.
//                 M3 (build_overload, same SPIKE-PROVEN f0_symload recipe as PCCoverload, but using
//                 the precedence as the d2ptm's pval) resolves TARGET's d2itm, REGISTERS NAME -> a
//                 D2ITMsym bucket via tr12env_add0_d2itm, and emits D2Csymload. Precedence IS read at
//                 typecheck (trsym2b_dynexp.dats auxpmax/auxtake prune the bucket to the max pval),
//                 so it is load-bearing, not cosmetic.
| PCCsymalias  of (loctn, strn(*name*), strn(*target*), sint(*precopt; ~1 = none*))
//   PCCtempl : a `@template[A, B] def foo[C, D](params) [-> Ret] [: body]` TEMPLATE declaration
//              (A-template). Carries:
//                * the TEMPLATE-arg binders (`list(pcparam)`, the `@template[A,B]` brackets) -> the
//                  d2cst's `tqas` (the `fun{A,B}` args), via t2qag_make_s2vs.
//                * the fun NAME.
//                * the POLYMORPHIC-arg binders (`list(pcparam)`, the `foo[C,D]` brackets) -> the fn
//                  type's universal `s2exp_uni0` quantifier (the `tqas`-on-fundclst half we lower
//                  for an ordinary def — here wrapping the bodyless extern's fn type).
//                * the value param names + OPTIONAL types (parallel, M5a-style) + OPTIONAL return.
//                * an OPTIONAL inline BODY (`pcexpopt`): PRESENT ⇒ the template is DECLARED (extern
//                  fun{A,B}) AND given its GENERIC implement in one shot (like ATS `fn{a} foo(x)=e`);
//                  ABSENT ⇒ declaration-only (extern fun{A,B}), bodies come from separate @impl[…]s.
//              M3 (pylower_decl00) builds the template extern via build_template_extern (the spike's
//              build_template_id/foo recipe: a NON-EMPTY tqas makes d2cst_tempq=true), and, when a
//              body is present, ALSO emits the generic implement (tias=[]).
| PCCtempl     of ( loctn
                  , list(pcparam)(*template args*)
                  , strn
                  , list(pcparam)(*polymorphic args*)
                  , list(strn), list(pytypopt), pytypopt
                  , pcexpopt(*inline body*) )
//   PCCsortdef : a `sortdef Name = SORT` SORT ALIAS (ATS-parity). Carries the alias NAME +
//                the RHS SORT-reference NAME (a sort vocab string like SInt/Type/Prop). M3
//                maps the RHS string to a sort2 (the psort2_of vocab) and emits
//                D2Csortdef(symbl_make_name(name), S2TEXsrt(<sort2>)) + tr12env_add0_s2tex.
//   PCCstacst  : a `stacst Name : SORT` STATIC-CONSTANT decl (ATS-parity). Carries the
//                constant NAME + its SORT-reference NAME. M3 builds an s2cst at that sort via
//                s2cst_make_idst, registers it (tr12env_add1_s2cst), and emits D2Cstacst0.
//   PCCstadef  : a `stadef Name = <static-expr>` STATIC-LEVEL DEFINITION (ATS-parity). v1
//                supports an int-literal body. Carries the NAME + the ELABORATED body (a pcexp;
//                v1 a PCElit int). M3 lowers the body to an s2exp (the index-lit -> s2exp_int)
//                and emits a D2Csexpdef via build_sexpdef.
//   PCCsortsub : a `@sort type Nat = {a: SInt | a >= 0}` SUBSET (refined) SORT (ATS-parity
//                `sortdef Nat = {a:int | a>=0}`). Carries the alias NAME, the BINDER (a pcparam —
//                its psort2_of sort is the carrier sort) + the guard list (raw `pytyp` bool-index
//                predicates, lowered like def-param guards). M3 emits D2Csortdef(name,
//                S2TEXsub(<binder s2var>, [<lowered guards>])) + tr12env_add0_s2tex (SX-SUB-proven).
| PCCsortdef of (loctn, strn(*name*), strn(*sort-ref*))
| PCCsortsub of (loctn, strn(*name*), pcparam(*binder*), list(pytyp)(*guards*))
| PCCstacst  of (loctn, strn(*name*), strn(*sort-ref*))
| PCCstadef  of (loctn, strn(*name*), pcexp(*static body*))
//   PCCprfun : a `prfun` proof FUNCTION (ATS-parity). Structurally PCCfun: carries its §5.7
//              type/index params + a single elaborated PCFundcl (body present). M3 lowers it
//              like PCCfun but swaps the funkind token to T_FUN(FNKprfn1).
//   PCCprval : a `prval` proof VALUE (ATS-parity). Like PCCval but carries an OPTIONAL type
//              annotation. M3 lowers it like PCCval but with the valkind token T_VAL(VLKprval).
//   PCCpraxi : a `praxi` proof AXIOM (ATS-parity). Bodyless, structurally PCCextern: carries the
//              NAME + param names + OPTIONAL types + the OPTIONAL return type. M3 builds the
//              function type + a registered d2cst + emits D2Cstatic(D2Cdynconst) with the proof
//              funkind T_FUN(FNKpraxi).
| PCCprfun  of (loctn, list(pcparam), pcfundcl)
| PCCprval  of (loctn, pcpat, pytypopt, pcexp)
| PCCpraxi  of (loctn, strn, list(strn), list(pytypopt), pytypopt)
//   PCCexcept : `exception E(T...)` (EXN) — an exception CONSTRUCTOR decl. Carries the con
//               NAME + its surface arg types. M3 lowers it to a D2Cexcptcon: a d2con of the
//               built-in `exn` type (the_s2cst_excptn), registered like a datatype con so
//               `raise E` / `except E` resolve. Nullary `exception Empty` has [].
| PCCexcept  of (loctn, strn, list(pytyp))
//   PCCprivate : SCOPING (bootstrap P1) — a RUN of `private` decls (a single `private def …`
//                modifier → a one-element run, or a `private:` block → the indented suite). The
//                MODULE/SUITE driver (pylower_decls) applies the CAPTURE-REST transform: the
//                privates become the local-HEAD (D1) and ALL FOLLOWING sibling decls in the same
//                suite become the local-BODY (D2) of a single D2Clocal0(D1, D2) — so the privates
//                are visible to D2 but NOT exported past the block. SPIKE-PROVEN (S2, nerror=0).
//                FAITHFULNESS: capture-rest is exact for the dominant case where `local…end` is the
//                TAIL of its scope (a `private` run is followed by all the publics it scopes); the
//                rare "decls AFTER the end of the local" ATS shape is a future pretty-printer concern.
| PCCprivate of (loctn, list(pcdecl)(*private decls*))
| PCCerror   of (loctn, strn)
//
// M5b.6b: a type param carries its surface sort name (Type/Linear/Prop, "" = none ⇒ default
// Type) + an @unboxed flag; M3 maps these to the s2var sort. (The names are still all that
// the monomorphic path needs; the parametric path now reads the sort.)
and
pcparam =
| PCParam of (loctn, strn(*name*), strn(*sort name, "" if none*), bool(*unboxed*))
//
// the memory/representation MODE selected by a §5.7 type-declaration decorator:
//   @boxed / none -> PCMbox  (boxed datatype `the_sort2_tbox` / record S2Etrcd(TRCDbox0)),
//   @linear       -> PCMlin  (linear  datatype `the_sort2_vtbx` / record S2Etrcd(TRCDbox1)),
//   @unboxed      -> PCMflat (flat record S2Etrcd(TRCDflt0); a flat DATATYPE has no stock
//                             primitive — M5b.6a pins it to BOXED with a code comment).
// M5b.6a: only the DECL-level decorators on `enum`/`struct` select a mode here; the type-PARAM
// sort annotations (`[A: Linear @unboxed]`) are a separate later slice (M5b.6b).
//
// DEP (dataprop/dataview): two PROOF/VIEW datatype modes carry the prop/view sort through the SAME
// PCCdata pipeline (DEP-spike P4/P9). They are emitted ONLY for a `dataprop`/`dataview` decl (a
// keyword fixes the kind — no decorator selects them), and consumed ONLY by dt_sort_of (the
// datatype sort): PCMprop -> the_sort2_prop, PCMview -> the_sort2_view. The record/abstype mode
// helpers never see them (those decls can't be prop/view); a defensive fallback keeps them total.
and
pcmode =
| PCMbox  of ()
| PCMlin  of ()
| PCMflat of ()
| PCMprop of ()
| PCMview of ()
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
