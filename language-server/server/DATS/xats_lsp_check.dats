(* ****** ****** *)
(*
WS-1a — LSP diagnostics checker (Stages 2+3).

A "compiler-linking" driver: it #include's the compiler headers and calls
the front-end (d3parsed_of_fil{sats,dats}); built by linking against the
compiled compiler srcgen2/lib/lib2xatsopt.js (see build.sh).

Instead of the stock f3perr0_d3parsed text report, it runs a NEW traversal
(modeled structurally on srcgen2/DATS/f3perr0_dynexp.dats + f3perr0_decl00
+ f2perr0_dynexp) that, at each `…errck` node, READS the wrapped node's
internal 0-based location (loc.pbeg().nrow()/.ncol(), loc.pend()...) and
CLASSIFIES the error into a §4.1 `code` + a human message, then pushes it
to a JS-side accumulator (LSPCHK_diag_push). The JS side (xats_lsp_check.cats)
dedups per Decision D6 and serializes the §4 JSON bundle to --json-out.

Primer anchors: §3 (front-end API), §5 (0-based internal coords via
accessors), §6 (errck nodes / codes / dedup), §9 (traversal template).
*)
(* ****** ****** *)
#include
"./../../../srcgen2/HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../../../srcgen2/HATS/xatsopt_sats.hats"
#include
"./../../../srcgen2/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
//
// libxatsopt.hats already #staload's dynexp2/dynexp3/staexp2/statyp2/xsymbol,
// and each of those SATS carries its own `#symload node/lctn/styp/name` — so
// the dot-notation for d2*/d3*/s2cst/symbl is already in scope. We add the
// three SATS that libxatsopt does NOT staload but we need, exactly as the
// stock reporter files (f2perr0_dynexp.dats / dynexp1_print0.dats) do:
//   locinfo  -> postn/loctn accessors (pbeg/pend/ntot/nrow/ncol)
//   lexing0  -> token accessors
//   dynexp1  -> bare D1Eid0 + d1exp.node()
//
#staload "./../../../srcgen2/SATS/locinfo.sats"
#staload "./../../../srcgen2/SATS/lexing0.sats"
#staload "./../../../srcgen2/SATS/dynexp1.sats"
//
// filpath -> fpath_get_fnm1 (the file path inside a LCSRCfpath source). The
// go-to-def path mapping (primer §8) reads lctn.lsrc() -> fpath -> fnm1.
#staload "./../../../srcgen2/SATS/filpath.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
// ---------------- FFI declarations (impl in the .cats) ----------------
//
#if
defq(_XATS2JS_)
#typedef argv=jsa1sz(strn)
#endif
//
#extern fun
XATSOPT_argv$get((*0*)): argv = $extnam()
//
#extern fun
LSPCHK_argv_count((*0*)): sint = $extnam()
#extern fun
LSPCHK_argv_get(i0: sint): strn = $extnam()
//
// string-buffer FILR (capture a type's printed form, primer §7 leaf printer)
#extern fun
LSPCHK_strbuf_new((*0*)): FILR = $extnam()
#extern fun
LSPCHK_strbuf_get(fb: FILR): strn = $extnam()
//
// push one raw diagnostic (0-based internal coords) into the JS accumulator
#extern fun
LSPCHK_diag_push
( l0: sint, c0: sint
, l1: sint, c1: sint
, code: strn, message: strn): void = $extnam()
//
// push one hover entry (0-based internal coords) into the JS accumulator.
// `typ` = source-syntax type string (the pretty-printer below).
// `kind` = "expr" | "pat".
#extern fun
LSPCHK_hover_push
( l0: sint, c0: sint
, l1: sint, c1: sint
, typ: strn, kind: strn): void = $extnam()
//
// push one definition entry into the JS accumulator. Coords are 0-based.
//   use{l0,c0,l1,c1} = the use-site range (the D3Evar/D3Ecst/D3Econ node)
//   defpath          = entity's def-site fnm1 path (lctn.lsrc() -> fpath fnm1);
//                      "" when the source is not a real file (skip in JS)
//   def{l0,c0,l1,c1} = the binding-site range (entity.lctn())
//   entity           = "var" | "cst" | "con"
//   hastdef          = 1 if a type-def is supplied, else 0
//   tdpath           = type-constant def-site path (s2cst_get_lctn fnm1)
//   td{l0,c0,l1,c1}  = the type-constant's declaration range
#extern fun
LSPCHK_def_push
( ul0: sint, uc0: sint, ul1: sint, uc1: sint
, defpath: strn
, dl0: sint, dc0: sint, dl1: sint, dc1: sint
, entity: strn
, hastdef: sint
, tdpath: strn
, tl0: sint, tc0: sint, tl1: sint, tc1: sint): void = $extnam()
//
// dedup + serialize §4 bundle + write to jsonout
#extern fun
LSPCHK_json_finish
(uri: strn, nerror: sint, jsonout: strn): void = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
fpath_satsq
(fp: strn): bool = let
val n0 = strn_length(fp)
in
if (n0 <= 4) then false else
( if(fp[n0-1]!='s') then (false) else
  if(fp[n0-2]!='t') then (false) else
  if(fp[n0-3]!='a') then (false) else
  if(fp[n0-4]!='s') then (false) else
  if(fp[n0-5]!='.') then (false) else (true))
