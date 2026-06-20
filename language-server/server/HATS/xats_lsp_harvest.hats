(* ****** ****** *)
(*
xats_lsp_harvest.hats — the SINGLE typed-AST harvest traversal.

SHARED, single source of truth, #include'd by:
  * language-server/server/resident/DATS/xats_lsp_resident.dats (editor server)
  * language-server/server/DATS/xats_lsp_check.dats             (one-shot checker)

This holds the ONE copy of the harvest:
  * the SOURCE FILTER (loc_fpath / lcsrc_fpath / loc_in_topfile / the_top_path):
    only emit for nodes whose source == the top file being checked, so the walk
    never attributes an #include'd / #staload'd node's coords to the current uri
    (the include-leak bug). The top path is captured ONCE per harvest from
    d3parsed_get_source (the exact lcsrc the compiler stamped on top nodes), so
    the per-node guard is an identity match.
  * the CLASSIFIERS (errck -> §4.1 code + message);
  * the HOVER / DEFINITION / SEMANTIC-TOKEN emission helpers;
  * the mutually-recursive d2/d3-family WALK;
  * harvest_d3parsed (set top-path; walk; reset) — the universally-shared
    post-check work. A consumer that also needs dependency extraction / signature
    stamping (the resident) wraps THIS, calling it for the walk.

The four EMIT SINKS are ABSTRACT here — declared `#extern fun … = $extnam()` —
and each consumer implements them:
  diag_push  — push one diagnostic   (0-based coords + code + message)
  hover_push — push one hover entry   (0-based coords + type string + kind)
  def_push   — push one definition    (use range + def range + type-def range)
  token_push — push one semantic token (range + ttype + tmods + def-path)
  * RESIDENT: implements all four -> LSP_*   (tokens active).
  * CHECKER : implements diag/hover/def -> LSPCHK_*, and a NO-OP token_push
              (it has no semantic tokens; the shared walk calls it, it drops it).

Requires (in scope via the including file's compiler headers):
  locinfo  : loctn / postn accessors (pbeg/pend/ntot/nrow/ncol), loctn_dummy
  dynexp1  : bare D1Eid0 + d1exp.node()
  filpath  : fpath_get_fnm1
  statyp2 / staexp2 / dynexp2 / dynexp3 : the AST node families + accessors
The including file must also provide BEFORE this #include:
  fun typ_to_strn (t2p): string         -- leaf head-name renderer (mismatch msgs)
  + the s2typ pretty-printer (#include xats_lsp_typrint.hats) -> typ_pretty,
    typr_funq (used for function-vs-variable token classification).
*)
(* ****** ****** *)
(* ====================================================================== *)
(*           ABSTRACT EMIT SINKS  (each consumer implements these)         *)
(* ====================================================================== *)
//
// The harvest pushes rows into FOUR sinks, which are ABSTRACT to this HATS — it
// only CALLS them; each consumer DECLARES + IMPLEMENTS them BEFORE this #include
// (their JS bodies differ, so the binding can't live here):
//
//   fun diag_push ( l0,c0,l1,c1: int, code,message: string ): void
//   fun hover_push( l0,c0,l1,c1: int, typ,kind: string ): void
//   fun def_push  ( ul0,uc0,ul1,uc1: int, defpath: string
//                 , dl0,dc0,dl1,dc1: int, entity: string
//                 , hastdef: int, tdpath: string
//                 , tl0,tc0,tl1,tc1: int ): void
//   fun token_push( l0,c0,l1,c1: int, ttype,tmods: int, defpath: string ): void
//
//   * RESIDENT: declares them in SATS + binds via #implfun -> LSP_*  (the .cats);
//               token_push is the live LSP_token_push (semantic tokens active).
//   * CHECKER : declares them as #extern …=$extnam() -> LSPCHK_*  (the .cats),
//               and binds token_push to a NO-OP (it has no semantic tokens; the
//               shared walk calls it, the checker drops the row).
// Coords are 0-based internal coords throughout.
//
(* ****** ****** *)
//
// helper: is a list empty?
//
fun
list_nilq{a:t0}(xs: list(a)): bool =
( case+ xs of list_nil() => true | list_cons _ => false )
//
(* ****** ****** *)
(* ====================================================================== *)
(*           SOURCE FILTER: only emit for nodes from the top file          *)
(* ====================================================================== *)
//
fun
loc_realq
(loc: loctn): bool = let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  if (pb.nrow() < 0) then false else
  if (pb.ncol() < 0) then false else
  // zero-width / inverted spans are synthetic: skip
  if (pe.ntot() <= pb.ntot()) then false else true
end
//
// extract the on-disk path carried by an lcsrc (the source identity stamped on
// every loctn). Shared by loc_fpath (per-node) and the top-file path capture in
// harvest_d3parsed (which reads d3parsed_get_source — the SAME lcsrc kind).
//
fun
lcsrc_fpath
(src: lcsrc): string =
(
case+ src of
| LCSRCfpath(fp) => fpath_get_fnm1(fp)
| LCSRCsome1(s) => s
| _ => ""
)
//
fun
loc_fpath
(loc: loctn): string = lcsrc_fpath(loc.lsrc())
//
// The harvest walks the WHOLE typed AST of the top file, which inlines the
// nodes of every #include'd / #staload'd source (the compiler stamps each such
// node with ITS OWN source lcsrc + line/col). Emitting a diagnostic / hover /
// semantic-token / definition-use-site for an included-file node and attributing
// it to the CURRENT uri (with the OTHER file's coords) produces phantom rows far
// past EOF. Gate the four per-file emit sites on "this node's source == the top
// file's source". The top path is captured ONCE at the start of harvest_d3parsed
// from d3parsed_get_source (the exact lcsrc the compiler stamped on top nodes),
// so the comparison is an identity match, not a re-normalized path compare.
//
val the_top_path: a0ref(string) = a0ref_make_1val("")
//
fun
loc_in_topfile
(loc: loctn): bool = let
  val top = the_top_path[]
in
  // empty top path: filter disabled (be permissive rather than drop everything).
  if strn_nilq(top) then true else strn_eq(loc_fpath(loc), top)
end
//
fun
push_diag
(loc: loctn, code: string, msg: string): void =
if loc_in_topfile(loc) then let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  diag_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), code, msg)
end
//
(* ****** ****** *)
(* ====================================================================== *)
(*                       CLASSIFIERS (per level)                          *)
(* ====================================================================== *)
//
// At an errck node we look at the WRAPPED node to choose code+message.
//
fun
d1exp_idname_opt
(d1e: d1exp): string = (* "" if not a bare id *)
(
case+ d1exp_get_node(d1e) of
| D1Eid0(sym) => symbl_get_name(sym)
| _ => ""
)
//
fun
classify_d2exp
(loc: loctn, d2e: d2exp): void =
(
case+ d2e.node() of
// unbound identifier: D2Enone1(D1Eid0 name)
| D2Enone1(d1e1) =>
  let
    val nm = d1exp_idname_opt(d1e1)
  in
    if strn_nilq(nm)
    then push_diag(loc, "unbound-identifier", "unbound identifier")
    else push_diag(loc, "unbound-identifier",
                   strn_append("unbound identifier `",
                     strn_append(nm, "`")))
  end
| _ => push_diag(loc, "unknown", "type/elaboration error")
)
//
fun
classify_d2pat
(loc: loctn, d2p: d2pat): void =
  push_diag(loc, "pattern-error", "pattern error")
