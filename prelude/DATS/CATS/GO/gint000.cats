////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/gint000.cats — the typed Go primitive floor for [sint].
// Mirrors CATS/JS/gint000.cats, but TYPED (sint -> Go int, uint -> Go int,
// bool -> Go bool).  These are the only hand-written Go for integers; all
// the prelude's int-using ATS code is COMPILED to Go by xats2go and bottoms
// out here.  The print store is the package-level XATS2GO_the_print_store
// (defined in the GO precats, mirroring XATS2JS_the_print_store).
//
// NOTE (typed-intrep1 redesign): emitted prelude code now carries concrete
// Go types, so these typed signatures link without `any`-boxing.
//
////////////////////////////////////////////////////////////////////////.
//
func XATS2GO_sint_neg(i1 int) int { return -i1 }
//
func XATS2GO_sint_lt$sint(i1 int, i2 int) bool { return i1 < i2 }
func XATS2GO_sint_gt$sint(i1 int, i2 int) bool { return i1 > i2 }
func XATS2GO_sint_lte$sint(i1 int, i2 int) bool { return i1 <= i2 }
func XATS2GO_sint_gte$sint(i1 int, i2 int) bool { return i1 >= i2 }
func XATS2GO_sint_eq$sint(i1 int, i2 int) bool { return i1 == i2 }
func XATS2GO_sint_neq$sint(i1 int, i2 int) bool { return i1 != i2 }
//
func XATS2GO_sint_add$sint(i1 int, i2 int) int { return i1 + i2 }
func XATS2GO_sint_sub$sint(i1 int, i2 int) int { return i1 - i2 }
func XATS2GO_sint_mul$sint(i1 int, i2 int) int { return i1 * i2 }
// Go integer division truncates toward zero (== JS Math.trunc(i1/i2)).
func XATS2GO_sint_div$sint(i1 int, i2 int) int { return i1 / i2 }
func XATS2GO_sint_mod$sint(i1 int, i2 int) int { return i1 % i2 }
//
func XATS2GO_sint_print(i0 int) {
	XATS2GO_the_print_store = append(XATS2GO_the_print_store, strconv.Itoa(i0))
}
func XATS2GO_uint_print(u0 int) {
	XATS2GO_the_print_store = append(XATS2GO_the_print_store, strconv.Itoa(u0))
}
//
func XATS2GO_sint_to$uint(i0 int) int {
	if i0 >= 0 {
		return i0
	}
	panic("XATS2GO_sint_to$uint: i0 = " + strconv.Itoa(i0))
}
func XATS2GO_uint_to$sint(u0 int) int {
	if u0 >= 0 {
		return u0
	}
	panic("XATS2GO_uint_to$sint: u0 = " + strconv.Itoa(u0))
}
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_gint000.cats]
////////////////////////////////////////////////////////////////////////.