end
//
(* ****** ****** *)
//
// helper: is a list empty?  (used by the type pretty-printer below)
//
fun
list_nilq{a:t0}(xs: list(a)): bool =
( case+ xs of list_nil() => true | list_cons _ => false )
//
(* ****** ****** *)
//
// ----------------- render a type (s2typ) to a JS string ---------------
// A minimal source-ish renderer for type-mismatch messages: we extract the
// HEAD of the type so the message reads "expected `int`, got `string`"-ish
// rather than the full debug AST. We resolve:
//   T2Pcst(s2c)          -> the constant's name (e.g. gint_type, the_s2exp_strn0)
//   T2Papps(head, _)     -> recurse on the head (so int<...> -> its head name)
//   T2Ptext(name, _)     -> the external name string (e.g. xats_sint_t)
//   T2Ps2exp / others    -> fall back to the compiler's debug printer
// A full source-syntax pretty-printer is WS-2's job (primer §7); this is the
// cheap leaf-printer the task permits.
//
fun
typ_to_strn
(t2p: s2typ): strn = typ_aux(t2p, 4) where {
  // `fuel` bounds recursion through existential-var resolution chains so we
  // never loop on a self-referential / still-unresolved unification var.
  fun
  typ_aux
  (t2p: s2typ, fuel: sint): strn =
  if (fuel <= 0) then typ_to_strn_dbg(t2p) else
  (
  case+ s2typ_get_node(t2p) of
  | T2Pcst(s2c) => symbl_get_name(s2cst_get_name(s2c))
  | T2Papps(head, _) => typ_aux(head, fuel-1)
  | T2Ptext(nm, _) => nm
  | T2Pxtv(xv) => typ_aux(x2t2p_get_styp(xv), fuel-1)
  | _ => typ_to_strn_dbg(t2p)
  )
}
//
and
typ_to_strn_dbg
(t2p: s2typ): strn = let
  val fb = LSPCHK_strbuf_new()
  val () = s2typ_fprint(t2p, fb)
in
  LSPCHK_strbuf_get(fb)