//
fun
classify_d3exp
(loc: loctn, d3e: d3exp): void =
(
case+ d3e.node() of
// type mismatch: D3Et2pck(expr, expected); actual = expr.styp()
| D3Et2pck(d3e1, t2pexp) =>
  let
    val t2pact = d3e1.styp()
    val sexp = typ_to_strn(t2pexp)
    val sact = typ_to_strn(t2pact)
  in
    push_diag(loc, "type-mismatch",
      strn_append("expected `",
        strn_append(sexp,
          strn_append("`, got `",
            strn_append(sact, "`")))))
  end
| D3Etimp _ =>
  push_diag(loc, "unresolved-template", "unresolved template instantiation")
| D3Etimq _ =>
  push_diag(loc, "unresolved-template", "unresolved template instantiation")
// an L2 error that survived into L3 unchanged: reclassify at L2
| D3Enone1(d2e1) => classify_d2exp(loc, d2e1)
| _ => push_diag(loc, "unknown", "type error")
)
//
fun
classify_d3pat
(loc: loctn, d3p: d3pat): void =
(
case+ d3p.node() of
| D3Pnone1(d2p1) => classify_d2pat(loc, d2p1)
| _ => push_diag(loc, "pattern-error", "pattern error")
)
//
fun
classify_d3ecl
(loc: loctn, dcl: d3ecl): void =
  push_diag(loc, "decl-error", "declaration error")
fun
classify_d2ecl
(loc: loctn, dcl: d2ecl): void =
  push_diag(loc, "decl-error", "declaration error")
//
(* ****** ****** *)
(* ====================================================================== *)
(*               HOVER + DEFINITION emission helpers                       *)
(* ====================================================================== *)
//
fun
emit_hover
(loc: loctn, t2p: s2typ, kind: string): void =
if loc_realq(loc) then
if loc_in_topfile(loc) then let
  val pb = loc.pbeg()
  val pe = loc.pend()
  val ts = typ_pretty(t2p)
in
  // skip empty / pathological type strings
  if strn_nilq(ts) then () else
  hover_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), ts, kind)
end
//
fun
emit_def
(uloc: loctn, dloc: loctn, entity: string, t2p: s2typ): void =
// gate on the USE site only — the def TARGET (dloc) may legitimately live in
// another file (that is go-to-definition); leave dloc unfiltered.
if loc_realq(uloc) then
if loc_in_topfile(uloc) then
( if loc_realq(dloc) then let
    val upb = uloc.pbeg() and upe = uloc.pend()
    val dpb = dloc.pbeg() and dpe = dloc.pend()
    val defpath = loc_fpath(dloc)
  in
    if strn_nilq(defpath) then () else let
      val (hastdef, tdpath, tloc) = typedef_of(t2p)
      val tpb = tloc.pbeg() and tpe = tloc.pend()
    in
      def_push
      ( upb.nrow(), upb.ncol(), upe.nrow(), upe.ncol()
      , defpath
      , dpb.nrow(), dpb.ncol(), dpe.nrow(), dpe.ncol()
      , entity
      , hastdef, tdpath
      , tpb.nrow(), tpb.ncol(), tpe.nrow(), tpe.ncol() )
    end
  end )
//
// resolve a type to its head type-constant's declaration location, if any.
// Returns (1, path, loc) when the head is a T2Pcst with a real location,
// else (0, "", dummy). Peeks through T2Papps / T2Pxtv (fuel-guarded).
//
and
typedef_of
(t2p: s2typ): (int, string, loctn) = typedef_aux(t2p, 6)
//
and
typedef_aux
(t2p: s2typ, fuel: int): (int, string, loctn) =
if (fuel <= 0) then (0, "", loctn_dummy()) else
(
case+ s2typ_get_node(t2p) of
| T2Pcst(s2c) => let
    val cloc = s2cst_get_lctn(s2c)
  in
    if loc_realq(cloc)
    then (1, loc_fpath(cloc), cloc)
    else (0, "", loctn_dummy())
  end
| T2Papps(head, _) => typedef_aux(head, fuel-1)
| T2Pxtv(xv) => typedef_aux(x2t2p_get_styp(xv), fuel-1)
| T2Plft(inner) => typedef_aux(inner, fuel-1)
| T2Ptop0(inner) => typedef_aux(inner, fuel-1)
| T2Ptop1(inner) => typedef_aux(inner, fuel-1)
| T2Pexi0(_, body) => typedef_aux(body, fuel-1)
| T2Puni0(_, body) => typedef_aux(body, fuel-1)
| _ => (0, "", loctn_dummy())
)
//
(* ****** ****** *)
(* ====================================================================== *)
(*            SEMANTIC TOKENS: classification + emission                   *)
(* ====================================================================== *)
//
// token-type indices into the legend advertised in onInitialize. KEEP IN SYNC
// with LSP_TOKEN_TYPES in the resident .cats:
//   namespace=0 type=1 typeParameter=2 parameter=3 variable=4 property=5
//   function=6 enumMember=7 keyword=8 string=9 number=10 operator=11 comment=12
//
#define TT_TYPE          1
#define TT_TYPEPARAM     2
#define TT_VARIABLE      4
#define TT_PROPERTY      5
#define TT_FUNCTION      6
#define TT_ENUMMEMBER    7
//
// token-modifier bits (a bitset). KEEP IN SYNC with LSP_TOKEN_MODS in the .cats:
//   declaration=1 definition=2 readonly=4 static=8 defaultLibrary=16
// `defaultLibrary` is added IN JS (from the def-path's $XATSHOME prefix), so the
// ATS side never sets bit 16 — it passes the def-path and JS ORs it in.
//
#define TM_NONE          0
#define TM_DECLARATION   1
#define TM_DEFINITION    2
//
// emit ONE semantic token for a use-/binding-site node. Guarded on a real
// loctn (skips synthetic/dummy nodes). `defpath` lets JS decide defaultLibrary.
// The checker binds token_push to a no-op, so this whole machinery is inert
// there; the resident binds it to LSP_token_push.
//
fun
emit_token
(loc: loctn, ttype: int, tmods: int, defpath: string): void =
if loc_realq(loc) then
if loc_in_topfile(loc) then let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  // only single-line identifier spans are well-formed semantic tokens; the LSP
  // delta encoding is per-line, and an identifier never spans lines. Skip any
  // multi-line span defensively (keeps the encoder's invariants intact).
  if (pb.nrow() = pe.nrow())
  then token_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), ttype, tmods, defpath)
  else ()
end
//
// a d2cst is a FUNCTION iff its resolved type is a function type (T2Pfun1,
// peeking transparent wrappers via typr_funq from the shared typrint HATS).
// Otherwise it is a plain constant -> variable (we use `variable` rather than
// `property` for a bare value const; `property` is reserved for record fields).
//
fun
cst_ttype
(c: d2cst): int =
  if typr_funq(d2cst_get_styp(c)) then TT_FUNCTION else TT_VARIABLE
