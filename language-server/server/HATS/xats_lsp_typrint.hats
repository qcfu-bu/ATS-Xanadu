(* ****** ****** *)
(*
xats_lsp_typrint.hats — FAITHFUL s2typ -> ATS3 surface-syntax pretty-printer.

SHARED, single source of truth, #include'd by:
  * language-server/server/DATS/xats_lsp_check.dats   (one-shot checker)
  * language-server/server/resident/DATS/xats_lsp_resident.dats (editor server)
  * language-server/server/DATS/xats_lsp_typrint_rt.dats (round-trip harness)

The printer is the INVERSE of `p1_s0exp` (srcgen2/DATS/parsing_staexp.dats):
every s2typ_node constructor is rendered as the surface syntax that re-parses
(via p1_s0exp + s2exp_stpize / f0_impr) to the SAME s2typ. Grounded in the spec
language-server/docs/S2TYP-SURFACE-SYNTAX.md and the forward map f0_impr
(srcgen2/DATS/statyp2_utils1.dats:549-775).

Two MODEs:
  * TPMhover : friendly + readable (drops empty quantifiers, peeks wrappers,
               collapses int width to the friendly width name) — for tooltips.
  * TPMexact : resolvable + round-trippable (resolvable width name, keep
               quantifiers, $extype("...") for external) — for round-trip proof.

Requires (all in scope via libxatsopt.hats):
  statyp2.sats : s2typ_get_node, T2P* constructors, x2t2p_get_styp/get_stmp
  staexp2.sats : s2cst/s2var accessors, S2LAB, l2t2p, s2varlst
  xbasics.sats : trcdknd (TRCDflt0/box0/box1/box2), f2clknd (F2CLfun/F2CLclo)
  xlabel0.sats : label (LABint/LABsym)
  xsymbol.sats : symbl_get_name
The including file must provide:
  fun typ_to_strn (t2p: s2typ): strn         -- leaf debug renderer (fallback)
  fun TYPRINT_int2str (n: sint): strn        -- FFI (impl in the .cats)
  fun TYPRINT_stamp2str (s: stamp): strn     -- FFI (impl in the .cats)
  fun TYPRINT_sort2str (s: sort2): strn      -- sort -> source name (for Exact)
*)
(* ****** ****** *)
//
// printer mode. distinct nullary tags; matched by tag below.
//
datatype tpmode = TPMhover | TPMexact
//
fun
tpmode_exactq(m: tpmode): bool =
  (case+ m of TPMexact() => true | TPMhover() => false)
//
(* ****** ****** *)
//
// list-empty test (kept local; some including files already define one, so the
// name is namespaced).
//
fun
typr_nilq{a:t0}(xs: list(a)): bool =
  (case+ xs of list_nil() => true | list_cons _ => false)
