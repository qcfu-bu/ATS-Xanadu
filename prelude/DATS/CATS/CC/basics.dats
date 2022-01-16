(* ****** ****** *)
(*
Basics for Xats2cc
// char, bool,
// ints, floats, string
*)
(* ****** ****** *)
#staload
UN = // for casting
"prelude/SATS/unsafe.sats"
(* ****** ****** *)
//
// prelude/bool.sats
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_bool_neg
{b0:bool}
( b0
: bool(b0)
)
: bool(~b0) = $exname()
//
impltmp bool_neg<> = XATS2CC_bool_neg
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_bool_add
{b1,b2:bool}
( b1
: bool(b1)
, b2
: bool(b2)
)
: bool(b1+b2) = $exname()
#extern
fun
XATS2CC_bool_mul
{b1,b2:bool}
( b1
: bool(b1)
, b2
: bool(b2)
)
: bool(b1*b2) = $exname()
//
impltmp
bool_add<> = XATS2CC_bool_add
impltmp
bool_mul<> = XATS2CC_bool_mul
//
(* ****** ****** *)
//
// prelude/char.sats
//
// [char] is a (small) number
//
(* ****** ****** *)
//
impltmp
char_make_sint<>
( i0 ) = $UN.cast01(i0)
//
impltmp
sint_make_char<>
( c0 ) = $UN.cast01(c0)
//
(* ****** ****** *)
#extern
fun
XATS2CC_char_eqzq
(c0: char): bool = $exname()
impltmp
char_eqzq<> = XATS2CC_char_eqzq
#extern
fun
XATS2CC_char_neqzq
(c0: char): bool = $exname()
impltmp
char_neqzq<> = XATS2CC_char_neqzq
(* ****** ****** *)
#extern
fun
XATS2CC_char_cmp
( c1: char
, c2: char): sint = $exname()
impltmp
char_cmp<> = XATS2CC_char_cmp
(* ****** ****** *)
#extern
fun
XATS2CC_char_equal
( c1: char
, c2: char): bool = $exname()
impltmp
char_equal<> = XATS2CC_char_equal
#extern
fun
XATS2CC_char_noteq
( c1: char
, c2: char): bool = $exname()
impltmp
char_noteq<> = XATS2CC_char_noteq
(* ****** ****** *)
//
// prelude/gint.sats
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gint_neg_sint
{i:int}
( x0
: sint(i)): sint(-i) = $exname()
impltmp
gint_neg_sint<> = XATS2CC_gint_neg_sint
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gint_abs_sint
{i:int}
( x0
: sint(i)): sint(abs(i)) = $exname()
impltmp
gint_abs_sint<> = XATS2CC_gint_abs_sint
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gint_succ_sint
{i:int}
( x0
: sint(i)): sint(i+1) = $exname()
#extern
fun
XATS2CC_gint_pred_sint
{i:int}
( x0
: sint(i)): sint(i-1) = $exname()
impltmp
gint_succ_sint<> = XATS2CC_gint_succ_sint
impltmp
gint_pred_sint<> = XATS2CC_gint_pred_sint
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gint_lt_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): bool(i<j) = $exname()
impltmp
gint_lt_sint_sint<> = XATS2CC_gint_lt_sint_sint
//
#extern
fun
XATS2CC_gint_gt_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): bool(i>j) = $exname()
impltmp
gint_gt_sint_sint<> = XATS2CC_gint_gt_sint_sint
//
#extern
fun
XATS2CC_gint_eq_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): bool(i=j) = $exname()
impltmp
gint_eq_sint_sint<> = XATS2CC_gint_eq_sint_sint
//
#extern
fun
XATS2CC_gint_lte_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): bool(i<=j) = $exname()
impltmp
gint_lte_sint_sint<> = XATS2CC_gint_lte_sint_sint
//
#extern
fun
XATS2CC_gint_gte_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): bool(i>=j) = $exname()
impltmp
gint_gte_sint_sint<> = XATS2CC_gint_gte_sint_sint
//
#extern
fun
XATS2CC_gint_neq_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): bool(i!=j) = $exname()
impltmp
gint_neq_sint_sint<> = XATS2CC_gint_neq_sint_sint
//
(* ****** ****** *)

#extern
fun
XATS2CC_gint_cmp_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j))
: sint(sgn(i-j)) = $exname((*self*))
impltmp
gint_cmp_sint_sint<> = XATS2CC_gint_cmp_sint_sint