end
//
(* ****** ****** *)
//
// =============== SOURCE-SYNTAX s2typ PRETTY-PRINTER (hover) =============
//
// A real source-form renderer over s2typ_node (primer §7). The only stock
// printer (s2typ_fprint) is DEBUG-form ("T2Papps(f; args)"), unreadable for
// hover, so we render proper surface syntax here:
//   T2Pcst(s2c)            -> constant name (friendly-mapped: gint_type->int…)
//   T2Pvar(s2v)            -> the type-variable's name
//   T2Pxtv(xv)             -> resolve to the unification var's styp (fuel-guarded)
//   T2Papps(f, args)       -> "f(a, b)"
//   T2Pfun1(_,_,args,res)  -> "(a, b) -> r"
//   T2Ptext(name, args)    -> "name(a, b)" (or bare "name" when nullary)
//   T2Ptrcd(knd,npf,lts)   -> "(a, b)" tuple / "@{l=a, m=b}" record (heuristic)
//   T2Pexi0/uni0(vs,body)  -> render the body (quantifiers are noise for hover)
//   T2Plft/top0/top1/arg1  -> render the wrapped inner type (markers, transparent)
//   T2Patx2(bef,aft)       -> render `aft` (the post-state type)
//   T2Ps2exp/none1/errck   -> recurse / fall back to the debug printer
//
// All recursion is bounded by `fuel`; on exhaustion we fall back to the leaf
// head-name renderer so we can never loop on a self-referential xtv chain.
//
// A type-constant head whose application args are internal representation
// noise (kind/rep parameters) rather than user-visible type arguments — these
// display as just their bare name (e.g. `int`, not `int(xats_sint_t, ...)`).
// We test the head name against this set; the JS friendly-map then renames it.
fun
prim_head_nameq
(nm: strn): bool =
  if strn_eq(nm, "gint_type") then true else
  if strn_eq(nm, "gflt_type") then true else
  if strn_eq(nm, "bool_type") then true else
  if strn_eq(nm, "char_type") then true else
  if strn_eq(nm, "void_type") then true else
  if strn_eq(nm, "string_type") then true else
  if strn_eq(nm, "string_i0_tx") then true else false
//
// is this s2typ a primitive type-constant head (T2Pcst with a prim name)?
fun
prim_app_headq
(t2p: s2typ): bool =
(
case+ s2typ_get_node(t2p) of
| T2Pcst(s2c) => prim_head_nameq(symbl_get_name(s2cst_get_name(s2c)))
| _ => false
)
//
fun
typ_pretty
(t2p: s2typ): strn = typ_p(t2p, 8)
//
and
typ_p
(t2p: s2typ, fuel: sint): strn =
if (fuel <= 0) then typ_to_strn(t2p) else
(
case+ s2typ_get_node(t2p) of
//
| T2Pcst(s2c) => symbl_get_name(s2cst_get_name(s2c))
| T2Pvar(s2v) => symbl_get_name(s2var_get_name(s2v))
//
| T2Pxtv(xv) => typ_p(x2t2p_get_styp(xv), fuel-1)
//
// application  F(a, b).  When the head is a primitive type constant, its
// app-args are internal representation params -> show just the head name.
| T2Papps(head, args) =>
  let
    val hs = typ_p(head, fuel-1)
  in
    if prim_app_headq(head)
    then hs
    else strn_append(hs,
           strn_append("(", strn_append(typlst_p(args, fuel-1), ")")))
  end
//
// function type  (a, b) -> r   (npf proof args are dropped for readability)
| T2Pfun1(_f2cl, _npf, args, res) =>
  strn_append("(",
    strn_append(typlst_p(args, fuel-1),
      strn_append(") -> ", typ_p(res, fuel-1))))
//
// external/text type: name or name(args)
| T2Ptext(nm, args) =>
  ( if list_nilq(args) then nm else
    strn_append(nm, strn_append("(",
      strn_append(typlst_p(args, fuel-1), ")"))) )
//
// tuple / record (we approximate: render the field types as a tuple)
| T2Ptrcd(_knd, _npf, lts) =>
  strn_append("(", strn_append(l2t2plst_p(lts, fuel-1), ")"))
//
// quantifiers are noise for a hover tooltip: show the body
| T2Pexi0(_vs, body) => typ_p(body, fuel-1)
| T2Puni0(_vs, body) => typ_p(body, fuel-1)
//
// transparent markers: render the inner type
| T2Plft(inner) => typ_p(inner, fuel-1)
| T2Ptop0(inner) => typ_p(inner, fuel-1)
| T2Ptop1(inner) => typ_p(inner, fuel-1)
| T2Parg1(_knd, inner) => typ_p(inner, fuel-1)
| T2Patx2(_bef, aft) => typ_p(aft, fuel-1)
| T2Pnone1(inner) => typ_p(inner, fuel-1)
//
| T2Plam1(_vs, body) => typ_p(body, fuel-1)
//
// inner-type marker we still want to peek through
| T2Perrck(_lvl, inner) => typ_p(inner, fuel-1)
//
// placeholder / no-type marker: render as `_` (used as a rep-arg slot)
| T2Pnone0() => "_"
//
// f2cl (closure-kind marker): show its inner if any; else a stable tag
| T2Pf2cl(_) => "<cloref>"
//
// lifted static exprs / anything else: debug-form leaf (still informative)
| _ => typ_to_strn(t2p)
)
//
and
typlst_p
(ts: s2typlst, fuel: sint): strn =
(
case+ ts of
| list_nil() => ""
| list_cons(t, list_nil()) => typ_p(t, fuel)
| list_cons(t, rest) =>
  strn_append(typ_p(t, fuel), strn_append(", ", typlst_p(rest, fuel)))
)
//
and
l2t2plst_p
(lts: l2t2plst, fuel: sint): strn =
(
case+ lts of
| list_nil() => ""
| list_cons(S2LAB(_, t), list_nil()) => typ_p(t, fuel)
| list_cons(S2LAB(_, t), rest) =>
  strn_append(typ_p(t, fuel), strn_append(", ", l2t2plst_p(rest, fuel)))
)
//
(* ****** ****** *)
//
// ============== loctn helpers: real-location guard + path =============
//
// A location is "real" iff its source is a file (LCSRCfpath) and the begin
// position is non-negative with a non-empty span. Dummy locations are
// POSTN(-1,-1,-1) (primer §5) — we skip those.
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
// extract the file path (fnm1) from a location's source, or "" if none.
//
fun
loc_fpath
(loc: loctn): strn =
(
case+ loc.lsrc() of
| LCSRCfpath(fp) => fpath_get_fnm1(fp)
| LCSRCsome1(s) => s
| _ => ""
)
//
//
// ------------------- push a diagnostic from a loctn --------------------
//
fun
push_diag
(loc: loctn, code: strn, msg: strn): void = let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  LSPCHK_diag_push
  ( pb.nrow(), pb.ncol()
  , pe.nrow(), pe.ncol(), code, msg)