//
(* ****** ****** *)
//
// ---- friendly head-name map (Hover only) -------------------------------
// Grounds in prelude/basics0.sats head names. In TPMexact we DON'T rename
// (resolvable names round-trip); in TPMhover we map to the surface spelling.
//
fun
typr_friendly_head(nm: strn): strn =
  if strn_eq(nm, "xats_void_t")    then "void"    else
  if strn_eq(nm, "bool_type")      then "bool"    else
  if strn_eq(nm, "char_type")      then "char"    else
  if strn_eq(nm, "gflt_type")      then "double"  else
  if strn_eq(nm, "string_i0_tx")   then "string"  else
  if strn_eq(nm, "p1tr_tbox")      then "ptr"     else
  if strn_eq(nm, "p2tr_tbox")      then "p2tr"    else
  if strn_eq(nm, "list_t0_i0_tx")  then "list"    else
  if strn_eq(nm, "list_vt_i0_vx")  then "list_vt" else
  if strn_eq(nm, "optn_t0_i0_tx")  then "optn"    else
  if strn_eq(nm, "optn_vt_i0_vx")  then "optn_vt" else
  if strn_eq(nm, "lazy_t0_tx")     then "lazy"    else
  if strn_eq(nm, "lazy_vt_vx")     then "lazy_vt" else
  // singleton index-term constants (a literal's static index), shown as the
  // base type for hover readability.
  if strn_eq(nm, "the_s2exp_sint0") then "int"    else
  if strn_eq(nm, "the_s2exp_bool0") then "bool"   else
  if strn_eq(nm, "the_s2exp_char0") then "char"   else
  if strn_eq(nm, "the_s2exp_strn0") then "string" else
  if strn_eq(nm, "the_s2exp_void")  then "void"   else
  if strn_eq(nm, "the_s2exp_uint0")  then "uint"   else
  if strn_eq(nm, "the_s2exp_slint0") then "lint"   else
  if strn_eq(nm, "the_s2exp_ulint0") then "ulint"  else
  if strn_eq(nm, "the_s2exp_sllint0") then "llint" else
  if strn_eq(nm, "the_s2exp_ullint0") then "ullint" else
  if strn_eq(nm, "the_s2exp_sflt0")  then "float"  else
  if strn_eq(nm, "the_s2exp_dflt0")  then "double" else
  if strn_eq(nm, "the_s2exp_list0")  then "list"   else
  if strn_eq(nm, "the_s2exp_optn0")  then "optn"   else
  if strn_eq(nm, "the_s2exp_lazy0")  then "lazy"   else
  if strn_eq(nm, "the_s2exp_p1")     then "ptr"    else
  if strn_eq(nm, "the_s2exp_p2")     then "p2tr"   else
  (nm)
//
(* ****** ****** *)
//
// ---- integer-width name from the `_k` rep tag -------------------------
// All int widths share head `gint_type`; only the FIRST app-arg (the `_k`
// rep tag, e.g. $extype("xats_sint_t")) tells them apart. Likewise gflt_type.
// We look at the tag string (T2Ptext name or T2Pcst name) of the head's first
// application argument. Returns "" if the tag is unrecognized.
//
fun
typr_intwidth_of_tag(tag: strn): strn =
  if strn_eq(tag, "xats_sint_t")   then "int"    else
  if strn_eq(tag, "xats_uint_t")   then "uint"   else
  if strn_eq(tag, "xats_slint_t")  then "lint"   else
  if strn_eq(tag, "xats_ulint_t")  then "ulint"  else
  if strn_eq(tag, "xats_ssize_t")  then "ssize"  else
  if strn_eq(tag, "xats_usize_t")  then "usize"  else
  if strn_eq(tag, "xats_sllint_t") then "llint"  else
  if strn_eq(tag, "xats_ullint_t") then "ullint" else
  (* gflt widths *)
  if strn_eq(tag, "xats_sflt_t")   then "float"  else
  if strn_eq(tag, "xats_dflt_t")   then "double" else
  if strn_eq(tag, "xats_ldflt_t")  then "ldouble" else
  ("")