//
// emit a token for a dynamic-expression use site (D3Evar/D3Econ/D3Ecst). The
// def-path is the entity's binding-site file, so JS can mark prelude consts
// defaultLibrary. A d2var whose resolved type is a function type is classified
// `function` (a fundcl is given BOTH a d2cst and a same-named d2var for its
// recursive calls — dynexp2.sats — so recursive/forward uses resolve to a var
// that is really a function; keep them `function`).
//
fun
emit_var_token
(loc: loctn, v: d2var, tmods: int): void = let
  val ttype =
    if typr_funq(d2var_get_styp(v)) then TT_FUNCTION else TT_VARIABLE
in
  emit_token(loc, ttype, tmods, loc_fpath(d2var_get_lctn(v)))
end
//
fun
emit_con_token
(loc: loctn, c: d2con): void =
  emit_token(loc, TT_ENUMMEMBER, TM_NONE, loc_fpath(d2con_get_lctn(c)))
//
fun
emit_cst_token
(loc: loctn, c: d2cst): void =
  emit_token(loc, cst_ttype(c), TM_NONE, loc_fpath(d2cst_get_lctn(c)))
//
// emit a DECLARATION token at each fundcl's d2cst decl site (its own loctn),
// classified function/variable by its type. +declaration modifier.
//
fun
emit_cst_fun_decl_tokens
(cs: d2cstlst): void =
( case+ cs of
  | list_nil() => ()
  | list_cons(c, rest) =>
    ( emit_token(d2cst_get_lctn(c), cst_ttype(c), TM_DECLARATION,
                 loc_fpath(d2cst_get_lctn(c)))
    ; emit_cst_fun_decl_tokens(rest) ) )
//
// emit a `type` token at a static-constant's declaration site (datatype name,
// typedef name, stacst, abstype). s2cst carries its own loctn (its decl name);
// def-path = that same file (prelude type names -> defaultLibrary).
//
fun
emit_scst_type_token
(s2c: s2cst): void = let
  val loc = s2cst_get_lctn(s2c)
in
  emit_token(loc, TT_TYPE, TM_DECLARATION, loc_fpath(loc))
end
//
fun
emit_scst_type_tokens
(s2cs: s2cstlst): void =
( case+ s2cs of
  | list_nil() => ()
  | list_cons(s2c, rest) =>
    (emit_scst_type_token(s2c); emit_scst_type_tokens(rest)) )
//
// emit `enumMember` tokens at an exception-constructor declaration site.
//
fun
emit_dcon_enum_tokens
(d2cs: d2conlst): void =
( case+ d2cs of
  | list_nil() => ()
  | list_cons(c, rest) =>
    ( emit_token(d2con_get_lctn(c), TT_ENUMMEMBER, TM_DECLARATION,
                 loc_fpath(d2con_get_lctn(c)))
    ; emit_dcon_enum_tokens(rest) ) )
//
(* ****** ****** *)
(* ====================================================================== *)
(*       DOCUMENT SYMBOLS + INLAY HINTS: emission helpers (WS-5)            *)
(* ====================================================================== *)
//
// LSP SymbolKind indices (subset we map ATS decls onto). KEEP IN SYNC with the
// kinds the .cats serializers pass through unchanged:
//   Class=5 Constructor=9 Enum=10 Interface=11 Function=12 Variable=13
//   Constant=14 EnumMember=22 TypeParameter=26
//
#define SK_CLASS         5
#define SK_CONSTRUCTOR   9
#define SK_ENUM          10
#define SK_INTERFACE     11
#define SK_FUNCTION      12
#define SK_VARIABLE      13
#define SK_CONSTANT      14
#define SK_ENUMMEMBER    22
#define SK_TYPEPARAM     26
//
// LSP InlayHintKind: Type=1, Parameter=2. We emit Type hints on inferred
// val-bindings (": <type>" after the bound name).
//
#define IH_TYPE          1
//
// emit ONE document symbol (gated on the top file, like diagnostics). The range
// IS the name's loctn — selectionRange == range in v1 (a name span trivially
// contains itself; the LSP spec only requires selectionRange ⊆ range).
//
fun
emit_symbol
(loc: loctn, name: string, kind: int, container: string, typ: string): void =
if loc_realq(loc) then
if loc_in_topfile(loc) then let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  if strn_nilq(name) then () else
  symbol_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), name, kind, container, typ)
end
//
// emit an inlay hint ": <type>" at the END of a bound variable's name loctn,
// rendering the variable's inferred type via the shared s2typ pretty-printer
// (the same renderer hover uses). Gated on the top file.
//
fun
emit_inlay_for_var
(loc: loctn, v: d2var): void =
if loc_realq(loc) then
if loc_in_topfile(loc) then let
  val pe = loc.pend()
  val ts = typ_pretty(d2var_get_styp(v))
in
  if strn_nilq(ts) then () else
  inlay_push(pe.nrow(), pe.ncol(), strn_append(": ", ts), IH_TYPE)
end
//
// INLAY pattern walk: for a val-binding pattern, emit a type hint at each bare
// (un-annotated) variable. An explicitly-annotated binding (D3Pannot anywhere on
// the spine) suppresses the hint for that sub-pattern — the type is already
// written. Tuple / record sub-patterns recurse. Used INSIDE the main walk
// (walk_d3valdclist), so a val at any depth (top-level or nested let) gets hints.
//
fun
emit_inlays_for_valpat
(d3p: d3pat): void =
(
case+ d3p.node() of
| D3Pvar(v) => emit_inlay_for_var(d3p.lctn(), v)
| D3Pannot(_, _, _) => ((*explicit type: no hint*))
| D3Ptup0(_, ps) => emit_inlays_for_valpatlst(ps)
| D3Ptup1(_, _, ps) => emit_inlays_for_valpatlst(ps)
| D3Prcd2(_, _, lps) => emit_inlays_for_l3patlst(lps)
| D3Pt2pck(p, _) => emit_inlays_for_valpat(p)
| _ => ((*non-binding leaf*))
)
and
emit_inlays_for_valpatlst
(ps: d3patlst): void =
( case+ ps of
  | list_nil() => ()
  | list_cons(p, ps) =>
    (emit_inlays_for_valpat(p); emit_inlays_for_valpatlst(ps)) )
and
emit_inlays_for_l3patlst
(lps: l3d3plst): void =
( case+ lps of
  | list_nil() => ()
  | list_cons(D3LAB(_, p), lps) =>
    (emit_inlays_for_valpat(p); emit_inlays_for_l3patlst(lps)) )
//
(* ====================================================================== *)
(*   SCOPE-AWARE LOCALS (WS-6 Stage 2): emit each local binder with the     *)
(*   range over which it is VISIBLE (its enclosing body), so completion can *)
(*   offer in-scope locals (ranked above globals). scope_push carries the   *)
(*   visibility range + the binder name + its inferred type.                *)
(* ====================================================================== *)
//
// emit one binder: visibility range (the enclosing body's loctn) + name + type.
fun
emit_scope_var
(v: d2var, visloc: loctn): void =
if loc_realq(visloc) then
if loc_in_topfile(visloc) then let
  val pb = visloc.pbeg()
  val pe = visloc.pend()
  val nm = symbl_get_name(d2var_get_name(v))