end
//
(* ****** ****** *)
(* ****** ****** *)
//
// ===================== CLASSIFIERS (per level) ========================
//
// At an errck node we look at the WRAPPED node to choose code+message.
// We classify by the immediate wrapped constructor; this matches the
// empirical shapes in primer §6.
//
(* ---- L1 d1exp: only used to extract an unbound identifier name ---- *)
//
fun
d1exp_idname_opt
(d1e: d1exp): strn = (* "" if not a bare id *)
(
case+ d1exp_get_node(d1e) of
| D1Eid0(sym) => symbl_get_name(sym)
| _ => ""
)
//
(* ---- classify a wrapped L2 d2exp at a D2Eerrck ---- *)
//
fun
classify_d2exp
(loc: loctn, d2e: d2exp): void =
(
case+ d2e.node() of
//
// unbound identifier: D2Enone1(D1Eid0 name)  (primer §6)
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
//
| _ => push_diag(loc, "unknown", "type/elaboration error")
)
//
(* ---- classify a wrapped L2 d2pat at a D2Perrck ---- *)
//
fun
classify_d2pat
(loc: loctn, d2p: d2pat): void =
  push_diag(loc, "pattern-error", "pattern error")
//
(* ---- classify a wrapped L3 d3exp at a D3Eerrck ---- *)
//
fun
classify_d3exp
(loc: loctn, d3e: d3exp): void =
(
case+ d3e.node() of
//
// type mismatch: D3Et2pck(expr, expected); actual = expr.styp() (primer §6)
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
//
// unresolved template instantiation (primer §6, §4.1)
| D3Etimp _ =>
  push_diag(loc, "unresolved-template", "unresolved template instantiation")
| D3Etimq _ =>
  push_diag(loc, "unresolved-template", "unresolved template instantiation")
//
// an L2 error that survived into L3 unchanged: reclassify at L2
| D3Enone1(d2e1) => classify_d2exp(loc, d2e1)
//
| _ => push_diag(loc, "unknown", "type error")
)
//
(* ---- classify a wrapped L3 d3pat at a D3Perrck ---- *)
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
(* ---- classify a wrapped d2ecl / d3ecl at a *Cerrck ---- *)
// Decl-level errck usually re-wraps an inner expr/pat error; we still emit
// a decl-error at the decl range — dedup (D6) collapses it against the
// inner (smaller-range) diagnostic, so the inner classified one wins.
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
(* ****** ****** *)
//
// ============== HOVER + DEFINITION emission helpers ===================
//
// emit a hover for a node that has a real location and a type.
//
fun
emit_hover
(loc: loctn, t2p: s2typ, kind: strn): void =
if loc_realq(loc) then let
  val pb = loc.pbeg()
  val pe = loc.pend()
  val ts = typ_pretty(t2p)