//
// extract the rep-tag string of a type node (the head of an int/flt rep arg).
//
fun
typr_tag_of_typ(t2p: s2typ): strn =
(
case+ s2typ_get_node(t2p) of
| T2Ptext(nm, _) => nm
| T2Pcst(s2c) => symbl_get_name(s2cst_get_name(s2c))
| _ => ""
)
//
(* ****** ****** *)
//
// f2clknd -> arrow token (T2Pfun1 / T2Pf2cl).
//   F2CLfun       -> "->"
//   F2CLclo(~1)   -> "-<cloref>"   (ref)
//   F2CLclo(1|0)  -> "-<cloptr>"   (ptr/flat)
//
fun
typr_arrow_of_f2cl(t2cl: s2typ): strn =
(
case+ s2typ_get_node(t2cl) of
| T2Pf2cl(knd) =>
  (
  case+ knd of
  | F2CLfun() => "->"
  | F2CLclo(k) => if (0 > k) then "-<cloref>" else "-<cloptr>"
  )
| _ => "->"
)
//
(* ****** ****** *)
//
// is this node a function type? (for parenthesization: arrow prec 10 < app/
// arg prec 70, so an arg/left-arm that is itself a T2Pfun1 needs parens).
//
fun
typr_funq(t2p: s2typ): bool =
(
case+ s2typ_get_node(t2p) of
| T2Pfun1 _ => true
// peek transparent wrappers
| T2Plft(t) => typr_funq(t)
| T2Pnone1(t) => typr_funq(t)
| T2Perrck(_, t) => typr_funq(t)
| T2Ptop0(t) => typr_funq(t)
| T2Ptop1(t) => typr_funq(t)
| _ => false
)
//
(* ****** ****** *)
//
// is the head of a T2Papps the gint_type / gflt_type primitive? (so the args
// are rep params, and we print the width name instead of "gint_type(...)").
//
fun
typr_gnum_headq(head: s2typ): bool =
(
case+ s2typ_get_node(head) of
| T2Pcst(s2c) =>
  let val nm = symbl_get_name(s2cst_get_name(s2c)) in
    if strn_eq(nm, "gint_type") then true else strn_eq(nm, "gflt_type")
  end
| _ => false
)
//
(* ****** ****** *)
//
// =================== the printer ===================
//
fun
typr_pretty_mode
(t2p: s2typ, m: tpmode): strn = typr_p(t2p, m, 24)
//
and
typr_p
(t2p: s2typ, m: tpmode, fuel: sint): strn =
if (fuel <= 0) then typ_to_strn(t2p) else
(
case+ s2typ_get_node(t2p) of
//
// --- leaves ---
| T2Pcst(s2c) =>
  let val nm = symbl_get_name(s2cst_get_name(s2c)) in
    if tpmode_exactq(m) then nm else typr_friendly_head(nm)
  end
| T2Pvar(s2v) => symbl_get_name(s2var_get_name(s2v))
//
// existential var: solved -> its styp; unsolved -> "[stamp]".
| T2Pxtv(xv) =>
  let val st = x2t2p_get_styp(xv) in
    case+ s2typ_get_node(st) of
    | T2Pnone0() =>
      strn_append("[#", strn_append(TYPRINT_stamp2str(x2t2p_get_stmp(xv)), "]"))
    | _ => typr_p(st, m, fuel-1)
  end
//
// --- application  f(a, b) ---
| T2Papps(head, args) =>
  (
  // primitive numeric head: print the width name from the first rep-arg tag.
  if typr_gnum_headq(head)
  then
    let
      val w =
        (case+ args of
         | list_cons(a0, _) => typr_intwidth_of_tag(typr_tag_of_typ(a0))
         | list_nil() => "")
    in
      if strn_eq(w, "") then typr_p(head, m, fuel-1) else w
    end
  else
    let
      // drop erased static-index args (T2Pnone0 -> "_"); e.g. bool(_) -> bool,
      // list(int, _) -> list(int). These are static indices not in the surface
      // type and never round-trip; keeping them is noise.
      val args1 = typr_drop_erased(args)
    in
      case+ args1 of
      | list_nil() => typr_p(head, m, fuel-1)
      | list_cons _ =>
        strn_append(typr_p(head, m, fuel-1),
          strn_append("(", strn_append(typr_plst(args1, m, fuel-1), ")")))
    end
  )
//
// --- function type  (pf | a, b) -> r ---
| T2Pfun1(f2cl, npf, args, res) =>
  let
    val arr = typr_arrow_of_f2cl(f2cl)
    val ins = typr_arglst(args, npf, m, fuel-1)
  in
    strn_append("(",
      strn_append(ins,
        strn_append(") ",
          strn_append(arr,
            strn_append(" ", typr_p_arm(res, m, fuel-1))))))
  end
//
// --- tuple / record ---
| T2Ptrcd(knd, npf, lts) => typr_trcd(knd, npf, lts, m, fuel-1)
//
// --- quantifiers ---
| T2Pexi0(vs, body) =>
  strn_append(typr_quant("[", "]", vs, m, fuel-1), typr_p(body, m, fuel-1))
| T2Puni0(vs, body) =>
  strn_append(typr_quant("{", "}", vs, m, fuel-1), typr_p(body, m, fuel-1))
//
// --- arg modifiers (only as a T2Pfun1 arg, but handle anywhere) ---
| T2Parg1(knd, inner) =>
  ( if (knd > 0) then strn_append("!", typr_p(inner, m, fuel-1)) else
    if (0 > knd) then strn_append("&", typr_p(inner, m, fuel-1)) else
    typr_p(inner, m, fuel-1) )
| T2Patx2(bef, aft) =>
  strn_append(typr_p(bef, m, fuel-1),
    strn_append(" >> ", typr_p(aft, m, fuel-1)))
//
// --- external ---
| T2Ptext(nm, args) =>
  if tpmode_exactq(m)
  then
    ( if typr_nilq(args)
      then strn_append("$extype(\"", strn_append(nm, "\")"))
      else strn_append("$extype(\"",
             strn_append(nm,
               strn_append("\", ",
                 strn_append(typr_plst(args, m, fuel-1), ")")))) )
  else
    ( if typr_nilq(args) then nm
      else strn_append(nm,
             strn_append("(", strn_append(typr_plst(args, m, fuel-1), ")"))) )
//
// --- parameterized type abstraction (rare in value position) ---
| T2Plam1(vs, body) =>
  strn_append("lam",
    strn_append(typr_quant("(", ")", vs, m, fuel-1),
      strn_append(" => ", typr_p(body, m, fuel-1))))
//
// --- lifted static expression: delegate to the debug leaf printer ---
| T2Ps2exp(_) => typ_to_strn(t2p)
//
// --- transparent wrappers: descend ---
| T2Plft(inner) => typr_p(inner, m, fuel-1)
| T2Pnone1(inner) => typr_p(inner, m, fuel-1)
| T2Perrck(_, inner) => typr_p(inner, m, fuel-1)
| T2Ptop0(inner) => typr_p(inner, m, fuel-1)
| T2Ptop1(inner) => typr_p(inner, m, fuel-1)
//
// --- placeholders / markers ---
| T2Pnone0() => "_"
| T2Pf2cl(_) => typr_arrow_of_f2cl(t2p)
)
//
(* ****** ****** *)
//
// an arm/arg printed with parens iff it is itself a function type (prec).
//
and
typr_p_arm
(t2p: s2typ, m: tpmode, fuel: sint): strn =
if (fuel <= 0) then typ_to_strn(t2p) else
( if typr_funq(t2p)
  then strn_append("(", strn_append(typr_p(t2p, m, fuel), ")"))
  else typr_p(t2p, m, fuel) )