in
  if strn_nilq(nm) then () else
  scope_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(),
             nm, typ_pretty(d2var_get_styp(v)))
end
//
// walk a binding pattern, emitting each bound variable with the visibility range.
fun
emit_scope_pat
(d3p: d3pat, visloc: loctn): void =
(
case+ d3p.node() of
| D3Pvar(v) => emit_scope_var(v, visloc)
| D3Pannot(p, _, _) => emit_scope_pat(p, visloc)
| D3Ptup0(_, ps) => emit_scope_patlst(ps, visloc)
| D3Ptup1(_, _, ps) => emit_scope_patlst(ps, visloc)
| D3Prcd2(_, _, lps) => emit_scope_l3patlst(lps, visloc)
| D3Pt2pck(p, _) => emit_scope_pat(p, visloc)
| _ => ()
)
and
emit_scope_patlst
(ps: d3patlst, visloc: loctn): void =
( case+ ps of
  | list_nil() => ()
  | list_cons(p, ps) => (emit_scope_pat(p, visloc); emit_scope_patlst(ps, visloc)) )
and
emit_scope_l3patlst
(lps: l3d3plst, visloc: loctn): void =
( case+ lps of
  | list_nil() => ()
  | list_cons(D3LAB(_, p), lps) =>
    (emit_scope_pat(p, visloc); emit_scope_l3patlst(lps, visloc)) )
//
// lambda / fix PARAMS are visible in the body: emit each f3arg's patterns.
fun
emit_scope_farg
(farg: f3arglst, visloc: loctn): void =
( case+ farg of
  | list_nil() => ()
  | list_cons(a, farg) =>
    ( ( case+ a.node() of
        | F3ARGdapp(_, ps) => emit_scope_patlst(ps, visloc)
        | _ => ((*static / metric args*)) )
    ; emit_scope_farg(farg, visloc) ) )
//
// LET val-binders are visible in the body: emit each valdcl pattern's binders.
fun
emit_scope_dcls
(dcls: d3eclist, visloc: loctn): void =
( case+ dcls of
  | list_nil() => ()
  | list_cons(d, dcls) =>
    ( ( case+ d.node() of
        | D3Cvaldclst(_, dvs) => emit_scope_valdcls(dvs, visloc)
        | _ => () )
    ; emit_scope_dcls(dcls, visloc) ) )
and
emit_scope_valdcls
(dvs: d3valdclist, visloc: loctn): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    (emit_scope_pat(d3valdcl_get_dpat(dv), visloc); emit_scope_valdcls(dvs, visloc)) )
//
// D2-LEVEL params: when a function body is a half-typed/unbound partial (the real
// live-completion case), trans23 drops the fundcl from the d3 tree but it survives
// at d2 (reached via D3Cnone1 -> walk_d2ecl -> D2Cfundclst). So we also emit a
// `fun`'s params from the d2 fundcl, with the fundcl's loctn as the visibility.
fun
emit_scope_d2pat
(d2p: d2pat, visloc: loctn): void =
(
case+ d2p.node() of
| D2Pvar(v) => emit_scope_var(v, visloc)
| D2Pannot(p, _, _) => emit_scope_d2pat(p, visloc)
| D2Ptup0(_, ps) => emit_scope_d2patlst(ps, visloc)
| D2Ptup1(_, _, ps) => emit_scope_d2patlst(ps, visloc)
| D2Pt2pck(p, _) => emit_scope_d2pat(p, visloc)
| _ => ()
)
and
emit_scope_d2patlst
(ps: d2patlst, visloc: loctn): void =
( case+ ps of
  | list_nil() => ()
  | list_cons(p, ps) => (emit_scope_d2pat(p, visloc); emit_scope_d2patlst(ps, visloc)) )
//
fun
emit_scope_f2arg
(farg: f2arglst, visloc: loctn): void =
( case+ farg of
  | list_nil() => ()
  | list_cons(a, farg) =>
    ( ( case+ a.node() of
        | F2ARGdapp(_, ps) => emit_scope_d2patlst(ps, visloc)
        | _ => ((*static / metric args*)) )
    ; emit_scope_f2arg(farg, visloc) ) )
//
(* ====================================================================== *)
(*   MEMBER COMPLETION (WS-6 Stage 3): record fields of a receiver's type   *)
(* ====================================================================== *)
//
// For each record-typed expression node, emit its FIELDS keyed by the node's
// range (the receiver span). Completion at `recv.partial` finds the entry whose
// receiver range ends at the `.` and offers its fields. Record fields are NOT
// global names, so this is genuinely-semantic completion. (T2Ptrcd is both
// tuples and records; we emit NAMED fields — LABsym — and skip positional ones.)
//
fun
emit_members_aux
(loc: loctn, t2p: s2typ, fuel: int): void =
if (fuel <= 0) then () else
(
case+ s2typ_get_node(t2p) of
| T2Ptrcd(_, _, ltps) => emit_member_ltps(loc, ltps)
| T2Papps(head, _) => emit_members_aux(loc, head, fuel-1)
| T2Pxtv(xv) => emit_members_aux(loc, x2t2p_get_styp(xv), fuel-1)
| T2Plft(t) => emit_members_aux(loc, t, fuel-1)
| T2Ptop0(t) => emit_members_aux(loc, t, fuel-1)
| T2Ptop1(t) => emit_members_aux(loc, t, fuel-1)
| T2Pexi0(_, t) => emit_members_aux(loc, t, fuel-1)
| T2Puni0(_, t) => emit_members_aux(loc, t, fuel-1)
| _ => ()
)
and
emit_member_ltps
(loc: loctn, ltps: l2t2plst): void =
( case+ ltps of
  | list_nil() => ()
  | list_cons(ltp, ltps) => (emit_member_one(loc, ltp); emit_member_ltps(loc, ltps)) )
and
emit_member_one
(loc: loctn, ltp: l2t2p): void = let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  case+ ltp of
  | S2LAB(lab, t) =>
    ( case+ lab of
      | LABsym(sym) =>
        let val nm = symbl_get_name(sym) in
          if strn_nilq(nm) then () else
          member_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), nm, typ_pretty(t))
        end
      | _ => ((*LABint: positional field, skip in v1*)) )
