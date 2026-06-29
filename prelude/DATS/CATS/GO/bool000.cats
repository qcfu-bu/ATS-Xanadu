////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/bool000.cats — typed Go primitive floor for [bool].
// Mirrors CATS/JS/bool000.cats, but TYPED (bool -> Go bool).  The ordering
// ops on bool follow Go's: false < true (Go has no `<` on bool, so compare
// the int encodings).  [bool_print] is NOT here -- it is pure-ATS in the arm.
//
////////////////////////////////////////////////////////////////////////.
//
// Go forbids `<`/`>` on bool, so rank via a tiny int encoding (false=0,true=1).
func xats2goBoolRank(b bool) int {
	if b {
		return 1
	}
	return 0
}
//
func XATS2GO_bool_lt(b1 bool, b2 bool) bool { return xats2goBoolRank(b1) < xats2goBoolRank(b2) }
func XATS2GO_bool_gt(b1 bool, b2 bool) bool { return xats2goBoolRank(b1) > xats2goBoolRank(b2) }
func XATS2GO_bool_lte(b1 bool, b2 bool) bool { return xats2goBoolRank(b1) <= xats2goBoolRank(b2) }
func XATS2GO_bool_gte(b1 bool, b2 bool) bool { return xats2goBoolRank(b1) >= xats2goBoolRank(b2) }
func XATS2GO_bool_eq(b1 bool, b2 bool) bool { return b1 == b2 }
func XATS2GO_bool_neq(b1 bool, b2 bool) bool { return b1 != b2 }
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_bool000.cats]
////////////////////////////////////////////////////////////////////////.