//
(* ****** ****** *)
//
// plain comma list (application args, $extype args).
//
and
typr_plst
(ts: s2typlst, m: tpmode, fuel: sint): strn =
(
case+ ts of
| list_nil() => ""
| list_cons(t, list_nil()) => typr_p(t, m, fuel)
| list_cons(t, rest) =>
  strn_append(typr_p(t, m, fuel),
    strn_append(", ", typr_plst(rest, m, fuel)))
)
//
// drop erased static-index app-args: a T2Pnone0 (the "_" placeholder produced
// by s2exp_stpize for a non-impredicative index) carries no surface type info.
//
and
typr_drop_erased
(ts: s2typlst): s2typlst =
(
case+ ts of
| list_nil() => list_nil()
| list_cons(t, rest) =>
  (case+ s2typ_get_node(t) of
   | T2Pnone0() => typr_drop_erased(rest)
   | _ => list_cons(t, typr_drop_erased(rest)))
)
//
(* ****** ****** *)
//
// function-arg list, honoring npf (the proof `|` separator) and per-arg
// parenthesization (an arg that is itself a function type).
//   npf = ~1 : no bar
//   npf =  0 : "| a, b"
//   npf =  k : "pf1, .., pfk | a, b"
//
and
typr_arglst
(ts: s2typlst, npf: sint, m: tpmode, fuel: sint): strn =
if (0 > npf) then typr_arglst_nobar(ts, m, fuel) else
  let
    val (pfs, rest) = typr_split(ts, npf)
    val sl = typr_arglst_nobar(rest, m, fuel)
  in
    case+ pfs of
    | list_nil() => strn_append("| ", sl)
    | list_cons _ =>
      strn_append(typr_arglst_nobar(pfs, m, fuel),
        strn_append(" | ", sl))
  end