end
//
fun
emit_members
(loc: loctn, t2p: s2typ): void =
if loc_realq(loc) then
if loc_in_topfile(loc) then emit_members_aux(loc, t2p, 6)
//
(* ****** ****** *)
(* ====================================================================== *)
(*       THE TRAVERSAL (find all errck; emit hover/def/token)              *)
(* ====================================================================== *)
//
// Mutually-recursive walk over the d3 family (and the d2 family it embeds via
// D3Cnone1/D3Enone1/D3Pnone1). At each `…errck` we classify (above) AND keep
// descending. Each typed d3exp/d3pat emits a hover; each D3Evar/D3Ecst/D3Econ
// use site emits a definition + a semantic token; declaration sites (fundcl
// d2csts, datatype/typedef/stacst/abstype s2csts, exception d2cons) emit decl
// tokens. The four sinks (diag/hover/def/token) are abstract per consumer.
//
fun
walk_d3exp (d3e0: d3exp): void = let
//
// HOVER: every expression node carries its type.
val () = emit_hover(d3e0.lctn(), d3e0.styp(), "expr")
// MEMBERS: if this node has a record type, emit its fields (keyed by its range)
// so `node.field` completion can offer them.
val () = emit_members(d3e0.lctn(), d3e0.styp())
//
in
(
case+ d3e0.node() of
//
| D3Eerrck(lvl, d3e1) =>
  ( walk_d3exp(d3e1)
  ; if (lvl < 3) then classify_d3exp(d3e0.lctn(), d3e1) )
//
// DEFINITION use sites: the embedded entity object carries its own binding-site
// location; type-def comes from the node's styp() head. Also a semantic token.
| D3Evar(v) =>
( emit_def(d3e0.lctn(), d2var_get_lctn(v), "var", d3e0.styp())
; emit_var_token(d3e0.lctn(), v, TM_NONE) )
| D3Econ(c) =>
( emit_def(d3e0.lctn(), d2con_get_lctn(c), "con", d3e0.styp())
; emit_con_token(d3e0.lctn(), c) )
| D3Ecst(c) =>
( emit_def(d3e0.lctn(), d2cst_get_lctn(c), "cst", d3e0.styp())
; emit_cst_token(d3e0.lctn(), c) )
//
| D3Et2pck(d3e1, _) => walk_d3exp(d3e1)
| D3Et2ped(d3e1, _) => walk_d3exp(d3e1)
| D3Elabck(d3e1, _) => walk_d3exp(d3e1)
| D3Eannot(d3e1, _, _) => walk_d3exp(d3e1)
//
| D3Etimp(d3f0, _) => walk_d3exp(d3f0)
| D3Etimq(d3f0, _, _) => walk_d3exp(d3f0)
| D3Esapp(d3f0, _) => walk_d3exp(d3f0)
| D3Esapq(d3f0, _) => walk_d3exp(d3f0)
| D3Etapp(d3f0, _) => walk_d3exp(d3f0)
| D3Etapq(d3f0, _) => walk_d3exp(d3f0)
| D3Edap0(d3f0) => walk_d3exp(d3f0)
| D3Edapp(d3f0, _, d3es) => (walk_d3exp(d3f0); walk_d3explst(d3es))
//
| D3Epcon(_, _, d3e1) => walk_d3exp(d3e1)
| D3Eproj(_, _, d3e1) => walk_d3exp(d3e1)
//
| D3Elet0(dcls, d3e1) =>
  ( emit_scope_dcls(dcls, d3e1.lctn())   // let-binders visible in the body
  ; walk_d3eclist(dcls); walk_d3exp(d3e1) )
| D3Eift0(d3e1, dthn, dels) =>
  (walk_d3exp(d3e1); walk_d3expopt(dthn); walk_d3expopt(dels))
| D3Ecas0(_, d3e1, dcls) => (walk_d3exp(d3e1); walk_d3clslst(dcls))
| D3Eseqn(d3es, d3e1) => (walk_d3explst(d3es); walk_d3exp(d3e1))
//
| D3Etup0(_, d3es) => walk_d3explst(d3es)
| D3Etup1(_, _, d3es) => walk_d3explst(d3es)
| D3Ercd2(_, _, ld3es) => walk_l3d3elst(ld3es)
//
| D3Elam0(_, farg, _, _, d3e1) =>
  ( emit_scope_farg(farg, d3e1.lctn())   // lambda params visible in the body
  ; walk_f3arglst(farg); walk_d3exp(d3e1) )
| D3Efix0(_, _, farg, _, _, d3e1) =>
  ( emit_scope_farg(farg, d3e1.lctn())   // fix params visible in the body
  ; walk_f3arglst(farg); walk_d3exp(d3e1) )
| D3Etry0(_, d3e1, dcls) => (walk_d3exp(d3e1); walk_d3clslst(dcls))
//
| D3Eaddr(d3e1) => walk_d3exp(d3e1)
| D3Eview(d3e1) => walk_d3exp(d3e1)
| D3Eflat(d3e1) => walk_d3exp(d3e1)
| D3Elval(d3e1) => walk_d3exp(d3e1)
| D3Eeval(d3e1) => walk_d3exp(d3e1)
| D3Efold(d3e1) => walk_d3exp(d3e1)
| D3Efree(d3e1) => walk_d3exp(d3e1)
| D3Edelaz(d3e1) => walk_d3exp(d3e1)
| D3Edp2tr(d3e1) => walk_d3exp(d3e1)
| D3Edl0az(d3e1) => walk_d3exp(d3e1)
| D3Edl1az(d3e1) => walk_d3exp(d3e1)
//
| D3Ewhere(d3e1, dcls) => (walk_d3exp(d3e1); walk_d3eclist(dcls))
| D3Eassgn(dl, dr) => (walk_d3exp(dl); walk_d3exp(dr))
| D3Exazgn(dl, dr) => (walk_d3exp(dl); walk_d3exp(dr))
| D3Exchng(dl, dr) => (walk_d3exp(dl); walk_d3exp(dr))
| D3Eraise(_, d3e1) => walk_d3exp(d3e1)
| D3Eexists(_, d3e1) => walk_d3exp(d3e1)
//
| D3El0azy(_, d3e1) => walk_d3exp(d3e1)
| D3El1azy(_, d3e1, d3es) => (walk_d3exp(d3e1); walk_d3explst(d3es))
| D3Eelazy(_, d3e1, d3es) => (walk_d3exp(d3e1); walk_d3explst(d3es))
//
| D3Enone1(d2e1) => walk_d2exp(d2e1)
| D3Enone2(d3e1) => walk_d3exp(d3e1)
//
| _ => ((*leaf*))
) end
//
and
walk_d3pat (d3p0: d3pat): void = let
//
// HOVER: every pattern node carries its type too.
val () = emit_hover(d3p0.lctn(), d3p0.styp(), "pat")
//
in
(
case+ d3p0.node() of
| D3Perrck(lvl, d3p1) =>
  ( walk_d3pat(d3p1)
  ; if (lvl < 3) then classify_d3pat(d3p0.lctn(), d3p1) )
// pattern variable: a BINDING site -> variable + declaration.
| D3Pvar(v) => emit_var_token(d3p0.lctn(), v, TM_DECLARATION)
// constructor pattern (nullary): a USE of the data constructor -> enumMember.
| D3Pcon(c) => emit_con_token(d3p0.lctn(), c)
| D3Pbang(p) => walk_d3pat(p)
| D3Pflat(p) => walk_d3pat(p)
| D3Pfree(p) => walk_d3pat(p)
| D3Pdap1(p) => walk_d3pat(p)
| D3Pdapp(f, _, ps) => (walk_d3pat(f); walk_d3patlst(ps))
| D3Prfpt(p1, _, p2) => (walk_d3pat(p1); walk_d3pat(p2))
| D3Pargtp(p1, _) => walk_d3pat(p1)
| D3Pannot(p1, _, _) => walk_d3pat(p1)
| D3Pt2pck(p1, _) => walk_d3pat(p1)
| D3Ptup0(_, ps) => walk_d3patlst(ps)
| D3Ptup1(_, _, ps) => walk_d3patlst(ps)
| D3Prcd2(_, _, lps) => walk_l3d3plst(lps)
| D3Psapp(p, _) => walk_d3pat(p)
| D3Psapq(p, _) => walk_d3pat(p)
| D3Ptapq(p, _) => walk_d3pat(p)
| D3Pnone1(d2p1) => walk_d2pat(d2p1)
| D3Pnone2(d3p1) => walk_d3pat(d3p1)
| _ => ((*leaf*))
) end
//
and
walk_d3ecl (dcl0: d3ecl): void =
(
case+ dcl0.node() of
| D3Cerrck(lvl, dcl1) =>
  ( walk_d3ecl(dcl1)
  ; if (lvl < 3) then classify_d3ecl(dcl0.lctn(), dcl1) )
// L2-only decls (datatypes, typedefs, stacst, abstype, exception cons) are
// wrapped here; descend so their static-constant names get `type` tokens.
| D3Cd2ecl(d2cl) => walk_d2ecl(d2cl)
| D3Cstatic(_, dcl1) => walk_d3ecl(dcl1)
| D3Cextern(_, dcl1) => walk_d3ecl(dcl1)
| D3Ctmpsub(_, dcl1) => walk_d3ecl(dcl1)
| D3Cdclst0(dcls) => walk_d3eclist(dcls)
| D3Clocal0(da, db) => (walk_d3eclist(da); walk_d3eclist(db))
| D3Cinclude(_, _, _, _, dopt) => walk_d3eclistopt(dopt)
| D3Cvaldclst(_, dvs) => walk_d3valdclist(dvs)
| D3Cvardclst(_, dvs) => walk_d3vardclist(dvs)
| D3Cfundclst(_, _, dcsts, dfs) =>
  (emit_cst_fun_decl_tokens(dcsts); walk_d3fundclist(dfs))
| D3Cimplmnt0(_, _, _, _, _, _, _, _, dexp) => walk_d3exp(dexp)
| D3Cnone1(d2cl) => walk_d2ecl(d2cl)
| D3Cnone2(d3cl) => walk_d3ecl(d3cl)
| _ => ((*leaf*))
)
//
and
walk_d2exp (d2e0: d2exp): void =
(
case+ d2e0.node() of
| D2Eerrck(lvl, d2e1) =>
  ( walk_d2exp(d2e1)
  ; if (lvl < 3) then classify_d2exp(d2e0.lctn(), d2e1) )
| D2Et2pck(d2e1, _) => walk_d2exp(d2e1)
| D2Et2ped(d2e1, _) => walk_d2exp(d2e1)
| D2Elabck(d2e1, _) => walk_d2exp(d2e1)
| D2Eannot(d2e1, _, _) => walk_d2exp(d2e1)
| D2Esapp(d2f0, _) => walk_d2exp(d2f0)
| D2Etapp(d2f0, _) => walk_d2exp(d2f0)
| D2Edap0(d2f0) => walk_d2exp(d2f0)
| D2Edapp(d2f0, _, d2es) => (walk_d2exp(d2f0); walk_d2explst(d2es))
| D2Eproj(_, _, _, d2e1) => walk_d2exp(d2e1)
| D2Elet0(dcls, d2e1) => (walk_d2eclist(dcls); walk_d2exp(d2e1))
| D2Eift0(d2e1, dthn, dels) =>
  (walk_d2exp(d2e1); walk_d2expopt(dthn); walk_d2expopt(dels))
| D2Eseqn(d2es, d2e1) => (walk_d2explst(d2es); walk_d2exp(d2e1))
| D2Etup0(_, d2es) => walk_d2explst(d2es)
| D2Etup1(_, _, d2es) => walk_d2explst(d2es)
| D2Elam0(_, _, _, _, d2e1) => walk_d2exp(d2e1)
| D2Efix0(_, _, _, _, _, d2e1) => walk_d2exp(d2e1)
| D2Eaddr(d2e1) => walk_d2exp(d2e1)
| D2Eview(d2e1) => walk_d2exp(d2e1)
| D2Elval(d2e1) => walk_d2exp(d2e1)
| D2Eeval(d2e1) => walk_d2exp(d2e1)
| D2Efold(d2e1) => walk_d2exp(d2e1)
| D2Efree(d2e1) => walk_d2exp(d2e1)
| D2Ewhere(d2e1, dcls) => (walk_d2exp(d2e1); walk_d2eclist(dcls))
| D2Eassgn(dl, dr) => (walk_d2exp(dl); walk_d2exp(dr))
| D2Exazgn(dl, dr) => (walk_d2exp(dl); walk_d2exp(dr))
| D2Exchng(dl, dr) => (walk_d2exp(dl); walk_d2exp(dr))
| D2Eraise(_, d2e1) => walk_d2exp(d2e1)
| D2El0azy(_, d2e1) => walk_d2exp(d2e1)
| D2El1azy(_, d2e1, d2es) => (walk_d2exp(d2e1); walk_d2explst(d2es))
| D2Eelazy(_, d2e1, d2es) => (walk_d2exp(d2e1); walk_d2explst(d2es))
| D2Enone2(d2e1) => walk_d2exp(d2e1)
| _ => ((*leaf or D2Enone1(d1exp): classified at the errck above*))
)
//
and
walk_d2pat (d2p0: d2pat): void =
(
case+ d2p0.node() of
| D2Perrck(lvl, d2p1) =>
  ( walk_d2pat(d2p1)
  ; if (lvl < 3) then classify_d2pat(d2p0.lctn(), d2p1) )
| D2Pbang(p) => walk_d2pat(p)
| D2Pflat(p) => walk_d2pat(p)
| D2Pfree(p) => walk_d2pat(p)
| D2Pdap1(p) => walk_d2pat(p)
| D2Pdapp(f, _, ps) => (walk_d2pat(f); walk_d2patlst(ps))
| D2Pannot(p1, _, _) => walk_d2pat(p1)
| D2Pargtp(p1, _) => walk_d2pat(p1)
| D2Pnone2(d2p1) => walk_d2pat(d2p1)
| _ => ((*leaf*))
)
//
and
walk_d2ecl (dcl0: d2ecl): void =
(
case+ dcl0.node() of
| D2Cerrck(lvl, dcl1) =>
  ( walk_d2ecl(dcl1)
  ; if (lvl < 3) then classify_d2ecl(dcl0.lctn(), dcl1) )
| D2Cstatic(_, dcl1) => walk_d2ecl(dcl1)
| D2Cextern(_, dcl1) => walk_d2ecl(dcl1)
| D2Clocal0(da, db) => (walk_d2eclist(da); walk_d2eclist(db))
| D2Cvaldclst(_, dvs) => walk_d2valdclist(dvs)
| D2Cvardclst(_, dvs) => walk_d2vardclist(dvs)
| D2Cfundclst(_, _, _, dfs) => walk_d2fundclist(dfs)
| D2Cimplmnt0(_, _, _, _, _, _, _, dexp) => walk_d2exp(dexp)
// static-constant DECLARATION sites -> a `type` token at the s2cst loctn.
| D2Cdatatype(_, s2cs) => emit_scst_type_tokens(s2cs)
| D2Csexpdef(s2c, _) => emit_scst_type_token(s2c)
| D2Cstacst0(s2c, _) => emit_scst_type_token(s2c)
| D2Cabstype(s2c, _) => emit_scst_type_token(s2c)
// exception constructors -> enumMember tokens at each d2con's decl loctn.
| D2Cexcptcon(_, d2cs) => emit_dcon_enum_tokens(d2cs)
| D2Cnone2(d2cl) => walk_d2ecl(d2cl)
| _ => ((*leaf*))
)
//
and
walk_d3explst (xs: d3explst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d3exp(x); walk_d3explst(xs)) )
and
walk_d3expopt (xo: d3expopt): void =
( case+ xo of optn_nil() => () | optn_cons(x) => walk_d3exp(x) )
and
walk_d3patlst (xs: d3patlst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d3pat(x); walk_d3patlst(xs)) )
and
walk_d3eclist (xs: d3eclist): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d3ecl(x); walk_d3eclist(xs)) )
and
walk_d3eclistopt (xo: d3eclistopt): void =
( case+ xo of optn_nil() => () | optn_cons(xs) => walk_d3eclist(xs) )
and
walk_l3d3elst (xs: l3d3elst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(D3LAB(_, x), xs) => (walk_d3exp(x); walk_l3d3elst(xs)) )
and
walk_l3d3plst (xs: l3d3plst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(D3LAB(_, x), xs) => (walk_d3pat(x); walk_l3d3plst(xs)) )
and
walk_f3arglst (xs: f3arglst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(a, xs) =>
    ( ( case+ a.node() of
        | F3ARGdapp(_, ps) => walk_d3patlst(ps)
        | _ => ((*static / metric args*)) )
    ; walk_f3arglst(xs) ) )
