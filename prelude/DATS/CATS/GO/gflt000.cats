////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/gflt000.cats — typed Go primitive floor for [dflt] (Go `float64`).
// Mirrors CATS/JS/gflt000.cats.  Needs `import ("math"; "strconv")`.
//
// FLOAT-PRINT PARITY NOTE: [dflt_print] uses strconv.FormatFloat(f,'g',-1,64)
// -- the shortest round-trippable form, which matches JS Number.toString() for
// the common range (e.g. 2.0->"2", 1.5->"1.5", 3.14->"3.14").  Exotic
// magnitudes near the fixed/exponential boundary (|x| < 1e-6 or >= 1e21) can
// differ in notation from JS; tighten here if the suite ever forces one.
//
// ROUND PARITY: JS Math.round rounds half toward +Inf (Math.round(-1.5) = -1),
// NOT away-from-zero like Go's math.Round.  Replicated as math.Floor(x + 0.5).
//
////////////////////////////////////////////////////////////////////////.
//
// sint -> dflt coercion (g_si<dflt>).
func XATS2GO_si2dflt(i1 int) float64 { return float64(i1) }
//
func XATS2GO_dflt_neg(f1 float64) float64 { return -f1 }
func XATS2GO_dflt_abs(f1 float64) float64 { return math.Abs(f1) }
func XATS2GO_dflt_sqrt(f1 float64) float64 { return math.Sqrt(f1) }
func XATS2GO_dflt_cbrt(f1 float64) float64 { return math.Cbrt(f1) }
//
func XATS2GO_dflt_lt$dflt(f1 float64, f2 float64) bool { return f1 < f2 }
func XATS2GO_dflt_gt$dflt(f1 float64, f2 float64) bool { return f1 > f2 }
func XATS2GO_dflt_lte$dflt(f1 float64, f2 float64) bool { return f1 <= f2 }
func XATS2GO_dflt_gte$dflt(f1 float64, f2 float64) bool { return f1 >= f2 }
func XATS2GO_dflt_eq$dflt(f1 float64, f2 float64) bool { return f1 == f2 }
func XATS2GO_dflt_neq$dflt(f1 float64, f2 float64) bool { return f1 != f2 }
//
// -1 / 0 / 1 (== JS XATS2JS_dflt_cmp$dflt).
func XATS2GO_dflt_cmp$dflt(f1 float64, f2 float64) int {
	if f1 < f2 {
		return -1
	}
	if f1 > f2 {
		return 1
	}
	return 0
}
//
func XATS2GO_dflt_add$dflt(f1 float64, f2 float64) float64 { return f1 + f2 }
func XATS2GO_dflt_sub$dflt(f1 float64, f2 float64) float64 { return f1 - f2 }
func XATS2GO_dflt_mul$dflt(f1 float64, f2 float64) float64 { return f1 * f2 }
func XATS2GO_dflt_div$dflt(f1 float64, f2 float64) float64 { return f1 / f2 }
// JS `%` on floats == math.Mod (truncated remainder, sign of dividend).
func XATS2GO_dflt_mod$dflt(f1 float64, f2 float64) float64 { return math.Mod(f1, f2) }
//
// void-as-value (returns any/nil), like the other prelude prints.
func XATS2GO_dflt_print(f0 float64) any {
	XATS2GO_the_print_store = append(XATS2GO_the_print_store, strconv.FormatFloat(f0, 'g', -1, 64))
	return nil
}
//
func XATS2GO_dflt_ceil(df float64) float64  { return math.Ceil(df) }
func XATS2GO_dflt_floor(df float64) float64 { return math.Floor(df) }
// JS Math.round: half toward +Inf, NOT away-from-zero.
func XATS2GO_dflt_round(df float64) float64 { return math.Floor(df + 0.5) }
func XATS2GO_dflt_trunc(df float64) float64 { return math.Trunc(df) }
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_gflt000.cats]
////////////////////////////////////////////////////////////////////////.
