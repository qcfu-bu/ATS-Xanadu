////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/xtop000.cats — the SELF-CONTAINED GO runtime floor (print stores +
// flush + console_log).  The typed Go analog of CATS/JS/xtop000.cats; this is
// the I/O primitive floor that makes a CATS/GO program self-contained (it does
// NOT share runtime/xatsgo's store).
//
// Needs `import ("fmt"; "strings")` in the emitted package.
//
////////////////////////////////////////////////////////////////////////.
//
// console_log is generic in ATS (console_log{t0}(x0)); fmt.Println(any) is the
// faithful Go form (prints the value + a trailing newline, == JS console.log).
func XATS2GO_console_log(x0 any) { fmt.Println(x0) }
//
// the three output stores (mirrors XATS2JS_the_{print,prout,prerr}_store).
var XATS2GO_the_print_store []string
var XATS2GO_the_prout_store []string
var XATS2GO_the_prerr_store []string
//
func XATS2GO_the_print_store_clear() { XATS2GO_the_print_store = XATS2GO_the_print_store[:0] }
//
// flush: join the store into one string, clear it, return the text.
func XATS2GO_the_print_store_flush() string {
	cs := strings.Join(XATS2GO_the_print_store, "")
	XATS2GO_the_print_store = XATS2GO_the_print_store[:0]
	return cs
}
func XATS2GO_the_prout_store_flush() string {
	cs := strings.Join(XATS2GO_the_prout_store, "")
	XATS2GO_the_prout_store = XATS2GO_the_prout_store[:0]
	return cs
}
func XATS2GO_the_prerr_store_flush() string {
	cs := strings.Join(XATS2GO_the_prerr_store, "")
	XATS2GO_the_prerr_store = XATS2GO_the_prerr_store[:0]
	return cs
}
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_xtop000.cats]
////////////////////////////////////////////////////////////////////////.