and
walk_d3clslst (xs: d3clslst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(c, xs) =>
    ( ( case+ c.node() of
        | D3CLSgpt(g) => walk_d3gpt(g)
        | D3CLScls(g, e) => (walk_d3gpt(g); walk_d3exp(e)) )
    ; walk_d3clslst(xs) ) )
and
walk_d3gpt (g: d3gpt): void =
( case+ g.node() of
  | D3GPTpat(p) => walk_d3pat(p)
  | D3GPTgua(p, gs) => (walk_d3pat(p); walk_d3gualst(gs)) )
and
walk_d3gualst (gs: d3gualst): void =
( case+ gs of
  | list_nil() => ()
  | list_cons(gg, gs) =>
    ( ( case+ gg.node() of
        | D3GUAexp(e) => walk_d3exp(e)
        | D3GUAmat(e, p) => (walk_d3exp(e); walk_d3pat(p)) )
    ; walk_d3gualst(gs) ) )
and
walk_teqd3exp (t: teqd3exp): void =
( case+ t of
  | TEQD3EXPnone() => ()
  | TEQD3EXPsome(_, e) => walk_d3exp(e) )
and
walk_d3valdclist (dvs: d3valdclist): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( emit_inlays_for_valpat(d3valdcl_get_dpat(dv))
    ; walk_d3pat(d3valdcl_get_dpat(dv))
    ; walk_teqd3exp(d3valdcl_get_tdxp(dv))
    ; walk_d3valdclist(dvs) ) )