(* ****** ****** *)
//
#extern
fun
XATS2CC_gint_add_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): sint( i+j ) = $exname()
impltmp
gint_add_sint_sint<> = XATS2CC_gint_add_sint_sint
#extern
fun
XATS2CC_gint_sub_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): sint( i-j ) = $exname()
impltmp
gint_sub_sint_sint<> = XATS2CC_gint_sub_sint_sint
//
#extern
fun
XATS2CC_gint_mul_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): sint( i*j ) = $exname()
impltmp
gint_mul_sint_sint<> = XATS2CC_gint_mul_sint_sint
#extern
fun
XATS2CC_gint_div_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): sint( i/j ) = $exname()
impltmp
gint_div_sint_sint<> = XATS2CC_gint_div_sint_sint
#extern
fun
XATS2CC_gint_mod_sint_sint
{i,j:int}
( x1
: sint(i)
, x2
: sint(j)): sint(mod(i,j)) = $exname()
impltmp
gint_mod_sint_sint<> = XATS2CC_gint_mod_sint_sint
//
(* ****** ****** *)
//
// prelude/gflt.sats
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_i_dflt
( x0: sint ): dflt = $exname()
impltmp
gflt_i_dflt<> = XATS2CC_gflt_i_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_neg_dflt
  ( x0: dflt ): dflt = $exname()
impltmp
gflt_neg_dflt<> = XATS2CC_gflt_neg_dflt
//
#extern
fun
XATS2CC_gflt_abs_dflt
  ( x0: dflt ): dflt = $exname()
impltmp
gflt_abs_dflt<> = XATS2CC_gflt_abs_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_succ_dflt
  ( x0: dflt ): dflt = $exname()
impltmp
gflt_succ_dflt<> = XATS2CC_gflt_succ_dflt
#extern
fun
XATS2CC_gflt_pred_dflt
  ( x0: dflt ): dflt = $exname()
