(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: PyCore utilities (DATS).
**
** The PyCore-node `loctn` accessors declared in pycore.sats, plus small shared helpers
** the elaborator uses (string-list set ops over `mut` names; deterministic ordering).
** PURE; no global state.
**
** PURELY ADDITIVE; consumes pycore.sats / pyparsing.sats / locinfo.sats read-only.
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
//
#staload "./../SATS/pyelab.sats"
//
(* ****** ****** *)
//
// ---- PyCore node location accessors (SATS-declared in pycore.sats) ----------
//
#implfun
pcexp_loctn(e) =
(
case+ e of
| PCElit(loc, _) => loc       | PCEvar(loc, _) => loc
| PCEcon(loc, _) => loc       | PCEapp(loc, _, _) => loc
| PCElam(loc, _, _) => loc    | PCElet(loc, _, _, _) => loc
| PCEletfun(loc, _, _) => loc | PCEif(loc, _, _, _) => loc
| PCEcase(loc, _, _) => loc   | PCEtup(loc, _) => loc
| PCErec(loc, _) => loc       | PCElist(loc, _) => loc
| PCEfield(loc, _, _) => loc  | PCEseq(loc, _, _) => loc
| PCEunit(loc) => loc         | PCEerror(loc, _) => loc
)
//
#implfun
pcpat_loctn(p) =
(
case+ p of
| PCPvar(loc, _) => loc   | PCPwild(loc) => loc
| PCPcon(loc, _, _) => loc | PCPtup(loc, _) => loc
| PCPrec(loc, _) => loc   | PCPlit(loc, _) => loc
)
//
#implfun
pcdecl_loctn(d) =
(
case+ d of
| PCCdata(loc, _, _, _) => loc | PCCfun(loc, _) => loc
| PCCval(loc, _, _) => loc     | PCCstaload(loc, _) => loc
| PCCerror(loc, _) => loc
)
//
(* ****** ****** *)
//
// ---- string-set helpers over `mut`/accumulator names (deterministic order) --
//
// membership.
#implfun
nameset_mem(xs, x) =
(
case+ xs of
| list_nil() => false
| list_cons(y, rest) => if strn_eq(x, y) then true else nameset_mem(rest, x)
)
//
// add (set union of a single element; keep first-seen / declaration order — append at
// end so existing order is preserved and the new name is last).
#implfun
nameset_add(xs, x) =
  if nameset_mem(xs, x) then xs
  else list_append(xs, list_sing(x))
//
// union (xs ++ those of ys not already in xs; preserves xs order then ys order).
#implfun
nameset_union(xs, ys) =
(
case+ ys of
| list_nil() => xs
| list_cons(y, rest) => nameset_union(nameset_add(xs, y), rest)
)
//
// intersect (keep elements of xs that are in ys; xs order = deterministic = decl order).
#implfun
nameset_inter(xs, ys) =
(
case+ xs of
| list_nil() => list_nil()
| list_cons(x, rest) =>
  if nameset_mem(ys, x)
    then list_cons(x, nameset_inter(rest, ys))
    else nameset_inter(rest, ys)
)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_util.dats]
*)