in
  // skip empty / pathological type strings
  if strn_nilq(ts) then () else
  LSPCHK_hover_push
  ( pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), ts, kind)
end
//
// emit a definition for a use site `uloc` resolving to entity binding `dloc`.
// `t2p` is the use node's styp(); we add an optional type-definition when the
// type head is a T2Pcst with a real location (primer §8).
//
fun
emit_def
(uloc: loctn, dloc: loctn, entity: strn, t2p: s2typ): void =
if loc_realq(uloc) then
( if loc_realq(dloc) then let
    val upb = uloc.pbeg() and upe = uloc.pend()
    val dpb = dloc.pbeg() and dpe = dloc.pend()
    val defpath = loc_fpath(dloc)
  in
    if strn_nilq(defpath) then () else let
      // optional type-definition: head T2Pcst -> s2cst_get_lctn
      val (hastdef, tdpath, tloc) = typedef_of(t2p)
      val tpb = tloc.pbeg() and tpe = tloc.pend()
    in
      LSPCHK_def_push
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
(t2p: s2typ): (sint, strn, loctn) = typedef_aux(t2p, 6)
//
and
typedef_aux
(t2p: s2typ, fuel: sint): (sint, strn, loctn) =
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
(* ****** ****** *)
//
// ===================== TRAVERSAL (find all errck) =====================
//
// In addition to harvesting `…errck` nodes (diagnostics), the d3-family walk
// now ALSO emits a hover for every d3exp/d3pat with a real location+type, and
// a definition for every D3Evar/D3Ecst/D3Econ use site. All three features
// share this single traversal (primer §9; LSP goals #2/#3).
//
// Mutually-recursive walk over the d3 family (and the d2 family it embeds
// via D3Cnone1/D3Enone1/D3Pnone1). Composite nodes recurse; leaves are
// ignored via the wildcard. At each `…errck` we classify (above) AND keep
// descending into the wrapped node (nested errcks carry inner detail).
//
fun
walk_d3exp (d3e0: d3exp): void = let
//
// HOVER: every expression node carries its type (primer §7).
val () = emit_hover(d3e0.lctn(), d3e0.styp(), "expr")
//
in
(
case+ d3e0.node() of
//
| D3Eerrck(lvl, d3e1) =>
  ( walk_d3exp(d3e1)
  ; if (lvl < 3) then classify_d3exp(d3e0.lctn(), d3e1) )
//
// DEFINITION use sites (primer §8): the embedded entity object carries its
// own binding-site location; type-def comes from the node's styp() head.
| D3Evar(v) => emit_def(d3e0.lctn(), d2var_get_lctn(v), "var", d3e0.styp())
| D3Econ(c) => emit_def(d3e0.lctn(), d2con_get_lctn(c), "con", d3e0.styp())
| D3Ecst(c) => emit_def(d3e0.lctn(), d2cst_get_lctn(c), "cst", d3e0.styp())
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
| D3Elet0(dcls, d3e1) => (walk_d3eclist(dcls); walk_d3exp(d3e1))
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
  (walk_f3arglst(farg); walk_d3exp(d3e1))
| D3Efix0(_, _, farg, _, _, d3e1) =>
  (walk_f3arglst(farg); walk_d3exp(d3e1))
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
| _ => ((*leaf / no nested errck*))
) end
//
and
walk_d3pat (d3p0: d3pat): void = let
//
// HOVER: every pattern node carries its type too (primer §7).
val () = emit_hover(d3p0.lctn(), d3p0.styp(), "pat")
//
in
(
case+ d3p0.node() of
| D3Perrck(lvl, d3p1) =>
  ( walk_d3pat(d3p1)
  ; if (lvl < 3) then classify_d3pat(d3p0.lctn(), d3p1) )
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
| D3Cstatic(_, dcl1) => walk_d3ecl(dcl1)
| D3Cextern(_, dcl1) => walk_d3ecl(dcl1)
| D3Ctmpsub(_, dcl1) => walk_d3ecl(dcl1)
| D3Cdclst0(dcls) => walk_d3eclist(dcls)
| D3Clocal0(da, db) => (walk_d3eclist(da); walk_d3eclist(db))
| D3Cinclude(_, _, _, _, dopt) => walk_d3eclistopt(dopt)
| D3Cvaldclst(_, dvs) => walk_d3valdclist(dvs)
| D3Cvardclst(_, dvs) => walk_d3vardclist(dvs)
| D3Cfundclst(_, _, _, dfs) => walk_d3fundclist(dfs)
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
        | _ => ((*static / metric args: no d3pat children*)) )
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
    ( walk_d3pat(d3valdcl_get_dpat(dv))
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
    ( walk_teqd3exp(d3fundcl_get_tdxp(df))
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
    ( walk_teqd2exp(d2fundcl_get_tdxp(df))
    ; walk_d2fundclist(dfs) ) )
(* ****** ****** *)
(* ****** ****** *)
//
// ----------------------- driver: run + emit ---------------------------
//
fun
run_check
(fpth: strn, uri: strn, jsonout: strn): void = let
//
val dpar =
  if (fpath_satsq(fpth))
  then d3parsed_of_filsats(fpth)
  else d3parsed_of_fildats(fpth)
//
val nerror = d3parsed_get_nerror(dpar)
//
// ALWAYS traverse: the one walk now harvests diagnostics (errck nodes),
// hovers (every typed d3exp/d3pat) and definitions (D3Evar/Ecst/Econ use
// sites). Even error-free files need the hover/def indices (LSP #2/#3).
val () = walk_d3eclistopt(d3parsed_get_parsed(dpar))
//
in
  LSPCHK_json_finish(uri, nerror, jsonout)
end
//
(* ****** ****** *)
//
// argv parsing: positional source, then --uri <u>, --json-out <p>.
// argv[2] is the first user arg (node app.js argv[2] ...).
//
fun
find_flag
(flag: strn): strn = let
  val n = LSPCHK_argv_count()
  fun loop(i: sint): strn =
    if (i+1 < n)
    then ( if strn_eq(LSPCHK_argv_get(i), flag)
           then LSPCHK_argv_get(i+1)
           else loop(i+1) )
    else ""
in
  loop(2)
end
//
(* ****** ****** *)
//
fun
mymain_work
(fpth: strn): void = let
  val uri0 = find_flag("--uri")
  val uri = if strn_nilq(uri0) then strn_append("file://", fpth) else uri0
  val jout0 = find_flag("--json-out")
  val jout = if strn_nilq(jout0) then "lsp-check.json" else jout0
in
  run_check(fpth, uri, jout)
end
//
(* ****** ****** *)
//
// flag-loading + argv plumbing copied from the stock tcheck driver.
//
#typedef cargv = jsa1sz(strn)
//
fun
cargv$loop
(argv: cargv): void = (loop(3)) where {
  val n0 = length(argv)
  fun loop(i0: sint): void =
    if (i0 < n0) then (loop(i0+1)) where {
      val () = xatsopt_flag$pvsadd0(argv[i0])
    }
}
//
fun
mymain_main(): void = let
//
val argv = XATSOPT_argv$get()
val alen = length(argv)
//
in
//
if (alen >= 3) then let
  val ret1 = the_fxtyenv_pvsl00d()
  val ret2 = the_tr12env_pvsl00d()
  val () = xatsopt_flag$pvsadd0("--_XATSOPT_")
  val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATSOPT_")
in
  cargv$loop(argv); mymain_work(argv[2])
end
else
  prerrsln("ERROR: usage: <src.dats|sats> --uri <uri> --json-out <path>")
//
end
//
(* ****** ****** *)
val ((*entry*)) = mymain_main()
(* ****** ****** *)
//
(***********************************************************************)
(* end of [language-server/server/DATS/xats_lsp_check.dats] *)
(***********************************************************************)
