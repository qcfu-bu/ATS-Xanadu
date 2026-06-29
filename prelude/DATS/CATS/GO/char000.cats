////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/char000.cats — typed Go primitive floor for [char] (Go `rune`).
// Mirrors CATS/JS/char000.cats.  ASCII surface: a char is an int8-range code
// point (char_add$sint wraps mod 256, matching the JS `%256`).
//
////////////////////////////////////////////////////////////////////////.
//
func XATS2GO_char_lt(c1 rune, c2 rune) bool { return c1 < c2 }
func XATS2GO_char_gt(c1 rune, c2 rune) bool { return c1 > c2 }
func XATS2GO_char_lte(c1 rune, c2 rune) bool { return c1 <= c2 }
func XATS2GO_char_gte(c1 rune, c2 rune) bool { return c1 >= c2 }
func XATS2GO_char_eq(c1 rune, c2 rune) bool { return c1 == c2 }
func XATS2GO_char_neq(c1 rune, c2 rune) bool { return c1 != c2 }
//
// char = int8: char_add$sint wraps mod 256 (== JS (c1+i2)%256).
func XATS2GO_char_add$sint(c1 rune, i2 int) rune { return rune((int(c1) + i2) % 256) }
func XATS2GO_char_sub$char(c1 rune, c2 rune) int { return int(c1) - int(c2) }
//
// void-as-value (returns any/nil), like the other prelude prints.
func XATS2GO_char_print(c0 rune) any {
	XATS2GO_the_print_store = append(XATS2GO_the_print_store, string(c0))
	return nil
}
//
// sint<->char conversions (explicit since Go int and rune are distinct types).
func XATS2GO_sint_make_char(ch rune) int { return int(ch) }
func XATS2GO_char_make_sint(i0 int) rune { return rune(i0) }
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_char000.cats]
////////////////////////////////////////////////////////////////////////.