and
walk_d3vardclist (dvs: d3vardclist): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_teqd3exp(d3vardcl_get_dini(dv))
    ; walk_d3vardclist(dvs) ) )
and
walk_d3fundclist (dfs: d3fundclist): void =
( case+ dfs of
  | list_nil() => ()
  | list_cons(df, dfs) =>
    ( // SCOPE: a `fun`'s params live on the fundcl (NOT a lambda in the body).
      // Use the fundcl's OWN loctn as the visibility range: it spans the whole
      // declaration (params + body), so params are still offered while the body is
      // a half-typed/unbound partial — the real live-completion case (the body's
      // own loctn is unreliable once the body errors).
      emit_scope_farg(d3fundcl_get_farg(df), d3fundcl_get_lctn(df))
    ; walk_teqd3exp(d3fundcl_get_tdxp(df))
    ; walk_d3fundclist(dfs) ) )
and
walk_d2explst (xs: d2explst): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d2exp(x); walk_d2explst(xs)) )
and
walk_d2expopt (xo: d2expopt): void =
( case+ xo of optn_nil() => () | optn_cons(x) => walk_d2exp(x) )
and
walk_d2patlst (ps: d2patlst): void =
( case+ ps of
  | list_nil() => ()
  | list_cons(p, ps) => (walk_d2pat(p); walk_d2patlst(ps)) )
and
walk_d2eclist (xs: d2eclist): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d2ecl(x); walk_d2eclist(xs)) )
and
walk_d2eclistopt (xo: d2eclistopt): void =
( case+ xo of optn_nil() => () | optn_cons(xs) => walk_d2eclist(xs) )
and
walk_teqd2exp (t: teqd2exp): void =
( case+ t of
  | TEQD2EXPnone() => ()
  | TEQD2EXPsome(_, e) => walk_d2exp(e) )
and
walk_d2valdclist (dvs: d2valdclist): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_d2pat(d2valdcl_get_dpat(dv))
    ; walk_teqd2exp(d2valdcl_get_tdxp(dv))
    ; walk_d2valdclist(dvs) ) )
and
walk_d2vardclist (dvs: d2vardclist): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_teqd2exp(d2vardcl_get_dini(dv))
    ; walk_d2vardclist(dvs) ) )
and
walk_d2fundclist (dfs: d2fundclist): void =
( case+ dfs of
  | list_nil() => ()
  | list_cons(df, dfs) =>
    ( emit_scope_f2arg(d2fundcl_get_farg(df), d2fundcl_get_lctn(df))  // d2 params
    ; walk_teqd2exp(d2fundcl_get_tdxp(df))
    ; walk_d2fundclist(dfs) ) )
//
(* ****** ****** *)
(* ====================================================================== *)
(*   DOCUMENT SYMBOLS: a TOP-LEVEL-ONLY decl pass (outline)                *)
(* ====================================================================== *)
//
// Separate from the main walk: it descends ONLY structural decl groupings
// (static/extern/local/include/dclst) — never into expression bodies — so the
// outline lists top-level (and local-block) declarations, not let-bound locals
// inside function bodies. Each emitter is gated on the top file (emit_symbol).
//
fun
emit_symbol_scst1
(s2c: s2cst, kind: int): void =
  // a static-type constant (datatype/typedef/abstype): no value-type to show.
  emit_symbol(s2cst_get_lctn(s2c), symbl_get_name(s2cst_get_name(s2c)), kind, "", "")
