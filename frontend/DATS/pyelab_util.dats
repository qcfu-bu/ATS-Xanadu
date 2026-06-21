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
| PCElam(loc, _, _, _, _) => loc | PCElet(loc, _, _, _, _) => loc
| PCEvarcell(loc, _, _, _, _) => loc | PCEassign(loc, _, _) => loc
| PCEletfun(loc, _, _) => loc | PCEif(loc, _, _, _) => loc
| PCEcase(loc, _, _) => loc   | PCEtup(loc, _) => loc
| PCErec(loc, _) => loc       | PCElist(loc, _) => loc
| PCEfield(loc, _, _) => loc  | PCEseq(loc, _, _) => loc
| PCEunit(loc) => loc         | PCEerror(loc, _) => loc
| PCEraise(loc, _) => loc     | PCEtry(loc, _, _) => loc
| PCEinst(loc, _, _) => loc
| PCEwhere(loc, _, _) => loc
| PCEaddr(loc, _) => loc      | PCEderef(loc, _) => loc
| PCEmove(loc, _, _) => loc   | PCEswap(loc, _, _) => loc
)
//
#implfun
pcpat_loctn(p) =
(
case+ p of
| PCPvar(loc, _) => loc   | PCPwild(loc) => loc
| PCPcon(loc, _, _, _) => loc | PCPtup(loc, _) => loc
| PCPrec(loc, _) => loc   | PCPlit(loc, _) => loc
| PCPas(loc, _, _) => loc | PCPfree(loc, _) => loc
)
//
#implfun
pcdecl_loctn(d) =
(
case+ d of
| PCCdata(loc, _, _, _, _) => loc | PCCfun(loc, _, _, _) => loc
| PCCval(loc, _, _) => loc     | PCCstaload(loc, _) => loc
| PCCimport(loc, _, _, _) => loc
| PCCalias(loc, _, _, _) => loc
| PCCrecord(loc, _, _, _, _) => loc
| PCCexcept(loc, _, _) => loc
| PCCabstype(loc, _, _, _) => loc
| PCCassume(loc, _, _) => loc
| PCCextern(loc, _, _, _, _) => loc
| PCCimplement(loc, _, _, _, _, _, _) => loc | PCCoverload(loc, _, _) => loc
| PCCtempl(loc, _, _, _, _, _, _, _) => loc
| PCCsortdef(loc, _, _) => loc | PCCstacst(loc, _, _) => loc
| PCCsortsub(loc, _, _, _) => loc
| PCCstadef(loc, _, _) => loc
| PCCprfun(loc, _, _) => loc   | PCCprval(loc, _, _, _) => loc
| PCCpraxi(loc, _, _, _, _) => loc
| PCCprivate(loc, _) => loc
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
//
// ---- M5a: the `mut`-accumulator TYPE map helpers ----------------------------
//
// (local) does `mts` already map `nm`?
fun mt_has(mts: list(@(strn, pytyp)), nm: strn): bool =
(
case+ mts of
| list_nil() => false
| list_cons(kt, rest) => if strn_eq(kt.0, nm) then true else mt_has(rest, nm)
)
//
// register `let mut nm : T` — only an ANNOTATED, not-yet-mapped name is recorded (first wins,
// so a re-`let mut` of the same name does not clobber). An unannotated `let mut` is a no-op.
#implfun
muttypes_add(mts, nm, topt) =
(
case+ topt of
| PyTypNone() => mts
| PyTypSome(t) =>
    if mt_has(mts, nm) then mts else list_append(mts, list_sing(@(nm, t)))
)
//
// the recorded annotation for `nm` (PyTypNone() if absent).
#implfun
muttypes_find(mts, nm) =
(
case+ mts of
| list_nil() => PyTypNone()
| list_cons(kt, rest) => if strn_eq(kt.0, nm) then PyTypSome(kt.1) else muttypes_find(rest, nm)
)
//
// the PARALLEL list(pytypopt) for an accumulator nameset (one entry per acc, same order).
#implfun
accs_types(accs, mts) =
(
case+ accs of
| list_nil() => list_nil()
| list_cons(nm, rest) => list_cons(muttypes_find(mts, nm), accs_types(rest, mts))
)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_util.dats]
*)
