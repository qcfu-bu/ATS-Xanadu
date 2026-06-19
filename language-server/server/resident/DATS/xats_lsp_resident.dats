(* ****** ****** *)
(*
RESIDENT LSP server — main driver (DATS).  Workstream R1.

ONE resident artifact: a long-running ATS3->JS node program that bundles the
ATS3 compiler front-end and checks IN-PROCESS. The prelude is loaded ONCE at
startup; each check reuses the warm compiler.

This file:
  (1) implements the FFI surface declared in SATS/xats_lsp_resident.sats by
      forwarding to the same-named JS bodies in CATS/xats_lsp_resident.cats;
  (2) ports the reference's dependency-extraction pass (dependency30): walks a
      checked d3parsed, and for every `staload` edge adds "B depends on A" to the
      depgraph so editing A later evicts A AND B;
  (3) REUSES our harvest traversal + s2typ pretty-printer (copied from
      server/DATS/xats_lsp_check.dats) — at each `…errck` it classifies a
      diagnostic; at every typed d3exp/d3pat it emits a hover; at every
      D3Evar/D3Ecst/D3Econ use site it emits a definition. Instead of writing a
      JSON bundle, it pushes rows into the .cats's per-uri in-memory index;
  (4) defines text_validator (didOpen/didSave -> in-process check + harvest) and
      cache_pruner (didChange -> env_reset over the topmaps + dependents);
  (5) startup: the_fxtyenv_pvsload(), the_tr12env_pvsl00d(), the two flags, then
      initialize(validator, pruner) which starts the connection loop.

Primer anchors: §3 (front-end API), §4 (one-shot-state solved via eviction),
§5 (0-based internal coords via accessors), §6 (errck/codes/dedup), §7 (s2typ
pretty-print), §8 (def loc), §9 (traversal), §10.5 (compiler-linking build).
*)
(* ****** ****** *)
//
#include "./../HATS/libxatsopt_resident.hats"
//
#include "srcgen2/HATS/xatsopt_sats.hats"
#include "srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../SATS/xats_lsp_resident.sats"
//
(* ****** ****** *)
(* ====================================================================== *)
(*                    FFI bindings (impl in the .cats)                     *)
(* ====================================================================== *)
//
#implfun url_to_path(uri) =
  vscode_url_to_path(uri)
  where { #extern fun vscode_url_to_path(uri: url) : string = $extnam() }
//
#implfun severity_error$make() =
  vscode_severity_error$make()
  where { #extern fun vscode_severity_error$make() : severity = $extnam() }
//
#implfun position_make(line, offs) : position =
  vscode_position_make(line, offs)
  where { #extern fun
    vscode_position_make(line: int, offs: int): position = $extnam() }
//
#implfun range_make(pbeg, pend): range =
  vscode_range_make(pbeg, pend)
  where { #extern fun
    vscode_range_make(pbeg: position, pend: position): range = $extnam() }
//
#implfun range_of_loctn(loc0) = let
    val pbeg0 = loc0.pbeg()
    val pend0 = loc0.pend()
    val pbeg1 = position_make(pbeg0.nrow(), pbeg0.ncol())
    val pend1 = position_make(pend0.nrow(), pend0.ncol())
  in range_make(pbeg1, pend1)
  end
//
#implfun diagnostic_make(severity, location, message, source) : diagnostic =
  vscode_diagnostic_make(severity, location, message, source)
  where { #extern fun
    vscode_diagnostic_make
    ( severity: severity, location: range
    , message: string, source: string): diagnostic = $extnam() }
//
#implfun diagnostics_push(ds, d) =
  vscode_diagnostics_push(ds, d)
  where { #extern fun
    vscode_diagnostics_push(ds: diagnostics, d: diagnostic): void = $extnam() }
#symload push with diagnostics_push
//
#implfun regex_make(pat) =
  vscode_regex_make(pat)
  where { #extern fun vscode_regex_make(pat: string): regex = $extnam() }
//
#implfun regex_test(re, input) =
  vscode_regex_test(re, input)
  where { #extern fun
    vscode_regex_test(re: regex, input: string): bool = $extnam() }
//
(* ---- dependency set / graph (ported from reference lsp_bootstrap) ---- *)
//
#implfun depset_make() =
  JS_depset_make()
  where { #extern fun JS_depset_make(): depset = $extnam() }
//
#implfun depset_add(dp, key) =
  JS_depset_add(dp, key)
  where { #extern fun JS_depset_add(dp: depset, key: sym_t): void = $extnam() }
//
#implfun depset_pop(dp) =
  JS_depset_pop(dp)
  where { #extern fun JS_depset_pop(dp: depset): sym_t = $extnam() }
//
#implfun depset_is_empty(dp) =
  JS_depset_is_empty(dp)
  where { #extern fun JS_depset_is_empty(dp: depset): bool = $extnam() }
//
#implfun depset_has(dp, key) =
  JS_depset_has(dp, key)
  where { #extern fun JS_depset_has(dp: depset, key: sym_t): bool = $extnam() }
//
#implfun depset_union(dp1, dp2) =
  JS_depset_union(dp1, dp2)
  where { #extern fun
    JS_depset_union(dp1: depset, dp2: depset): depset = $extnam() }
//
// depgraph is keyed in JS by the file's STAMP (a number), but we also store the
// sym_t itself (k0) so depset_union/pop can hand back real sym_t handles. This
// matches the reference exactly: JS_depgraph_add(dp, k.stmp(), k, v).
//
#implfun depgraph_add(dp, k, v) =
  JS_depgraph_add(dp, k.stmp(), k, v)
  where { #extern fun
    JS_depgraph_add(dp: depgraph, k: stamp, k0: sym_t, v: sym_t): void = $extnam() }
//
#implfun depgraph_delete(dp, k) =
  JS_depgraph_delete(dp, k.stmp())
  where { #extern fun
    JS_depgraph_delete(dp: depgraph, k: stamp): void = $extnam() }
//
#implfun depgraph_has(dp, k) =
  JS_depgraph_has(dp, k.stmp())
  where { #extern fun
    JS_depgraph_has(dp: depgraph, k: stamp): bool = $extnam() }
//
#implfun depgraph_find(dp, k) =
  JS_depgraph_find(dp, k.stmp())
  where { #extern fun
    JS_depgraph_find(dp: depgraph, k: stamp): depset = $extnam() }
//
#implfun fwd_graph() =
  JS_fwd_graph()
  where { #extern fun JS_fwd_graph(): depgraph = $extnam() }
//
(* ---- THE cache-eviction primitive: delete env[key.stmp()] ---- *)
//
// topmap_insert (xsymmap_topmap.dats) stores each file under g0u2s(uint(
// key.stmp())) in a jshmap (a plain JS object). So evicting a file is exactly
// `delete env[ key.stmp() ]` — the JS-key coercion is identical on both sides.
//
#implfun env_reset{syn}(env, key) =
  JS_map_reset{syn}(env, key.stmp())
  where { #extern fun
    JS_map_reset{syn:tx}(env: topmap(syn), key: stamp): void = $extnam() }
//
(* ---- R2a: prelude snapshot + workspace-file signature map ---- *)
//
// snapshot the keys already present in a topmap (called per topmap right after
// the prelude loads): those stamps = the prelude / $XATSHOME files (immutable).
//
#implfun prelude_snapshot{syn}(env) =
  JS_prelude_snapshot{syn}(env)
  where { #extern fun
    JS_prelude_snapshot{syn:tx}(env: topmap(syn)): void = $extnam() }
//
#implfun prelude_freeze() =
  JS_prelude_freeze()
  where { #extern fun JS_prelude_freeze(): void = $extnam() }
//
// signature map keyed by the file's stamp (same key the topmaps use). path is
// the absolute on-disk filename (fnm1) used to stat it.
//
#implfun sig_record(key, path) =
  JS_sig_record(key.stmp(), path)
  where { #extern fun JS_sig_record(key: stamp, path: string): void = $extnam() }
//
#implfun sig_refresh(key) =
  JS_sig_refresh(key.stmp())
  where { #extern fun JS_sig_refresh(key: stamp): void = $extnam() }
//
#implfun sig_changed(key) =
  JS_sig_changed(key.stmp())
  where { #extern fun JS_sig_changed(key: stamp): bool = $extnam() }
//
(* ---- string-buffer FILR (capture a printed type; externs, like our checker) ---- *)
//
#extern fun LSP_strbuf_new((*0*)): FILR = $extnam()
#extern fun LSP_strbuf_get(fb: FILR): string = $extnam()
//
(* ---- harvest push primitives (per-uri index in the .cats) ---- *)
//
#implfun diag_push(l0, c0, l1, c1, code, message) =
  LSP_diag_push(l0, c0, l1, c1, code, message)
  where { #extern fun
    LSP_diag_push
    ( l0: int, c0: int, l1: int, c1: int
    , code: string, message: string): void = $extnam() }
//
#implfun hover_push(l0, c0, l1, c1, typ, kind) =
  LSP_hover_push(l0, c0, l1, c1, typ, kind)
  where { #extern fun
    LSP_hover_push
    ( l0: int, c0: int, l1: int, c1: int
    , typ: string, kind: string): void = $extnam() }
//
#implfun def_push
  ( ul0, uc0, ul1, uc1, defpath
  , dl0, dc0, dl1, dc1, entity, hastdef, tdpath
  , tl0, tc0, tl1, tc1) =
  LSP_def_push
  ( ul0, uc0, ul1, uc1, defpath
  , dl0, dc0, dl1, dc1, entity, hastdef, tdpath
  , tl0, tc0, tl1, tc1)
  where { #extern fun
    LSP_def_push
    ( ul0: int, uc0: int, ul1: int, uc1: int
    , defpath: string
    , dl0: int, dc0: int, dl1: int, dc1: int
    , entity: string
    , hastdef: int
    , tdpath: string
    , tl0: int, tc0: int, tl1: int, tc1: int): void = $extnam() }
//
#implfun initialize(f, g) =
  vscode_initialize(f, g)
  where { #extern fun
    vscode_initialize(f: text_validator_t, g: cache_pruner_t): void = $extnam() }
//
(* ****** ****** *)
(* ====================================================================== *)
(*       DEPENDENCY EXTRACTION  (ported from reference dependency30)       *)
(* ====================================================================== *)
//
// Walk a checked d3parsed; for every `staload`, record an edge "key0 depends
// on the staloaded file key1" by depgraph_add(dp, key1, key0). Editing key1
// later (didChange) then evicts key1 AND every key0 that staloaded it.
//
// R2a additions, in the SAME pass (no extra AST walk):
//   * FORWARD edge depgraph_add(fwd, key0, key1) — "key0 staloads key1" — so a
//     later check can walk key0's staload CLOSURE forward and stat each member.
//   * sig_record(key1, fnm1) — stamp the staloaded WORKSPACE file with its
//     {mtimeMs,size} signature (no-op for prelude files; they stay immutable).
//
// We descend into D3Cstaload's embedded sub-parse so transitive deps are
// captured: if A staloads B and B staloads C, the graph gets C->B and B->A,
// and evicting C unions in B then A. `depgraph_has` guards against re-walking
// an already-recorded file (cuts cycles + redundant work).
//
fun
dependency_d3ecl
(dp: depgraph, fwd: depgraph, d3cl: d3ecl, key0: sym_t): void =
  case+ d3cl.node() of
  | D3Clocal0(dcls1, dcls2) => let
      val () = dependency_d3eclist(dp, fwd, dcls1, key0)
      val () = dependency_d3eclist(dp, fwd, dcls2, key0)
    in end
  | D3Cinclude(_, _, _, _, dopt) => dependency_d3eclistopt(dp, fwd, dopt, key0)
  | D3Cstaload(_stadyn, _tok, _src, fopt, s3opt) =>
    ( case+ fopt of
      | optn_cons(fpath) => let
          val key1 = fpath.fnm2()
          // forward edge (key0 staloads key1) + workspace-file signature.
          val () = depgraph_add(fwd, key0, key1)
          val () = sig_record(key1, fpath.fnm1())
          val () =
            if depgraph_has(dp, key1) then ()
            else dependency_s3taloadopt(dp, fwd, s3opt, key1)
          val () = depgraph_add(dp, key1, key0)
        in end
      | optn_nil() => () )
  | _ => ()
//
and
dependency_d3eclist
(dp: depgraph, fwd: depgraph, dcls: d3eclist, key0: sym_t): void =
  case+ dcls of
  | list_nil() => ()
  | list_cons(d, ds) =>
    (dependency_d3ecl(dp, fwd, d, key0); dependency_d3eclist(dp, fwd, ds, key0))
//
and
dependency_d3eclistopt
(dp: depgraph, fwd: depgraph, dopt: d3eclistopt, key0: sym_t): void =
  case+ dopt of
  | optn_nil() => ()
  | optn_cons(dcls) => dependency_d3eclist(dp, fwd, dcls, key0)
//
and
dependency_s3taloadopt
(dp: depgraph, fwd: depgraph, s3opt: s3taloadopt, key0: sym_t): void =
  case+ s3opt of
  | S3TALOADdpar(_stadyn, dpar) =>
      dependency_d3eclistopt(dp, fwd, d3parsed_get_parsed(dpar), key0)
  | S3TALOADnone(_s2opt) => ()
//
(* ****** ****** *)
//
// is this resolved path a .dats? (vs .sats). Reference uses a regex; we reuse
// our existing suffix check shape for clarity but via the JS regex FFI to match
// the reference (the dispatch is identical).
//
fun
fpath_is_dats(fp: string): bool = let
  val re = regex_make(".*[.]dats$")
in regex_test(re, fp)
end
//
(* ****** ****** *)
(* ====================================================================== *)
(*   HARVEST: s2typ pretty-printer + traversal  (reused from              *)
(*   server/DATS/xats_lsp_check.dats — verified harvest logic)            *)
(* ====================================================================== *)
//
// helper: is a list empty?  (used by the type pretty-printer below)
//
fun
list_nilq{a:t0}(xs: list(a)): bool =
( case+ xs of list_nil() => true | list_cons _ => false )
//
(* ---- leaf head-name renderer (type-mismatch messages) ---- *)
//
fun
typ_to_strn
(t2p: s2typ): string = typ_aux(t2p, 4) where {
  fun
  typ_aux
  (t2p: s2typ, fuel: int): string =
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
(t2p: s2typ): string = let
  val fb = LSP_strbuf_new()
  val () = s2typ_fprint(t2p, fb)
in
  LSP_strbuf_get(fb)
end
//
(* ---- source-syntax s2typ pretty-printer (hover) ---- *)
//
// FAITHFUL printer lives in the SHARED include (single source of truth, reused
// by the one-shot checker and the round-trip harness). It needs three FFI/leaf
// helpers (int label / xtv stamp / sort -> string), implemented here + .cats.
//
#extern fun
TYPRINT_int2str(n: int): string = $extnam()
#extern fun
TYPRINT_stamp2str(s: stamp): string = $extnam()
//
// surface sort name via the strbuf + sort2_fprint (used by the Exact mode of
// the shared printer; on the hover path it never fires, but keep it sound).
fun
TYPRINT_sort2str
(srt: sort2): string = let
  val fb = LSP_strbuf_new()
  val () = sort2_fprint(srt, fb)
in
  LSP_strbuf_get(fb)
end
//
#include "./../../HATS/xats_lsp_typrint.hats"
//
(* ---- loctn helpers: real-location guard + path ---- *)
//
fun
loc_realq
(loc: loctn): bool = let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  if (pb.nrow() < 0) then false else
  if (pb.ncol() < 0) then false else
  if (pe.ntot() <= pb.ntot()) then false else true
end
//
fun
loc_fpath
(loc: loctn): string =
(
case+ loc.lsrc() of
| LCSRCfpath(fp) => fpath_get_fnm1(fp)
| LCSRCsome1(s) => s
| _ => ""
)
//
fun
push_diag
(loc: loctn, code: string, msg: string): void = let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  diag_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), code, msg)
end
//
(* ---- classifiers (per level) ---- *)
//
fun
d1exp_idname_opt
(d1e: d1exp): string =
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
(* ---- hover + definition emission helpers ---- *)
//
fun
emit_hover
(loc: loctn, t2p: s2typ, kind: string): void =
if loc_realq(loc) then let
  val pb = loc.pbeg()
  val pe = loc.pend()
  val ts = typ_pretty(t2p)
in
  if strn_nilq(ts) then () else
  hover_push(pb.nrow(), pb.ncol(), pe.nrow(), pe.ncol(), ts, kind)
end
//
fun
emit_def
(uloc: loctn, dloc: loctn, entity: string, t2p: s2typ): void =
if loc_realq(uloc) then
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
(* ---- the traversal (find all errck; emit hover/def) ---- *)
//
fun
walk_d3exp (d3e0: d3exp): void = let
  val () = emit_hover(d3e0.lctn(), d3e0.styp(), "expr")
in
(
case+ d3e0.node() of
| D3Eerrck(lvl, d3e1) =>
  ( walk_d3exp(d3e1)
  ; if (lvl < 3) then classify_d3exp(d3e0.lctn(), d3e1) )
| D3Evar(v) => emit_def(d3e0.lctn(), d2var_get_lctn(v), "var", d3e0.styp())
| D3Econ(c) => emit_def(d3e0.lctn(), d2con_get_lctn(c), "con", d3e0.styp())
| D3Ecst(c) => emit_def(d3e0.lctn(), d2cst_get_lctn(c), "cst", d3e0.styp())
| D3Et2pck(d3e1, _) => walk_d3exp(d3e1)
| D3Et2ped(d3e1, _) => walk_d3exp(d3e1)
| D3Elabck(d3e1, _) => walk_d3exp(d3e1)
| D3Eannot(d3e1, _, _) => walk_d3exp(d3e1)
| D3Etimp(d3f0, _) => walk_d3exp(d3f0)
| D3Etimq(d3f0, _, _) => walk_d3exp(d3f0)
| D3Esapp(d3f0, _) => walk_d3exp(d3f0)
| D3Esapq(d3f0, _) => walk_d3exp(d3f0)
| D3Etapp(d3f0, _) => walk_d3exp(d3f0)
| D3Etapq(d3f0, _) => walk_d3exp(d3f0)
| D3Edap0(d3f0) => walk_d3exp(d3f0)
| D3Edapp(d3f0, _, d3es) => (walk_d3exp(d3f0); walk_d3explst(d3es))
| D3Epcon(_, _, d3e1) => walk_d3exp(d3e1)
| D3Eproj(_, _, d3e1) => walk_d3exp(d3e1)
| D3Elet0(dcls, d3e1) => (walk_d3eclist(dcls); walk_d3exp(d3e1))
| D3Eift0(d3e1, dthn, dels) =>
  (walk_d3exp(d3e1); walk_d3expopt(dthn); walk_d3expopt(dels))
| D3Ecas0(_, d3e1, dcls) => (walk_d3exp(d3e1); walk_d3clslst(dcls))
| D3Eseqn(d3es, d3e1) => (walk_d3explst(d3es); walk_d3exp(d3e1))
| D3Etup0(_, d3es) => walk_d3explst(d3es)
| D3Etup1(_, _, d3es) => walk_d3explst(d3es)
| D3Ercd2(_, _, ld3es) => walk_l3d3elst(ld3es)
| D3Elam0(_, farg, _, _, d3e1) =>
  (walk_f3arglst(farg); walk_d3exp(d3e1))
| D3Efix0(_, _, farg, _, _, d3e1) =>
  (walk_f3arglst(farg); walk_d3exp(d3e1))
| D3Etry0(_, d3e1, dcls) => (walk_d3exp(d3e1); walk_d3clslst(dcls))
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
| D3Ewhere(d3e1, dcls) => (walk_d3exp(d3e1); walk_d3eclist(dcls))
| D3Eassgn(dl, dr) => (walk_d3exp(dl); walk_d3exp(dr))
| D3Exazgn(dl, dr) => (walk_d3exp(dl); walk_d3exp(dr))
| D3Exchng(dl, dr) => (walk_d3exp(dl); walk_d3exp(dr))
| D3Eraise(_, d3e1) => walk_d3exp(d3e1)
| D3Eexists(_, d3e1) => walk_d3exp(d3e1)
| D3El0azy(_, d3e1) => walk_d3exp(d3e1)
| D3El1azy(_, d3e1, d3es) => (walk_d3exp(d3e1); walk_d3explst(d3es))
| D3Eelazy(_, d3e1, d3es) => (walk_d3exp(d3e1); walk_d3explst(d3es))
| D3Enone1(d2e1) => walk_d2exp(d2e1)
| D3Enone2(d3e1) => walk_d3exp(d3e1)
| _ => ((*leaf*))
) end
//
and
walk_d3pat (d3p0: d3pat): void = let
  val () = emit_hover(d3p0.lctn(), d3p0.styp(), "pat")
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
//
(* ****** ****** *)
(* ====================================================================== *)
(*            VALIDATOR + PRUNER + STARTUP  (the resident core)            *)
(* ====================================================================== *)
//
// evict_cascade: the shared eviction worklist (used by both the didChange pruner
// and the R2a precheck). Seeded with a depset of files to evict; for each popped
// file, env_reset it out of all three topmaps, pull its dependents from the
// (reverse) depgraph, union them in, and delete its graph entry — so editing a
// file evicts it AND every file that staloaded it. The prelude + untouched files
// stay cached -> the recheck is warm. Bounded: each file is processed once
// (depgraph_delete drops the visited entry, and depgraph_find of a leaf is empty).
//
fun
evict_cascade(dp: depgraph, seed: depset): void = let
    fun loop(work: depset): void =
      if ~depset_is_empty(work) then let
        val key = depset_pop(work)
        val () = env_reset(the_d1parenv_pvstmap(), key)
        val () = env_reset(the_d2parenv_pvstmap(), key)
        val () = env_reset(the_d3parenv_pvstmap(), key)
        val deps1 = depgraph_find(dp, key)
        val deps2 = depset_union(work, deps1)
        val () = depgraph_delete(dp, key)
      in loop(deps2)
      end
  in loop(seed)
  end
//
// R2a PRECHECK (the content-validated cache core). BEFORE each validate, walk the
// target's transitive-staload closure (forward graph) and re-stat each WORKSPACE
// member; any whose on-disk {mtimeMs,size} drifted (an out-of-band edit — another
// editor, git pull/checkout, codegen, formatter) is evicted via evict_cascade,
// which also cascades to its dependents. Prelude/$XATSHOME files are NEVER statted
// here: sig_changed returns false for them because sig_record never admitted them
// to the signature map (gated by the $XATSHOME path-prefix exclusion). Cost:
// O(|closure|) statSync (~µs each); the closure is small (the target's deps), so
// this is negligible against a warm check. (R2 Layer A.)
//
fun
precheck(dp: depgraph, fwd: depgraph, key0: sym_t): void = let
    val seen  = depset_make()   // forward-closure files already visited
    val dirty = depset_make()   // changed files to evict (+ cascade)
    // BFS the forward closure: key0 (the target itself — d3parsed_of_fil would
    // otherwise serve key0's STALE cached parse if it was edited out-of-band, so
    // the headline single-file case needs key0 statted too) plus its transitive
    // staloads.
    fun walk(work: depset): void =
      if ~depset_is_empty(work) then let
        val k = depset_pop(work)
      in
        if depset_has(seen, k) then walk(work)
        else let
          val () = depset_add(seen, k)
          // changed on disk? (no-op/false for prelude + unknown files)
          val () = if sig_changed(k) then depset_add(dirty, k)
          // descend into k's own forward staloads (transitive closure).
          val nbrs = depgraph_find(fwd, k)
          val work1 = depset_union(work, nbrs)
        in walk(work1) end
      end
    val work0 = depset_make()
    val () = depset_add(work0, key0)
  in
    let val () = walk(work0) in
      if ~depset_is_empty(dirty) then evict_cascade(dp, dirty)
    end
  end
//
// text_validator: invoked on didOpen/didSave. Resolve the file path from the
// uri, PRECHECK its staload closure for out-of-band drift (R2a), run the
// front-end IN-PROCESS (d3parsed_of_fil{dats,sats}; the warm compiler reuses the
// cached prelude + unchanged deps), record dependency edges (both directions)
// from the checked parse + stamp each workspace dep's signature, and harvest
// diagnostics + hover/def index from the SAME d3parsed. No subprocess, no temp
// JSON.
//
#implfun text_validator(dp, ds, uri) = let
    val path = url_to_path(uri)
    val key = path.fpath().fnm2()
    val fwd = fwd_graph()
    // R2a: catch on-disk drift in this file's staload closure BEFORE serving from
    // cache; evict any stale dep (+ cascade) so the check below re-translates it.
    val () = precheck(dp, fwd, key)
    val dpar =
      if fpath_is_dats(path)
      then d3parsed_of_fildats(path)
      else d3parsed_of_filsats(path)
    val parsed = d3parsed_get_parsed(dpar)
    // record "this file depends on each staloaded file" (reverse edge, for the
    // pruner) + "this file staloads each" (forward edge, for the precheck) + each
    // workspace dep's {mtimeMs,size} signature. One pass, both graphs.
    val () = dependency_d3eclistopt(dp, fwd, parsed, key)
    // also stamp THIS file's own signature so a later check of a dependent can
    // detect an out-of-band edit to it (the dependency pass only stamps deps).
    val () = sig_record(key, path)
    // harvest: diagnostics (errck) + hovers (typed nodes) + defs (use sites).
    val () = walk_d3eclistopt(parsed)
  in
    // `ds` is unused as a sink here (the .cats holds the per-uri index that the
    // diag_push calls populated); kept in the signature for parity with the
    // reference's validator shape. Touch it to avoid an unused warning.
    let val _ = ds in () end
  end
//
// cache_pruner: invoked on didChange. Evict the edited file AND its transitive
// dependents from the_d{1,2,3}parenv so the next validate re-translates them.
//
#implfun cache_pruner(dp, uri) = let
    val path = url_to_path(uri)
    val key = path.fpath().fnm2()
    val deps0 = depset_make()
    val () = depset_add(deps0, key)
  in evict_cascade(dp, deps0)
  end
//
(* ****** ****** *)
//
// initialize the xatsopt environment ONCE (loads the prelude), set the flags,
// then bootstrap the vscode-languageserver connection loop. These run on load.
//
val _ = the_fxtyenv_pvsload()
val _ = the_tr12env_pvsl00d()
val () = xatsopt_flag$pvsadd0("--_XATSOPT_")
val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATSOPT_")
//
// R2a PRELUDE SNAPSHOT: right after the prelude loads (above) and BEFORE any user
// file is checked, record the set of file stamps already cached in each of the
// three topmaps. That set = the prelude / $XATSHOME files; they are IMMUTABLE for
// the session — never statted, never evicted (the C1/restart path is out of scope
// here). freeze() seals the set. Any file NOT in it is a workspace file subject
// to mtime validation. This also correctly excludes a workspace rooted at the
// ATS-Xanadu repo: its prelude files are already in the snapshot.
//
val () = prelude_snapshot(the_d1parenv_pvstmap())
val () = prelude_snapshot(the_d2parenv_pvstmap())
val () = prelude_snapshot(the_d3parenv_pvstmap())
val () = prelude_freeze()
//
val () = initialize(text_validator, cache_pruner)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_resident.dats]
*)