impltmp
gflt_pred_dflt<> = XATS2CC_gflt_pred_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_lt_dflt_dflt
( x1: dflt, x2: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_gt_dflt_dflt
( x1: dflt, x2: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_eq_dflt_dflt
( x1: dflt, x2: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_lte_dflt_dflt
( x1: dflt, x2: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_gte_dflt_dflt
( x1: dflt, x2: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_neq_dflt_dflt
( x1: dflt, x2: dflt ): bool = $exname()
//
impltmp
gflt_lt_dflt_dflt<> = XATS2CC_gflt_lt_dflt_dflt
impltmp
gflt_gt_dflt_dflt<> = XATS2CC_gflt_gt_dflt_dflt
impltmp
gflt_eq_dflt_dflt<> = XATS2CC_gflt_eq_dflt_dflt
impltmp
gflt_lte_dflt_dflt<> = XATS2CC_gflt_lte_dflt_dflt
impltmp
gflt_gte_dflt_dflt<> = XATS2CC_gflt_gte_dflt_dflt
impltmp
gflt_neq_dflt_dflt<> = XATS2CC_gflt_neq_dflt_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_cmp_dflt_dflt
( x1: dflt, x2: dflt ): sint = $exname()
impltmp
gflt_cmp_dflt_dflt<> = XATS2CC_gflt_cmp_dflt_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_add_dflt_dflt
( x1: dflt, x2: dflt ): dflt = $exname()
#extern
fun
XATS2CC_gflt_sub_dflt_dflt
( x1: dflt, x2: dflt ): dflt = $exname()
#extern
fun
XATS2CC_gflt_mul_dflt_dflt
( x1: dflt, x2: dflt ): dflt = $exname()
#extern
fun
XATS2CC_gflt_div_dflt_dflt
( x1: dflt, x2: dflt ): dflt = $exname()
//
impltmp
gflt_add_dflt_dflt<> = XATS2CC_gflt_add_dflt_dflt
impltmp
gflt_sub_dflt_dflt<> = XATS2CC_gflt_sub_dflt_dflt
impltmp
gflt_mul_dflt_dflt<> = XATS2CC_gflt_mul_dflt_dflt
impltmp
gflt_div_dflt_dflt<> = XATS2CC_gflt_div_dflt_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_lt_dflt_sint
( x0: dflt, y0: sint ): bool = $exname()
#extern
fun
XATS2CC_gflt_gt_dflt_sint
( x0: dflt, y0: sint ): bool = $exname()
#extern
fun
XATS2CC_gflt_eq_dflt_sint
( x0: dflt, y0: sint ): bool = $exname()
#extern
fun
XATS2CC_gflt_lte_dflt_sint
( x0: dflt, y0: sint ): bool = $exname()
#extern
fun
XATS2CC_gflt_gte_dflt_sint
( x0: dflt, y0: sint ): bool = $exname()
#extern
fun
XATS2CC_gflt_neq_dflt_sint
( x0: dflt, y0: sint ): bool = $exname()
#extern
fun
XATS2CC_gflt_cmp_dflt_sint
( x0: dflt, y0: sint ): sint = $exname()
//
impltmp
gflt_lt_dflt_sint<> = XATS2CC_gflt_lt_dflt_sint
impltmp
gflt_gt_dflt_sint<> = XATS2CC_gflt_gt_dflt_sint
impltmp
gflt_eq_dflt_sint<> = XATS2CC_gflt_eq_dflt_sint
impltmp
gflt_lte_dflt_sint<> = XATS2CC_gflt_lte_dflt_sint
impltmp
gflt_gte_dflt_sint<> = XATS2CC_gflt_gte_dflt_sint
impltmp
gflt_neq_dflt_sint<> = XATS2CC_gflt_neq_dflt_sint
//
impltmp
gflt_cmp_dflt_sint<> = XATS2CC_gflt_cmp_dflt_sint
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_lt_sint_dflt
( x0: sint, y0: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_gt_sint_dflt
( x0: sint, y0: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_eq_sint_dflt
( x0: sint, y0: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_lte_sint_dflt
( x0: sint, y0: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_gte_sint_dflt
( x0: sint, y0: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_neq_sint_dflt
( x0: sint, y0: dflt ): bool = $exname()
#extern
fun
XATS2CC_gflt_cmp_sint_dflt
( x0: sint, y0: dflt ): sint = $exname()
//
impltmp
gflt_lt_sint_dflt<> = XATS2CC_gflt_lt_sint_dflt
impltmp
gflt_gt_sint_dflt<> = XATS2CC_gflt_gt_sint_dflt
impltmp
gflt_eq_sint_dflt<> = XATS2CC_gflt_eq_sint_dflt
impltmp
gflt_lte_sint_dflt<> = XATS2CC_gflt_lte_sint_dflt
impltmp
gflt_gte_sint_dflt<> = XATS2CC_gflt_gte_sint_dflt
impltmp
gflt_neq_sint_dflt<> = XATS2CC_gflt_neq_sint_dflt
//
impltmp
gflt_cmp_sint_dflt<> = XATS2CC_gflt_cmp_sint_dflt
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_add_dflt_sint
( x0: dflt, y0: sint ): dflt = $exname()
#extern
fun
XATS2CC_gflt_sub_dflt_sint
( x0: dflt, y0: sint ): dflt = $exname()
#extern
fun
XATS2CC_gflt_mul_dflt_sint
( x0: dflt, y0: sint ): dflt = $exname()
#extern
fun
XATS2CC_gflt_div_dflt_sint
( x0: dflt, y0: sint ): dflt = $exname()
//
impltmp
gflt_add_dflt_sint<> = XATS2CC_gflt_add_dflt_sint
impltmp
gflt_sub_dflt_sint<> = XATS2CC_gflt_sub_dflt_sint
impltmp
gflt_mul_dflt_sint<> = XATS2CC_gflt_mul_dflt_sint
impltmp
gflt_div_dflt_sint<> = XATS2CC_gflt_div_dflt_sint
//
(* ****** ****** *)
//
#extern
fun
XATS2CC_gflt_add_sint_dflt
( x0: sint, y0: dflt ): dflt = $exname()
#extern
fun
XATS2CC_gflt_sub_sint_dflt
( x0: sint, y0: dflt ): dflt = $exname()
#extern
fun
XATS2CC_gflt_mul_sint_dflt
( x0: sint, y0: dflt ): dflt = $exname()
#extern
fun
XATS2CC_gflt_div_sint_dflt
( x0: sint, y0: dflt ): dflt = $exname()
//
impltmp
gflt_add_sint_dflt<> = XATS2CC_gflt_add_sint_dflt
impltmp
gflt_sub_sint_dflt<> = XATS2CC_gflt_sub_sint_dflt
impltmp
gflt_mul_sint_dflt<> = XATS2CC_gflt_mul_sint_dflt
impltmp
gflt_div_sint_dflt<> = XATS2CC_gflt_div_sint_dflt
//
(* ****** ****** *)
//
// prelude/string.sats
//
(* ****** ****** *)
impltmp
string_vt2t<> =
XATS2CC_string_vt2t
where
{
#extern
fun
XATS2CC_string_vt2t
(cs
:string_vt):string = $exname()
}
(* ****** ****** *)

impltmp
stropt_nilq<> =
XATS2CC_stropt_nilq
where
{
#extern
fun
XATS2CC_stropt_nilq
(opt: stropt): bool = $exname()
}
impltmp
stropt_consq<> =
XATS2CC_stropt_consq
where
{
#extern
fun
XATS2CC_stropt_consq
(opt: stropt): bool = $exname()
}

(* ****** ****** *)
impltmp
string_lt<> =
XATS2CC_string_lt
where
{
#extern
fun
XATS2CC_string_lt
(x1: string
,x2: string): bool = $exname()
}
impltmp
string_gt<> =
XATS2CC_string_gt
where
{
#extern
fun
XATS2CC_string_gt
(x1: string
,x2: string): bool = $exname()
}
impltmp
string_eq<> =
XATS2CC_string_eq
where
{
#extern
fun
XATS2CC_string_eq
(x1: string
,x2: string): bool = $exname()
}
(* ****** ****** *)
impltmp
string_lte<> =
XATS2CC_string_lte
where
{
#extern
fun
XATS2CC_string_lte
(x1: string
,x2: string): bool = $exname()
}
impltmp
string_gte<> =
XATS2CC_string_gte
where
{
#extern
fun
XATS2CC_string_gte
(x1: string
,x2: string): bool = $exname()
}
impltmp
string_neq<> =
XATS2CC_string_neq
where
{
#extern
fun
XATS2CC_string_neq
(x1: string
,x2: string): bool = $exname()
}
(* ****** ****** *)
impltmp
string_cmp<> =
XATS2CC_string_cmp
where
{
#extern
fun
XATS2CC_string_cmp
(x1: string
,x2: string): sint = $exname()
}
(* ****** ****** *)
impltmp
string_head_opt<> =
XATS2CC_string_head_opt
where
{
#extern
fun
XATS2CC_string_head_opt
(cs: string): char = $exname()
}
(* ****** ****** *)
impltmp
string_head_raw<> =
XATS2CC_string_head_raw
where
{
#extern
fun
XATS2CC_string_head_raw
(cs: string): char = $exname()
}
(* ****** ****** *)
impltmp
string_tail_raw<> =
XATS2CC_string_tail_raw
where
{
#extern
fun
XATS2CC_string_tail_raw
(cs: string): string = $exname()
}
(* ****** ****** *)
impltmp
string_length<> =
XATS2CC_string_length
where
{
#extern
fun
XATS2CC_string_length
(cs : string) : nint = $exname()
}
//
impltmp
string_vt_length<> =
XATS2CC_string_vt_length
where
{
#extern
fun
XATS2CC_string_vt_length
(cs : !string_vt) : nint = $exname()
}
impltmp
string_vt_length1<> =
XATS2CC_string_vt_length1
where
{
#extern
fun
XATS2CC_string_vt_length1
(cs : !string_vt) : nint = $exname()
}
//
(* ****** ****** *)
impltmp
string_get_at<> =
XATS2CC_string_get_at
where
{
#extern
fun
XATS2CC_string_get_at
( cs
: string, i0: sint): char
= $exname((*self*))
}
(* ****** ****** *)
impltmp
string_forall<>(cs) =
let
//
#extern
fun
XATS2CC_string_forall_cfr
( cs: string
, f0: (cgtz) -<cfr> bool): bool
= $exname((*self*))
//
in
XATS2CC_string_forall_cfr
( cs
, lam(c0) => forall$test<cgtz>(c0))
end // end of [string_forall]
(* ****** ****** *)
impltmp
strtmp_vt_alloc<> =
XATS2CC_strtmp_vt_alloc
where
{
#extern
fun
XATS2CC_strtmp_vt_alloc
(bsz: sint) : strtmp0_vt = $exname()
}
(* ****** ****** *)
impltmp
strtmp_vt_set_at<> =
XATS2CC_strtmp_vt_set_at
where
{
#extern
fun
XATS2CC_strtmp_vt_set_at
( cs:strtmp0_vt
, i0:sint, c0:char): void = $exname()
}
(* ****** ****** *)
impltmp
string_vt_forall0<>(cs) =
let
//
#extern
fun
XATS2CC_string_vt_forall_cfr
( cs: ~string_vt
, f0: (cgtz) -<cfr> bool): bool
= $exname((*self*))
//
in
XATS2CC_string_vt_forall_cfr
( cs
, lam(c0) => forall0$test<cgtz>(c0))
end // end of [string_vt_forall0]
(* ****** ****** *)
impltmp
string_vt_forall1<>(cs) =
let
//
#extern
fun
XATS2CC_string_vt_forall_cfr
( cs: !string_vt
, f0: (cgtz) -<cfr> bool): bool
= $exname((*self*))
//
in
XATS2CC_string_vt_forall_cfr
( cs
, lam(c0) => forall1$test<cgtz>(c0))
end // end of [string_vt_forall1]
(* ****** ****** *)

(* end of [XATS2CC_basics.dats] *)