//
fun
emit_symbol_funs
(cs: d2cstlst): void =
( case+ cs of
  | list_nil() => ()
  | list_cons(c, rest) =>
    ( emit_symbol(d2cst_get_lctn(c),
                  symbl_get_name(d2cst_get_name(c)), SK_FUNCTION, "",
                  typ_pretty(d2cst_get_styp(c)))
    ; emit_symbol_funs(rest) ) )
//
fun
emit_symbol_dcons
(d2cs: d2conlst, kind: int, container: string): void =
( case+ d2cs of
  | list_nil() => ()
  | list_cons(c, rest) =>
    ( emit_symbol(d2con_get_lctn(c),
                  symbl_get_name(d2con_get_name(c)), kind, container,
                  typ_pretty(d2con_get_styp(c)))
    ; emit_symbol_dcons(rest, kind, container) ) )
//
fun
emit_symbol_scsts
(s2cs: s2cstlst, kind: int): void =
( case+ s2cs of
  | list_nil() => ()
  | list_cons(s2c, rest) =>
    (emit_symbol_scst1(s2c, kind); emit_symbol_scsts(rest, kind)) )
//
// a val-binding pattern -> a Constant symbol per bound variable.
//
fun
emit_symbols_for_valpat
(d3p: d3pat): void =
(
case+ d3p.node() of
| D3Pvar(v) =>
  emit_symbol(d3p.lctn(), symbl_get_name(d2var_get_name(v)), SK_CONSTANT, "",
              typ_pretty(d2var_get_styp(v)))
| D3Pannot(p, _, _) => emit_symbols_for_valpat(p)
| D3Ptup0(_, ps) => emit_symbols_for_valpatlst(ps)
| D3Ptup1(_, _, ps) => emit_symbols_for_valpatlst(ps)
| D3Prcd2(_, _, lps) => emit_symbols_for_l3patlst(lps)
| D3Pt2pck(p, _) => emit_symbols_for_valpat(p)
| _ => ()
)
and
emit_symbols_for_valpatlst
(ps: d3patlst): void =
( case+ ps of
  | list_nil() => ()
  | list_cons(p, ps) =>
    (emit_symbols_for_valpat(p); emit_symbols_for_valpatlst(ps)) )
and
emit_symbols_for_l3patlst
(lps: l3d3plst): void =
( case+ lps of
  | list_nil() => ()
  | list_cons(D3LAB(_, p), lps) =>
    (emit_symbols_for_valpat(p); emit_symbols_for_l3patlst(lps)) )
//
fun
emit_symbols_d3valdclist
(dvs: d3valdclist): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( emit_symbols_for_valpat(d3valdcl_get_dpat(dv))
    ; emit_symbols_d3valdclist(dvs) ) )
//
fun
emit_symbols_d3ecl
(dcl0: d3ecl): void =
(
case+ dcl0.node() of
| D3Cerrck(_, dcl1) => emit_symbols_d3ecl(dcl1)
| D3Cfundclst(_, _, dcsts, _) => emit_symbol_funs(dcsts)
| D3Cvaldclst(_, dvs) => emit_symbols_d3valdclist(dvs)
| D3Cstatic(_, dcl1) => emit_symbols_d3ecl(dcl1)
| D3Cextern(_, dcl1) => emit_symbols_d3ecl(dcl1)
| D3Ctmpsub(_, dcl1) => emit_symbols_d3ecl(dcl1)
| D3Cdclst0(dcls) => emit_symbols_d3eclist(dcls)
| D3Clocal0(da, db) => (emit_symbols_d3eclist(da); emit_symbols_d3eclist(db))
| D3Cinclude(_, _, _, _, dopt) => emit_symbols_d3eclistopt(dopt)
| D3Cd2ecl(d2cl) => emit_symbols_d2ecl(d2cl)
| D3Cnone1(d2cl) => emit_symbols_d2ecl(d2cl)
| D3Cnone2(d3cl) => emit_symbols_d3ecl(d3cl)
| _ => ()
)
and
emit_symbols_d3eclist
(xs: d3eclist): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (emit_symbols_d3ecl(x); emit_symbols_d3eclist(xs)) )
and
emit_symbols_d3eclistopt
(xo: d3eclistopt): void =
( case+ xo of optn_nil() => () | optn_cons(xs) => emit_symbols_d3eclist(xs) )
and
emit_symbols_d2ecl
(dcl0: d2ecl): void =
(
case+ dcl0.node() of
| D2Cerrck(_, dcl1) => emit_symbols_d2ecl(dcl1)
| D2Cstatic(_, dcl1) => emit_symbols_d2ecl(dcl1)
| D2Cextern(_, dcl1) => emit_symbols_d2ecl(dcl1)
| D2Clocal0(da, db) => (emit_symbols_d2eclist(da); emit_symbols_d2eclist(db))
// static-type declarations -> type-flavored symbols.
| D2Cdatatype(_, s2cs) => emit_symbol_scsts(s2cs, SK_ENUM)
| D2Csexpdef(s2c, _) => emit_symbol_scst1(s2c, SK_INTERFACE)
| D2Cstacst0(s2c, _) => emit_symbol_scst1(s2c, SK_TYPEPARAM)
| D2Cabstype(s2c, _) => emit_symbol_scst1(s2c, SK_CLASS)
// exception constructors -> EnumMember symbols.
| D2Cexcptcon(_, d2cs) => emit_symbol_dcons(d2cs, SK_ENUMMEMBER, "")
| D2Cnone2(d2cl) => emit_symbols_d2ecl(d2cl)
| _ => ()
)
and
emit_symbols_d2eclist
(xs: d2eclist): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (emit_symbols_d2ecl(x); emit_symbols_d2eclist(xs)) )
//
(* ****** ****** *)
(* ====================================================================== *)
(*   harvest_d3parsed: set top-path; walk; reset  (the shared payload)     *)
(* ====================================================================== *)
//
// SOURCE FILTER: capture the top file's source path from the SAME lcsrc the
// compiler stamped on its own nodes (d3parsed_get_source), so the per-node
// loc_in_topfile guard is an identity match. This drops phantom emissions
// attributed to included/staloaded sources (the include-leak bug). Reset after
// the walk so a stale path never leaks into a later, unguarded call.
//
// This is the UNIVERSALLY-SHARED post-check work. A consumer needing extra work
// from the same checked parse (the resident's dependency extraction + signature
// stamping) does it AROUND this call, not inside it.
//
fun
harvest_d3parsed
(dpar: d3parsed): void = let
  val () = the_top_path[] := lcsrc_fpath(d3parsed_get_source(dpar))
  val parsed = d3parsed_get_parsed(dpar)
  // the main walk: diagnostics (errck), hover, definitions, semantic tokens,
  // and inlay hints (val-binding type hints, emitted at every depth).
  val () = walk_d3eclistopt(parsed)
  // the top-level-only outline pass (document symbols).
  val () = emit_symbols_d3eclistopt(parsed)
  // clear the top-path filter (defensive: keep no stale source between checks).
  val () = the_top_path[] := ""
in (*nothing*) end
//
(* ****** ****** *)
(* end of [xats_lsp_harvest.hats] *)
(* ****** ****** *)