//
and
typr_arglst_nobar
(ts: s2typlst, m: tpmode, fuel: sint): strn =
(
case+ ts of
| list_nil() => ""
| list_cons(t, list_nil()) => typr_p_arm(t, m, fuel)
| list_cons(t, rest) =>
  strn_append(typr_p_arm(t, m, fuel),
    strn_append(", ", typr_arglst_nobar(rest, m, fuel)))
)
//
// split a list at position k (k >= 0): (first k, remaining).
//
and
typr_split
(ts: s2typlst, k: sint): (s2typlst, s2typlst) =
if (k <= 0) then (list_nil(), ts) else
(
case+ ts of
| list_nil() => (list_nil(), list_nil())
| list_cons(t, rest) =>
  let val (a, b) = typr_split(rest, k-1) in (list_cons(t, a), b) end
)
//
(* ****** ****** *)
//
// tuple / record. trcdknd sub-table:
//   TRCDflt0       : @(...) / @{...}   (flat)
//   TRCDbox0/box1  : #(...) / #{...}   (boxed; linearity erased)
//   TRCDbox2       : $tuprf(...) / $recrf(...)  (ref-counted)
// tuple vs record by the FIRST label: LABint -> tuple, LABsym -> record.
//
and
typr_trcd
(knd: trcdknd, npf: sint, lts: l2t2plst, m: tpmode, fuel: sint): strn =
let
  val recq = typr_l2t2p_recq(lts)
  val lp =
    (case+ knd of
     | TRCDflt0() => if recq then "@{" else "@("
     | TRCDbox0() => if recq then "#{" else "#("
     | TRCDbox1() => if recq then "#{" else "#("
     | TRCDbox2() => if recq then "$recrf(" else "$tuprf(")
  val rp =
    (case+ knd of
     | TRCDflt0() => if recq then "}" else ")"
     | TRCDbox0() => if recq then "}" else ")"
     | TRCDbox1() => if recq then "}" else ")"
     | TRCDbox2() => ")")
  val body =
    if recq
    then typr_rcdlst(lts, npf, m, fuel)
    else typr_tuplst(lts, npf, m, fuel)
in
  strn_append(lp, strn_append(body, rp))
end
//
// record iff the first label is a symbol (name) label.
//
and
typr_l2t2p_recq(lts: l2t2plst): bool =
(
case+ lts of
| list_nil() => false
| list_cons(S2LAB(lab, _), _) =>
  (case+ lab of LABsym _ => true | LABint _ => false)
)
//
// tuple element list (drop labels; honor npf bar).
//
and
typr_tuplst
(lts: l2t2plst, npf: sint, m: tpmode, fuel: sint): strn =
let
  val (pfs, rest) = typr_l2split(lts, npf)
  val sl = typr_tuplst_nobar(rest, m, fuel)
in
  if (0 > npf) then sl else
  (case+ pfs of
   | list_nil() => strn_append("| ", sl)
   | list_cons _ => strn_append(typr_tuplst_nobar(pfs, m, fuel),
                      strn_append(" | ", sl)))
end
//
and
typr_tuplst_nobar
(lts: l2t2plst, m: tpmode, fuel: sint): strn =
(
case+ lts of
| list_nil() => ""
| list_cons(S2LAB(_, t), list_nil()) => typr_p(t, m, fuel)
| list_cons(S2LAB(_, t), rest) =>
  strn_append(typr_p(t, m, fuel),
    strn_append(", ", typr_tuplst_nobar(rest, m, fuel)))
)
//
// record field list  l=a, m=b  (honor npf bar).
//
and
typr_rcdlst
(lts: l2t2plst, npf: sint, m: tpmode, fuel: sint): strn =
let
  val (pfs, rest) = typr_l2split(lts, npf)
  val sl = typr_rcdlst_nobar(rest, m, fuel)
