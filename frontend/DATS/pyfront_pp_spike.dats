(* ****** ****** *)
(*
** P2 PRETTY-PRINTER SPIKE — prove we can OBTAIN + WALK the stock level-0 AST
** (the `d0parsed` produced by the stock parser) from a real ATS file path, and
** DISPATCH on each top-level declaration's node tag. This is the access recipe
** the whole L0->pythonic pretty-printer is built on.
**
** RECIPE (cited):
**   (1) d0parsed_from_fpath(stadyn, fpath)  [parsing.sats:680]  -> d0parsed
**       stadyn = 0 for a STATIC file (.sats interface); 1 for dynamic.
**   (2) d0parsed_get_parsed(dpar)            [dynexp0.sats:1434] -> optn(d0eclist)
**   (3) for each d0ecl: d0ecl.node()         [dynexp0.sats:1176] -> d0ecl_node
**       dispatch on the constructor (D0Cabstype/D0Csexpdef/D0Cdynconst/
**       D0Csymload/D0Cdefine/D0Cinclude/...).
**   (4) NAMES: an i0dnt's .node() = I0DNTsome(token) [staexp0.sats:278]; the
**       token's .node() = a tnode carrying the raw string for T_IDALP/T_IDSYM/
**       T_IDDLR/T_IDSRP/T_IDQUA [lexing0.sats:82-90].
**
** PURELY ADDITIVE: only CALLS the compiler-as-a-library (lib2xatsopt). Nothing
** under srcgen2/ or language-server/ is modified.
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
// the LEVEL-0 datatypes (NOT in libxatsopt.hats): the parser entry + the d0ecl/
// s0exp node datatypes whose constructors we dispatch on.
#staload "./../../srcgen2/SATS/staexp0.sats"
#staload "./../../srcgen2/SATS/dynexp0.sats"
#staload "./../../srcgen2/SATS/parsing.sats"
//
(* ****** ****** *)
//
#extern fun PYP_log(s: strn): void = $extnam()
#extern fun PYP_log_int(s: strn, n: sint): void = $extnam()
//
(* ****** ****** *)
//
// extract the raw lexeme string out of a token (the identifier/literal payload).
// covers exactly the tnode forms xstamp0's names/literals use.
//
fun
tok_lexeme(tok: token): strn =
(
  case+ tok.node() of
  | T_IDALP(s) => s
  | T_IDSYM(s) => s
  | T_IDDLR(s) => s     // $name
  | T_IDSRP(s) => s     // #name
  | T_IDQUA(s) => s     // $name.
  | T_IDENT(s) => s
  | T_INT01(s) => s
  | T_STRN1_clsd(s, _) => s
  | _ => "?"
)
//
// an i0dnt's name (I0DNTsome|I0DNTnone both wrap a token).
fun
i0dnt_lexeme(id: i0dnt): strn =
(
  case+ id.node() of
  | I0DNTsome(tok) => tok_lexeme(tok)
  | I0DNTnone(tok) => tok_lexeme(tok)
)
//
(* ****** ****** *)
//
// the one-word tag of a d0ecl_node (for the spike's tag dump).
//
fun
d0ecl_tag(dc: d0ecl): strn =
(
  case+ dc.node() of
  | D0Cnonfix _   => "D0Cnonfix"
  | D0Cfixity _   => "D0Cfixity"
  | D0Cstatic _   => "D0Cstatic"
  | D0Cextern _   => "D0Cextern"
  | D0Cdefine _   => "D0Cdefine"
  | D0Cmacdef _   => "D0Cmacdef"
  | D0Clocal0 _   => "D0Clocal0"
  | D0Cabssort _  => "D0Cabssort"
  | D0Cstacst0 _  => "D0Cstacst0"
  | D0Csortdef _  => "D0Csortdef"
  | D0Csexpdef _  => "D0Csexpdef"
  | D0Cabstype _  => "D0Cabstype"
  | D0Cabsopen _  => "D0Cabsopen"
  | D0Cabsimpl _  => "D0Cabsimpl"
  | D0Csymload _  => "D0Csymload"
  | D0Cinclude _  => "D0Cinclude"
  | D0Cstaload _  => "D0Cstaload"
  | D0Cdyninit _  => "D0Cdyninit"
  | D0Cextcode _  => "D0Cextcode"
  | D0Cdatasort _ => "D0Cdatasort"
  | D0Cvaldclst _ => "D0Cvaldclst"
  | D0Cvardclst _ => "D0Cvardclst"
  | D0Cfundclst _ => "D0Cfundclst"
  | D0Cimplmnt0 _ => "D0Cimplmnt0"
  | D0Cexcptcon _ => "D0Cexcptcon"
  | D0Cdatatype _ => "D0Cdatatype"
  | D0Cdynconst _ => "D0Cdynconst"
  | D0Ctkerr _    => "D0Ctkerr"
  | D0Ctkskp _    => "D0Ctkskp"
  | D0Cerrck _    => "D0Cerrck"
  | D0Cifdef _    => "D0Cifdef"
  | D0Cifexp _    => "D0Cifexp"
  | D0Celsif _    => "D0Celsif"
  | D0Cthen0 _    => "D0Cthen0"
  | D0Celse1 _    => "D0Celse1"
  | D0Cendif _    => "D0Cendif"
)
//
// a salient NAME for the decl (best-effort, for evidence that we can reach names).
//
fun
d0ecl_name(dc: d0ecl): strn =
(
  case+ dc.node() of
  | D0Cabstype(_, sid, _, _, _) => i0dnt_lexeme(sid)
  | D0Csexpdef(_, sid, _, _, _, _) => i0dnt_lexeme(sid)
  | D0Cdefine(_, gid, _, _) => i0dnt_lexeme(gid)
  | D0Csymload(_, _, _, dqi, _) =>
    (
      case+ dqi of
      | D0QIDnone(id) => i0dnt_lexeme(id)
      | D0QIDsome(_, id) => i0dnt_lexeme(id)
    )
  | D0Cdynconst(_, _, dcdcls) =>
    (
      case+ dcdcls of
      | list_cons(dcd, _) => i0dnt_lexeme(d0cstdcl_get_dpid(dcd))
      | list_nil() => "(empty)"
    )
  | _ => "-"
)
//
(* ****** ****** *)
//
fun
walk(out: FILR, n: sint, dcs: d0eclist): void =
(
  case+ dcs of
  | list_nil() => ()
  | list_cons(dc, rest) => let
      val () = strn_fprint("  [", out)
      val () = gint_fprint$sint(n, out)
      val () = strn_fprint("] ", out)
      val () = strn_fprint(d0ecl_tag(dc), out)
      val () = strn_fprint("  name=", out)
      val () = strn_fprint(d0ecl_name(dc), out)
      val () = strn_fprint("\n", out)
    in
      walk(out, n+1, rest)
    end
)
//
(* ****** ****** *)
//
fun
mymain_pp_spike((*void*)): void = let
//
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYP_log("######## P2 PRETTY-PRINTER L0-ACCESS SPIKE ########")
//
val fpath = "srcgen2/SATS/xstamp0.sats"
val () = (PYP_log("[pp] parsing fpath = "); PYP_log(fpath))
//
// (1) parse the real ATS file to its stock d0parsed (stadyn=0: a STATIC .sats).
val dpar = d0parsed_from_fpath(0(*static*), fpath)
val nerr = d0parsed_get_nerror(dpar)
val () = PYP_log_int("[pp] d0parsed nerror (parser) =", nerr)
//
// (2) the parsed decl list (optn).
val dopt = d0parsed_get_parsed(dpar)
val out  = g_stdout<>()
//
in
  case+ dopt of
  | ~optn_cons(dcs) => let
      val () = PYP_log("[pp] -- top-level d0ecl tags (stdout) --")
      val () = strn_fprint("D0ECL-TAGS:\n", out)
      val () = walk(out, 0, dcs)
    in
      PYP_log("RESULT: GO (walked the L0 d0ecl list; tags+names dumped to stdout)")
    end
  | ~optn_nil() =>
      PYP_log("RESULT: NO-GO (parser returned no d0eclist)")
end // end of [mymain_pp_spike]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_pp_spike()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_pp_spike.dats]
*)