in
  if (0 > npf) then sl else
  (case+ pfs of
   | list_nil() => strn_append("| ", sl)
   | list_cons _ => strn_append(typr_rcdlst_nobar(pfs, m, fuel),
                      strn_append(" | ", sl)))
end
//
and
typr_rcdlst_nobar
(lts: l2t2plst, m: tpmode, fuel: sint): strn =
(
case+ lts of
| list_nil() => ""
| list_cons(S2LAB(lab, t), list_nil()) =>
  strn_append(typr_label(lab), strn_append("= ", typr_p(t, m, fuel)))
| list_cons(S2LAB(lab, t), rest) =>
  strn_append(typr_label(lab),
    strn_append("= ",
      strn_append(typr_p(t, m, fuel),
        strn_append(", ", typr_rcdlst_nobar(rest, m, fuel)))))
)
//
and
typr_label(lab: label): strn =
(
case+ lab of
| LABsym(s) => strn_append(symbl_get_name(s), "")
| LABint(i) => TYPRINT_int2str(i)
)
//
and
typr_l2split
(lts: l2t2plst, k: sint): (l2t2plst, l2t2plst) =
if (k <= 0) then (list_nil(), lts) else
(
case+ lts of
| list_nil() => (list_nil(), list_nil())
| list_cons(t, rest) =>
  let val (a, b) = typr_l2split(rest, k-1) in (list_cons(t, a), b) end
)
//
(* ****** ****** *)
//
// quantifier var list "v1, v2" wrapped by the open/close brackets, with a
// trailing space. In TPMexact each var prints with its sort: "v: srt".
//
and
typr_quant
(lbk: strn, rbk: strn, vs: s2varlst, m: tpmode, fuel: sint): strn =
strn_append(lbk, strn_append(typr_varlst(vs, m), strn_append(rbk, " ")))
//
and
typr_varlst
(vs: s2varlst, m: tpmode): strn =
(
case+ vs of
| list_nil() => ""
| list_cons(v, list_nil()) => typr_var(v, m)
| list_cons(v, rest) =>
  strn_append(typr_var(v, m), strn_append(", ", typr_varlst(rest, m)))
)
//
and
typr_var(v: s2var, m: tpmode): strn =
let
  val nm = symbl_get_name(s2var_get_name(v))
in
  // Exact mode keeps the sort ("a: type") so the quantifier round-trips; Hover
  // drops it for readability.
  if tpmode_exactq(m)
  then strn_append(nm, strn_append(": ", typr_sort2name(s2var_get_sort(v))))
  else nm
end
//
// surface sort NAME. The stock sort2_fprint emits debug syntax
// ("S2Tbas(T2Bimpr(0;type))"); we pull out the surface spelling for the common
// base-sort cases so the quantifier re-parses, and fall back to the debug
// renderer for compound sorts (rare in a quantifier binder).
//
and
typr_sort2name(srt: sort2): strn =
(
case+ srt of
| S2Tid0(s) => symbl_get_name(s)
| S2Tbas(tb) =>
  (case+ tb of
   | T2Bpred(s) => symbl_get_name(s)
   | T2Bimpr(_, s) => symbl_get_name(s)
   | _ => TYPRINT_sort2str(srt))
| _ => TYPRINT_sort2str(srt)
)
//
(* ****** ****** *)
//
// back-compat entry: the existing hover call site uses `typ_pretty`.
//
fun
typ_pretty(t2p: s2typ): strn = typr_pretty_mode(t2p, TPMhover())
//
(* ****** ****** *)
// end of [xats_lsp_typrint.hats]
(* ****** ****** *)
