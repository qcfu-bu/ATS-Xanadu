// Package xatsgo is the minimal Go runtime for the xats2go backend (M1).
//
// It mirrors, byte-for-byte at the OBSERVABLE-OUTPUT level, the subset of the
// JS backend runtime that the M1 walking-skeleton program (test01) needs:
//
//   - the print store (srcgen2_prelude.js: XATS2JS_the_print_store +
//     XATS2JS_strn_print + XATS2JS_the_print_store_flush)
//   - the_print_store_log (prelude/DATS/CATS/JS/xtop000.dats:
//     the_print_store_log() = console_log(the_print_store_flush()))
//   - console_log (== console.log, which appends a trailing '\n')
//   - the low-level string combinators XATSSTRN / XATSSTR0 (xats2js_js1emit.js)
//
// The JS reference output for test01 is the 28-byte string
// "Hello from [test01_xats2go]!\n" pushed by strn_print, then flushed and
// printed via console.log which appends one more '\n' -> two trailing '\n'.
// These functions reproduce exactly that.
//
// Representation note (Regime A, M1): emitted code is uniformly `any`-typed
// (interface{}), so the runtime entry points take/return `any` where the
// emitter expects first-class function values. This is the M1 skeleton; M2
// introduces concrete Go types per PLAN.md §4.
package xatsgo

import (
	"fmt"
	"math"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"
)

// thePrintStore mirrors XATS2JS_the_print_store: a growable buffer that
// strn_print appends to and the_print_store_flush drains.
var thePrintStore []string

// XATS2JS_strn_print pushes cs onto the print store (no output yet).
// Mirrors srcgen2_prelude.js: XATS2JS_strn_print(cs){ store.push(cs) }.
func XATS2JS_strn_print(cs string) {
	thePrintStore = append(thePrintStore, cs)
}

// XATS2JS_the_print_store_flush joins + clears the store, returning the text.
// Mirrors srcgen2_prelude.js: join("") then length=0.
func XATS2JS_the_print_store_flush() string {
	cs := strings.Join(thePrintStore, "")
	thePrintStore = thePrintStore[:0]
	return cs
}

// XATS2GO_flush_pending drains top-level `prints(...)` output at program exit.
// Unlike console_log(the_print_store_flush()), this does not append its own
// newline; the source-level print text is written byte-for-byte.
func XATS2GO_flush_pending() {
	if len(thePrintStore) != 0 {
		fmt.Print(XATS2JS_the_print_store_flush())
	}
}

// XATS2JS_console_log mirrors console.log: print the value followed by a
// single newline. (Go's fmt.Println appends exactly one '\n', matching
// node's console.log for a single string argument.)
func XATS2JS_console_log(x any) {
	fmt.Println(x)
}

// -- prelude-level entry points (named by their ATS symbol) -----------------
//
// The emitter resolves an I1INStimp to its d2cst and emits a reference to the
// matching runtime function below (see go1emit_utils0.dats: d2cstgo1). Each is
// a first-class function value of `any` arity so the emitted I1INSdapp can
// apply it.

// Xats_strn_print is the prelude `strn_print(strn): void`.
// It accepts `any` (the emitted argument is XATSSTRN(...) -> string).
// Naming: the emitter routes an I1INStimp's d2cst named `strn_print` to
// `xatsgo.Xats_strn_print` (go1emit_utils0.dats: d2cstgo1 prepends "Xats_").
var Xats_strn_print = func(cs any) any {
	XATS2JS_strn_print(cs.(string))
	return XATSNIL()
}

// Xats_the_print_store_log is the prelude `the_print_store_log(): void`, i.e.
// console_log(the_print_store_flush()).
var Xats_the_print_store_log = func() any {
	XATS2JS_console_log(XATS2JS_the_print_store_flush())
	return XATSNIL()
}

// Xats_the_print_store_flush and Xats_console_log are the first-class prelude
// names used when source calls `console_log(the_print_store_flush())` directly.
var Xats_the_print_store_flush = func() string {
	return XATS2JS_the_print_store_flush()
}

var Xats_console_log = func(x any) any {
	XATS2JS_console_log(x)
	return XATSNIL()
}

// -- low-level value combinators (mirror xats2js_js1emit.js) ----------------

// XATSSTRN is the string-literal combinator (identity on the Go string).
// Mirrors `let XATSSTRN = (cs) => cs` semantics.
func XATSSTRN(cs string) string { return cs }

// XATSSTR0 is the evaluated-string combinator (identity).
func XATSSTR0(cs string) string { return cs }

// XATSNIL is the unit value (ATS `()` / I1Vnil). Represented as nil `any`.
func XATSNIL() any { return nil }

// XATSTOP0 is the "topmost"/omitted value (ATS `_` in value position, I1Vtop).
// The JS backend defines `XATSTOP0 = undefined`; the Go analog is the unit/nil
// `any`. It is a placeholder the type checker filled; reading it is only valid
// where ATS proved the value is never demanded, so nil is the faithful image.
func XATSTOP0() any { return nil }

// XatsA0Ref is the boxed cell for ATS a0ref. These are real prelude
// primitives, not generated-local placeholders: if emitted code references a
// missing ref variable, Go compilation should still fail at that variable.
type XatsA0Ref struct {
	val any
}

var Xats_a0ref_make_1val = func(x any) any {
	return &XatsA0Ref{val: x}
}

var Xats_a0ref_get = func(r any) any {
	return r.(*XatsA0Ref).val
}

var Xats_a0ref_set = func(r any, x any) any {
	r.(*XatsA0Ref).val = x
	return XATSNIL()
}

// ===========================================================================
// LAZY — call-by-need (memoized) and call-by-name thunks
// ===========================================================================
//
// Mirrors the JS runtime combinators (xats2js_js1emit.js):
//
//	XATS000_l0azy(lfun) = [0, lfun]                       // unforced memo cell
//	XATS000_dl0az(l0az) = force-once-then-cache(l0az)     // $eval / `!lz`
//	XATS000_l1azy(lfun) = lfun                            // call-by-name (no memo)
//	XATS000_dl1az(l1az) = l1az(1)                         // call the thunk
//
// l0azy = a MEMOIZED thunk: the thunk runs at most ONCE; its result is cached
// and every later force returns the cached value (the observable: a side-effect
// in the thunk fires exactly once even when forced repeatedly).  l1azy = plain
// call-by-name: the thunk is re-run on every force (no caching).
//
// Linear cleanup (the [frees] of l1azy / the $free of lazy_vt_free) is a no-op
// under Go's GC, exactly as the JS backend treats XATS000_free as a no-op.

// XatsLazy is a memoized (call-by-need) thunk cell. Once forced, [forced] is
// set and [val] holds the cached result; [thunk] is the deferred computation.
type XatsLazy struct {
	forced bool
	val    any
	thunk  func() any
}

// Xats_l0azy wraps a thunk into an unforced memo cell (I1INSl0azy). Mirrors
// XATS000_l0azy: the thunk is NOT run here, only captured.
func Xats_l0azy(thunk func() any) *XatsLazy { return &XatsLazy{thunk: thunk} }

// Xats_dl0az forces a memo cell (I1INSdl0az / `$eval` / `!lz`): runs the thunk
// the FIRST time and caches the result; later forces return the cache. Mirrors
// XATS000_dl0az (memoization).
func Xats_dl0az(l *XatsLazy) any {
	if !l.forced {
		l.val = l.thunk()
		l.forced = true
	}
	return l.val
}

// Xats_l1azy is call-by-name (I1INSl1azy): the thunk itself is the lazy value;
// it is NOT memoized. Mirrors XATS000_l1azy = identity.
func Xats_l1azy(thunk func() any) func() any { return thunk }

// Xats_dl1az calls a call-by-name thunk (I1INSdl1az): re-runs it every time.
// Mirrors XATS000_dl1az = l1az(1).
func Xats_dl1az(f func() any) any { return f() }

// Xats_fold is the open-constructor folding no-op (I1INSfold). The JS runtime
// XATS000_fold returns null; here we yield the argument's value unchanged (a
// fold is a static/representation operation with no runtime effect).
func Xats_fold(v any) any { return v }

// Xats_free is the malloc-free no-op (I1INSfree). Irrelevant under Go's GC,
// exactly as the JS runtime XATS000_free is a no-op returning null.
func Xats_free(v any) any { return nil }

// ===========================================================================
// M2.7 — DATATYPES (datacons)
// ===========================================================================
//
// Every datatype value is a single boxed runtime type: a *XatsCon (datatypes
// are uniformly heap-boxed in ATS, so the layout-correct choice is a boxed
// pointer). This mirrors the JS backend's tag+array model (XATSCAPP stores
// [ctag, arg0, arg1, ...]) but separates the tag from the args:
//   - Tag  is the constructor's ctag (d2con_get_ctag); the JS backend keeps it
//     at slot 0 of the array, here it is its own field.
//   - Args holds ONLY the value arguments (proof args are erased upstream, like
//     tuples skip npf), in source order. A nullary constructor has Args == nil.
//
// Construction  I1INSdapp(I1Vcon(dcon), vs) -> &XatsCon{Tag: ctag, Args: ...}.
// Tag test      (case clause)               -> v.Tag == ctag.
// Projection    I1INSpcon(lab, v)/I1Vp1cn   -> v.Args[lab] (typed via .(T)).
// Field set     I1Vlpcn(lab, v) = rhs       -> v.Args[lab] = rhs (mutation).
type XatsCon struct {
	Tag  int
	Args []any
	// Name is the constructor NAME, populated ONLY for EXCEPTION constructors
	// (excptcon), which the front-end all assigns the sentinel ctag -1 (they are
	// an OPEN/extensible sum, unlike a closed datatype whose constructors get
	// distinct ctags 0,1,...). A try/with handler distinguishes two exception
	// types by Name (mirrors the JS backend's XATSCTAG(name, ctag) which compares
	// BOTH name and ctag). For ordinary datatype values Name is the zero "".
	Name string
}

func Xats_as_con(x any) *XatsCon {
	return x.(*XatsCon)
}

// Xats_list_length: a prelude `list` is a *XatsCon — list_nil = Tag 0 (no
// args), list_cons = Tag 1 with Args[0]=head, Args[1]=tail. Walk the tail
// counting cons cells. (Mirrors XATS2JS_list_length.)
func Xats_list_length(xs *XatsCon) int {
	n := 0
	for xs != nil && xs.Tag != 0 {
		n++
		xs = xs.Args[1].(*XatsCon)
	}
	return n
}

func xatsListNil(name string) *XatsCon {
	return &XatsCon{Tag: 0, Name: name}
}

func xatsListCons(name string, x any, xs *XatsCon) *XatsCon {
	return &XatsCon{Tag: 1, Args: []any{x, xs}, Name: name}
}

func Xats_list_vt_make_1val(x1 any) *XatsCon {
	return xatsListCons("list_vt", x1, xatsListNil("list_vt"))
}

func Xats_list_vt_make_2val(x1 any, x2 any) *XatsCon {
	return xatsListCons("list_vt", x1, xatsListCons("list_vt", x2, xatsListNil("list_vt")))
}

func Xats_list_vt_make_3val(x1 any, x2 any, x3 any) *XatsCon {
	return xatsListCons("list_vt", x1, xatsListCons("list_vt", x2, xatsListCons("list_vt", x3, xatsListNil("list_vt"))))
}

func Xats_list_vt2t(xs *XatsCon) *XatsCon {
	if xs != nil {
		xs.Name = "list"
	}
	return xs
}

// Xats_list_reverse: a fresh list with the cons cells in reverse order.
func Xats_list_reverse(xs *XatsCon) *XatsCon {
	acc := &XatsCon{Tag: 0}
	for xs != nil && xs.Tag != 0 {
		acc = &XatsCon{Tag: 1, Args: []any{xs.Args[0], acc}}
		xs = xs.Args[1].(*XatsCon)
	}
	return acc
}

// Xats_gseq_folditm is the current runtime fallback for the list-counting
// gseq_folditm surface used by the self-hosting rung test. General user
// folditm$fopr instances should eventually be emitted as concrete template
// bodies by the backend instead of routing through this fixed runtime hook.
func Xats_gseq_folditm(xs *XatsCon, r0 int) int {
	acc := r0
	for xs != nil && xs.Tag != 0 {
		acc++
		xs = xs.Args[1].(*XatsCon)
	}
	return acc
}

// Xats_cfail mirrors XATS2JS_XATS000_cfail: the match-failure sentinel for a
// non-exhaustive case/switch. The M2.3 emitter inlines a literal
// `panic("xats2go: XATS000_cfail")` in a switch's `default:` arm instead of
// calling this (a literal panic is a Go TERMINATING statement, so a return-
// position switch is seen as exhaustive). This named entry is kept as the
// documented sentinel and for M2.7's datacon match-failure paths; it returns
// `any` so it can also appear in value position.
func Xats_cfail() any {
	panic("xats2go: XATS000_cfail (non-exhaustive pattern match)")
}

// ===========================================================================
// M2.1 — SCALAR PRINTS + PRIMOPS
// ===========================================================================
//
// These mirror the JS backend's OBSERVABLE bytes (srcgen2_prelude.js):
//   - the per-type prints push a string onto the print store (no output yet);
//     the_print_store_log flushes + console.log's it (one trailing '\n').
//   - the arithmetic/compare fns are the `any`-typed FALLBACK for the
//     primops; the emitter prefers NATIVE Go operators when both operands
//     are concretely-typed scalars (see go1emit_styp0.dats), and references
//     these only for the boxed / higher-order path. They are kept here so
//     the op-temp's `_ = xatsgo.Xats_<name>` binding always resolves.

// -- per-type prints (push onto the store) ----------------------------------

// Xats_sint_print mirrors XATS2JS_sint_print: i0.toString() pushed.
var Xats_sint_print = func(i0 any) any {
	thePrintStore = append(thePrintStore, strconv.Itoa(i0.(int)))
	return XATSNIL()
}

// Xats_bool_print mirrors the prelude bool_print: "true"/"false" pushed.
var Xats_bool_print = func(b0 any) any {
	if b0.(bool) {
		thePrintStore = append(thePrintStore, "true")
	} else {
		thePrintStore = append(thePrintStore, "false")
	}
	return XATSNIL()
}

// Xats_char_print mirrors XATS2JS_char_print: String.fromCharCode(c0) pushed.
// The emitted char literal is a Go rune; print its single character.
var Xats_char_print = func(c0 any) any {
	thePrintStore = append(thePrintStore, string(rune(c0.(int32))))
	return XATSNIL()
}

// Xats_XATS2GO_gochar_esc returns the body of a Go rune literal, without the
// surrounding single quotes. It is used by the self-hosted Go emitter when an
// evaluated ATS char value must be printed as Go source.
var Xats_XATS2GO_gochar_esc = func(c0 any) any {
	var r rune
	switch v := c0.(type) {
	case int32:
		r = rune(v)
	case int:
		r = rune(v)
	default:
		r = []rune(fmt.Sprint(v))[0]
	}
	q := strconv.QuoteRune(r)
	if len(q) >= 2 {
		return q[1 : len(q)-1]
	}
	return q
}

// Xats_XATS2GO_chrfpr writes one raw character to a FILR-like writer. It is
// the Go-host counterpart of the JS shim adapter used while self-host smoke
// still runs through the xats2js-generated compiler bundle.
var Xats_XATS2GO_chrfpr = func(filr any, c0 any) any {
	var r rune
	switch v := c0.(type) {
	case int32:
		r = rune(v)
	case int:
		r = rune(v)
	default:
		rs := []rune(fmt.Sprint(v))
		if len(rs) == 0 {
			return XATSNIL()
		}
		r = rs[0]
	}
	if w, ok := filr.(interface{ Write([]byte) (int, error) }); ok {
		_, _ = w.Write([]byte(string(r)))
	}
	return XATSNIL()
}

// Xats_dflt_print mirrors XATS2JS_dflt_print: f0.toString() pushed, where
// .toString() is JS Number formatting -> see XatsFloatToString (JS-compatible).
var Xats_dflt_print = func(f0 any) any {
	thePrintStore = append(thePrintStore, XatsFloatToString(f0.(float64)))
	return XATSNIL()
}

// XatsFloatToString reproduces JavaScript's Number.prototype.toString() for
// the finite/decimal range the scalar tests exercise. Go's 'g' shortest
// round-trip representation matches JS for ordinary decimals (e.g. 3.75 ->
// "3.75", -2 -> "-2"); the exponent threshold/format differs only for very
// large/small magnitudes which the M2.1 tests avoid.
func XatsFloatToString(f float64) string {
	if math.IsInf(f, 1) {
		return "Infinity"
	}
	if math.IsInf(f, -1) {
		return "-Infinity"
	}
	if math.IsNaN(f) {
		return "NaN"
	}
	// shortest decimal that round-trips, like JS for ordinary magnitudes.
	return strconv.FormatFloat(f, 'g', -1, 64)
}

// -- string ops -------------------------------------------------------------

// Xats_strn_append mirrors XATS2JS_strn_append: string concatenation (`+`).
var Xats_strn_append = func(s1 any, s2 any) any {
	return s1.(string) + s2.(string)
}

// Xats_strn_length mirrors XATS2JS_strn_length: number of bytes (JS string
// .length over the prelude's char model).
//
// CONVENTION (soundness): a scalar-QUERY prelude fn returns its CONCRETE Go
// scalar type, NOT `any` -- exactly like Xats_sint_abs / Xats_list_length /
// Xats_gseq_folditm (all `int`). This matters because the result flows into a
// NATIVE Go operator (e.g. `strn_length(s) >= n`), and Go's ordered/arith
// operators (`<`,`>`,`+`,...) are undefined on `interface{}`. Returning the
// concrete `int` makes the emitted `(a OP b)` type-check with zero emitter
// change. (Equality `==`/`!=` would tolerate `any`, but ordered ops do not --
// this was the M5-probe blocker (a): `strn_length`'s `any` return made
// `int >= any` a compile error.) Only OP-FALLBACK fns (gint_*, sint_*, ...)
// stay `any`-returning, for first-class/higher-order use.
var Xats_strn_length = func(s0 any) int {
	return len(s0.(string))
}

// Xats_strn_get_at: the byte at index i of s, as a char (rune/int32) -- ATS
// strings are byte-indexed (C model). Matches `strn_get$at(s, i)` returning a
// char that the char_* ops then compare. (Runtime call; no native Go operator
// for indexing.)
var Xats_strn_get_at = func(s any, i any) any {
	return int32(s.(string)[i.(int)])
}

// Xats_strn_eq / Xats_strn_neq: any-typed fallbacks for string equality.
// goop_of_name inlines `=`/`!=` on strings to native Go `==`/`!=` (valid on
// Go strings), dropping the op-temp to a dead `_ =` suppressor; these back
// that suppressor and any first-class/higher-order use. XATSSTRN is identity,
// so the underlying Go strings compare exactly as in the JS backend.
var Xats_strn_eq = func(s1 any, s2 any) any { return s1.(string) == s2.(string) }
var Xats_strn_neq = func(s1 any, s2 any) any { return s1.(string) != s2.(string) }

// -- integer (sint) arithmetic / compare (any-typed fallback) ----------------

var Xats_sint_abs = func(i0 int) int {
	if i0 < 0 {
		return -i0
	}
	return i0
}

var Xats_sint_add_sint = func(i1 any, i2 any) any { return i1.(int) + i2.(int) }
var Xats_sint_sub_sint = func(i1 any, i2 any) any { return i1.(int) - i2.(int) }
var Xats_sint_mul_sint = func(i1 any, i2 any) any { return i1.(int) * i2.(int) }
var Xats_sint_div_sint = func(i1 any, i2 any) any { return i1.(int) / i2.(int) } // trunc toward 0, == JS Math.trunc
var Xats_sint_mod_sint = func(i1 any, i2 any) any { return i1.(int) % i2.(int) }

var Xats_sint_lt_sint = func(i1 any, i2 any) any { return i1.(int) < i2.(int) }
var Xats_sint_gt_sint = func(i1 any, i2 any) any { return i1.(int) > i2.(int) }
var Xats_sint_lte_sint = func(i1 any, i2 any) any { return i1.(int) <= i2.(int) }
var Xats_sint_gte_sint = func(i1 any, i2 any) any { return i1.(int) >= i2.(int) }
var Xats_sint_eq_sint = func(i1 any, i2 any) any { return i1.(int) == i2.(int) }
var Xats_sint_neq_sint = func(i1 any, i2 any) any { return i1.(int) != i2.(int) }

// -- generic integer (gint$sint$sint) fallbacks -----------------------------
// The generic g0int/gint op interface instantiated at sint.  goop_of_name
// inlines these to native Go operators, dropping the op-temp to a dead
// `_ = xatsgo.Xats_gint_<op>_sint_sint` suppressor; these defs back that
// suppressor (and any first-class/higher-order use).  Semantics identical to
// the monomorphic Xats_sint_*_sint above.
var Xats_gint_add_sint_sint = func(i1 any, i2 any) any { return i1.(int) + i2.(int) }
var Xats_gint_sub_sint_sint = func(i1 any, i2 any) any { return i1.(int) - i2.(int) }
var Xats_gint_mul_sint_sint = func(i1 any, i2 any) any { return i1.(int) * i2.(int) }
var Xats_gint_div_sint_sint = func(i1 any, i2 any) any { return i1.(int) / i2.(int) }
var Xats_gint_mod_sint_sint = func(i1 any, i2 any) any { return i1.(int) % i2.(int) }
var Xats_gint_lt_sint_sint = func(i1 any, i2 any) any { return i1.(int) < i2.(int) }
var Xats_gint_gt_sint_sint = func(i1 any, i2 any) any { return i1.(int) > i2.(int) }
var Xats_gint_lte_sint_sint = func(i1 any, i2 any) any { return i1.(int) <= i2.(int) }
var Xats_gint_gte_sint_sint = func(i1 any, i2 any) any { return i1.(int) >= i2.(int) }
var Xats_gint_eq_sint_sint = func(i1 any, i2 any) any { return i1.(int) == i2.(int) }
var Xats_gint_neq_sint_sint = func(i1 any, i2 any) any { return i1.(int) != i2.(int) }

// uint ops for the emitted frontend floor (xstamp0: stamp == uint boxed as int).
// [eq]/[cmp] return bool/int (NOT boxed `any`) because the emitter types their
// results from the SATS return type and emits the value bare (`return <r>` in a
// bool/int function), so the runtime Go type must match.
var Xats_gint_sint2uint = func(i any) any { return i.(int) }
var Xats_gint_suc_uint = func(i any) any { return i.(int) + 1 }
var Xats_gint_eq_uint_uint = func(i1 any, i2 any) bool { return i1.(int) == i2.(int) }
var Xats_gint_cmp_uint_uint = func(i1 any, i2 any) int {
	a, b := i1.(int), i2.(int)
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}
var Xats_gint_neg_sint = func(i any) any { return -i.(int) }
var Xats_gint_uint2sint = func(i any) any { return i.(int) }

// g_free: generic free.  Go is garbage-collected, so this is a no-op.  Kept so
// the emitted frontend (which frees linear values explicitly) type-checks.
var Xats_g_free = func(x any) any { return XATSNIL() }

// XATSOPT_strn_append_uint(name, stmp): append the uint's decimal digits to a
// string (xsymbol's symbl_extend_stamp builds "name<stmp>").
var Xats_XATSOPT_strn_append_uint = func(name any, stmp any) any {
	return name.(string) + strconv.Itoa(stmp.(int))
}

// strn_strmize(s): a char STREAM over s (strm_vt(cgtz)).  The frontend consumes
// it via strmcon_vt_nil()/strmcon_vt_cons(c, cs) -- i.e. Tag 0 / Tag 1 with
// Args[0]=char(int32), Args[1]=tail.  A finite string needs no laziness, so build
// the equivalent EAGER char cons-list (same Tag/Args shape -> identical matches).
var Xats_strn_strmize = func(s any) any {
	rs := []rune(s.(string))
	acc := &XatsCon{Tag: 0, Args: nil}
	for i := len(rs) - 1; i >= 0; i-- {
		acc = &XatsCon{Tag: 1, Args: []any{int32(rs[i]), acc}}
	}
	return acc
}

var Xats_g_eq = func(x1 any, x2 any) bool {
	if x1 == nil || x2 == nil {
		return x1 == x2
	}
	t1 := reflect.TypeOf(x1)
	t2 := reflect.TypeOf(x2)
	if t1 == t2 && t1.Comparable() {
		return x1 == x2
	}
	return reflect.DeepEqual(x1, x2)
}

// -- float (dflt) arithmetic / compare (any-typed fallback) ------------------

var Xats_dflt_add_dflt = func(f1 any, f2 any) any { return f1.(float64) + f2.(float64) }
var Xats_dflt_sub_dflt = func(f1 any, f2 any) any { return f1.(float64) - f2.(float64) }
var Xats_dflt_mul_dflt = func(f1 any, f2 any) any { return f1.(float64) * f2.(float64) }
var Xats_dflt_div_dflt = func(f1 any, f2 any) any { return f1.(float64) / f2.(float64) }

var Xats_dflt_lt_dflt = func(f1 any, f2 any) any { return f1.(float64) < f2.(float64) }
var Xats_dflt_gt_dflt = func(f1 any, f2 any) any { return f1.(float64) > f2.(float64) }
var Xats_dflt_lte_dflt = func(f1 any, f2 any) any { return f1.(float64) <= f2.(float64) }
var Xats_dflt_gte_dflt = func(f1 any, f2 any) any { return f1.(float64) >= f2.(float64) }
var Xats_dflt_eq_dflt = func(f1 any, f2 any) any { return f1.(float64) == f2.(float64) }
var Xats_dflt_neq_dflt = func(f1 any, f2 any) any { return f1.(float64) != f2.(float64) }

// -- char comparison (any-typed fallback; prelude names have no $ suffix) -----

var Xats_char_lt = func(c1 any, c2 any) any { return c1.(int32) < c2.(int32) }
var Xats_char_gt = func(c1 any, c2 any) any { return c1.(int32) > c2.(int32) }
var Xats_char_lte = func(c1 any, c2 any) any { return c1.(int32) <= c2.(int32) }
var Xats_char_gte = func(c1 any, c2 any) any { return c1.(int32) >= c2.(int32) }
var Xats_char_eq = func(c1 any, c2 any) any { return c1.(int32) == c2.(int32) }
var Xats_char_neq = func(c1 any, c2 any) any { return c1.(int32) != c2.(int32) }

// -- bool comparison (any-typed fallback; prelude names have no $ suffix) -----

var Xats_bool_eq = func(b1 any, b2 any) any { return b1.(bool) == b2.(bool) }
var Xats_bool_neq = func(b1 any, b2 any) any { return b1.(bool) != b2.(bool) }

// -- variadic prints / gs_print_aN ------------------------------------------
//
// `prints(x0, ..)` resolves (prelude/SATS/gsyn000.sats) to gs_print_aN, whose
// template BODY (prelude/DATS/gsyn000.dats) is
//
//	gs_print$beg(); g_print<x0>(x0); gs_print$sep(); g_print<x1>(x1); ...
//	                ...; gs_print$end()
//
// where the DEFAULT gs_print$beg/$sep/$end are NO-OPS, and each g_print<T> is
// the per-type print (strn_print / sint_print / ...) that PUSHES onto the
// print store.  The JS backend INLINES this template per call (each arg's
// static type picks g_print<T> at compile time).  The Go backend resolves the
// whole call to ONE runtime function (the M1 timp->named-runtime pattern), so
// the per-arg type dispatch happens HERE, at run time, on the arg's dynamic Go
// type -- producing the SAME pushed bytes (the differential oracle confirms).
//
// gsPrintOne mirrors g_print<T> for the scalar/string types the prelude default
// `print` covers: a Go string (from XATSSTRN/XATSSTR0) -> push verbatim (==
// strn_print); int -> Itoa (== sint_print); bool -> "true"/"false"; float64 ->
// XatsFloatToString; rune/int32 (a char) -> its single character.  An unknown
// type falls back to Go's default formatting (defensive; not on the test
// surface).
func xatsValueString(x any) string {
	switch v := x.(type) {
	case string:
		return v
	case int:
		return strconv.Itoa(v)
	case bool:
		if v {
			return "true"
		}
		return "false"
	case float64:
		return XatsFloatToString(v)
	case int32:
		return string(rune(v))
	case *XatsCon:
		return xatsListString(v)
	default:
		return fmt.Sprintf("%v", v)
	}
}

func xatsListString(xs *XatsCon) string {
	name := "list"
	if xs != nil && xs.Name == "list_vt" {
		name = "list_vt"
	}

	var b strings.Builder
	b.WriteString(name)
	b.WriteString("(")
	first := true
	for xs != nil && xs.Tag != 0 {
		if !first {
			b.WriteString(",")
		}
		first = false
		b.WriteString(xatsValueString(xs.Args[0]))
		xs = xs.Args[1].(*XatsCon)
	}
	b.WriteString(")")
	return b.String()
}

func gsPrintOne(x any) {
	thePrintStore = append(thePrintStore, xatsValueString(x))
}

func gsPrerrOne(x any) {
	fmt.Fprint(os.Stderr, xatsValueString(x))
}

var Xats_gs_print_a0 = func() any { return XATSNIL() }
var Xats_gs_print_a1 = func(x0 any) any { gsPrintOne(x0); return XATSNIL() }
var Xats_gs_print_a2 = func(x0 any, x1 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	return XATSNIL()
}
var Xats_gs_print_a3 = func(x0 any, x1 any, x2 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	return XATSNIL()
}
var Xats_gs_print_a4 = func(x0 any, x1 any, x2 any, x3 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	return XATSNIL()
}

// gs_print_n<N> is the `prints` overload family from prelude synoug0
// (gs_print_n<N> = gs_fproc_n<N> where g_fproc = g_print). Observably
// IDENTICAL to gs_print_a<N> above -- each arg printed via g_print, no
// separator -- so these mirror the (oracle-validated) _a twins exactly. The
// real (generic) compiler sources resolve `prints(...)` to this `_n` family.
var Xats_gs_print_n1 = func(x0 any) any { gsPrintOne(x0); return XATSNIL() }
var Xats_gs_print_n2 = func(x0, x1 any) any { gsPrintOne(x0); gsPrintOne(x1); return XATSNIL() }
var Xats_gs_print_n3 = func(x0, x1, x2 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	return XATSNIL()
}
var Xats_gs_print_n4 = func(x0, x1, x2, x3 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	return XATSNIL()
}
var Xats_gs_print_n5 = func(x0, x1, x2, x3, x4 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	return XATSNIL()
}
var Xats_gs_print_n6 = func(x0, x1, x2, x3, x4, x5 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	gsPrintOne(x5)
	return XATSNIL()
}
var Xats_gs_print_n7 = func(x0, x1, x2, x3, x4, x5, x6 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	gsPrintOne(x5)
	gsPrintOne(x6)
	return XATSNIL()
}
var Xats_gs_print_n8 = func(x0, x1, x2, x3, x4, x5, x6, x7 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	gsPrintOne(x5)
	gsPrintOne(x6)
	gsPrintOne(x7)
	return XATSNIL()
}
var Xats_gs_print_n9 = func(x0, x1, x2, x3, x4, x5, x6, x7, x8 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	gsPrintOne(x5)
	gsPrintOne(x6)
	gsPrintOne(x7)
	gsPrintOne(x8)
	return XATSNIL()
}
var Xats_gs_print_n10 = func(x0, x1, x2, x3, x4, x5, x6, x7, x8, x9 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	gsPrintOne(x5)
	gsPrintOne(x6)
	gsPrintOne(x7)
	gsPrintOne(x8)
	gsPrintOne(x9)
	return XATSNIL()
}

var Xats_gs_println_a0 = func() any {
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_a1 = func(x0 any) any {
	gsPrintOne(x0)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_a2 = func(x0 any, x1 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_a3 = func(x0 any, x1 any, x2 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_a4 = func(x0 any, x1 any, x2 any, x3 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}

var Xats_gs_prerrln_n0 = func() any {
	fmt.Fprint(os.Stderr, "\n")
	return XATSNIL()
}
var Xats_gs_prerrln_n1 = func(x0 any) any {
	gsPrerrOne(x0)
	fmt.Fprint(os.Stderr, "\n")
	return XATSNIL()
}
var Xats_gs_prerrln_n2 = func(x0 any, x1 any) any {
	gsPrerrOne(x0)
	gsPrerrOne(x1)
	fmt.Fprint(os.Stderr, "\n")
	return XATSNIL()
}

// ===========================================================================
// SELF-HOSTING prim leaves — the COMPILER-prelude primitives the EMITTER's own
// sources reference via xatsgo.Xats_* (the d2cstgo1 routing) that the runtime
// did not yet define. See docs/01-cats-go-prelude.md "Route 1 reality check":
// the emitter uses the compiler prelude (separate namespace from the XATS2GO_*
// user-prelude floor), and routes these prims to runtime leaves here. Semantics
// ported from the ATS prelude source; the Go value model is the runtime's:
// list = *XatsCon (Tag 0 nil / Tag 1 cons, Args[0]=head Args[1]=tail), char =
// int32/rune, bool = bool, sint = int, strn = string, symbl = interned NAME
// string.
//
// VERIFICATION STATUS: these are exercised only when the WHOLE Go emitter is
// built+run, which also needs the frontend-node ABI (still pending), so they
// are COMPILE targets matched to the emitted call sites + ported semantics, not
// yet end-to-end runtime-validated. The runtime package itself compiles (go
// build ./runtime/xatsgo), which is the check available today.
//
// EXCLUDED ON PURPOSE: list_exists / list_sortedq / list_map_e1nv /
// optn_map_e1nv / list_mergesort carry a per-call TEMPLATE METHOD
// ($pred/$fopr/$cmp) that the runtime routing drops, so they cannot be correct
// runtime leaves — the emitter must inline them. strn_fprint needs the FILR
// output model, deferred with the frontend ABI.
// ===========================================================================

// bool_neg: logical negation (prelude bool000: bool_neg(b) = ~b).
var Xats_bool_neg = func(b any) any { return !b.(bool) }

// symbl is an interned NAME string. TRUE_symbl = symbl("true");
// DLR_EXTNAM_symbl = symbl("$extnam"). symbl_cmp is the lexicographic name
// compare returning a sint (-1/0/1), consumed at the call site as `== 0`.
var Xats_TRUE_symbl any = "true"
var Xats_DLR_EXTNAM_symbl any = "$extnam"
var Xats_symbl_cmp = func(s1 any, s2 any) any {
	return strings.Compare(s1.(string), s2.(string))
}

// g_print<T>(x): the per-type print that PUSHES onto the print store; the
// generic dispatch is xatsValueString (same surface as gsPrintOne / prints).
var Xats_g_print = func(x any) any { gsPrintOne(x); return XATSNIL() }

// gs_print1_n<N>: the `print1s` family. prelude gbas000 has g_print1<a> =
// g_print<a>, so this is observably identical to gs_print_n<N> (each arg via
// g_print, no separator).
var Xats_gs_print1_n2 = func(x0, x1 any) any { gsPrintOne(x0); gsPrintOne(x1); return XATSNIL() }
var Xats_gs_print1_n3 = func(x0, x1, x2 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	return XATSNIL()
}
var Xats_gs_print1_n5 = func(x0, x1, x2, x3, x4 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	return XATSNIL()
}

// list_sing(x): the singleton list [x] (prelude list000).
var Xats_list_sing = func(x any) any {
	return xatsListCons("list", x, xatsListNil("list"))
}

// list_consq(xs): is xs a non-empty (cons) list? (prelude list000). The call
// site consumes the result as a Go bool.
var Xats_list_consq = func(xs any) bool {
	c, _ := xs.(*XatsCon)
	return c != nil && c.Tag != 0
}

// list_append(xs, ys): concatenate two lists, sharing ys's spine (prelude
// list000). Order-preserving: heads of xs are re-consed onto ys.
var Xats_list_append = func(xs any, ys any) any {
	x, _ := xs.(*XatsCon)
	var heads []any
	for x != nil && x.Tag != 0 {
		heads = append(heads, x.Args[0])
		x, _ = x.Args[1].(*XatsCon)
	}
	res, _ := ys.(*XatsCon)
	if res == nil {
		res = xatsListNil("list")
	}
	for i := len(heads) - 1; i >= 0; i-- {
		res = xatsListCons("list", heads[i], res)
	}
	return res
}

// strn_make_list(cs): build a string from a list of chars (prelude strn000).
// Chars are runes (int32); ints are tolerated defensively. (rune == int32 in
// Go, so the type switch uses int32 only to avoid a duplicate case.)
var Xats_strn_make_list = func(cs any) any {
	var b strings.Builder
	xs, _ := cs.(*XatsCon)
	for xs != nil && xs.Tag != 0 {
		switch c := xs.Args[0].(type) {
		case int32:
			b.WriteRune(rune(c))
		case int:
			b.WriteRune(rune(c))
		}
		xs, _ = xs.Args[1].(*XatsCon)
	}
	return b.String()
}

// stamp_cmp(s1, s2): a stamp is an abstract id over `uint` (xstamp0.sats:
// `#abstype stamp_type <= uint`); compare returns a sint (-1/0/1). Tolerant of
// the stamp's concrete Go integer type since the recorded gotyp for an abstract
// id is not always a fixed width.
func xatsStampVal(x any) uint64 {
	switch v := x.(type) {
	case int:
		return uint64(v)
	case uint:
		return uint64(v)
	case int64:
		return uint64(v)
	case uint64:
		return v
	case int32:
		return uint64(v)
	}
	return 0
}

var Xats_stamp_cmp = func(s1 any, s2 any) any {
	a, b := xatsStampVal(s1), xatsStampVal(s2)
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

// Xats_tup_get(t, i): the i-th field (F<i>) of a flat tuple/record struct that
// reached us ERASED as `any` (e.g. a tuple stored as a `list` element in
// `Args[i]`). A direct `t.F<i>` needs the exact `struct{...}` type, which is not
// recoverable where the element type was erased to the type variable; reflection
// reads the i-th field generically. (Normal projections off a typed root still
// emit `root.F<i>` directly; this is only for the erased-`any` root.)
func Xats_tup_get(t any, i int) any {
	v := reflect.ValueOf(t)
	if v.Kind() == reflect.Pointer {
		v = v.Elem()
	}
	return v.Field(i).Interface()
}

// -- intrep0 IR-type accessor floor -----------------------------------------
//
// The Go emitter (the 18 srcgen2/DATS/go1emit_*.dats modules) reads its INPUT
// IR through abstract-type method selectors -- `ipat.node()`, `iexp.lctn()`,
// etc. Those selectors resolve (via #symload) to the intrep0 accessor
// functions `i0pat_node$get`, `i0exp_lctn$get`, ... which d2cstgo1 routes to
// `xatsgo.Xats_i0pat_node_get`, `xatsgo.Xats_i0exp_lctn_get`, ... (abstract
// `tbox` accessors are runtime-ABI constants, the SAME boundary as list/strn/
// tuple ops). When the emitter is compiled to a standalone Go program, these
// names must be provided by the runtime floor -- intrep0 itself is not part of
// the assembled emitter package.
//
// Every intrep0 carrier is a SINGLE-constructor datatype, so it reaches the Go
// runtime as a `*XatsCon` with the constructor's value args in source order
// (Tag 0). Each accessor is therefore a fixed positional field read; the
// indices below mirror the `datatype` definitions in
// xats2cc/srcgen1/DATS/intrep0.dats verbatim.
func xatsIRfield(p any, i int) any {
	if c, ok := p.(*XatsCon); ok && i >= 0 && i < len(c.Args) {
		return c.Args[i]
	}
	return XATSNIL()
}

// i0exp = I0EXP of (loctn, i0typ, i0exp_node)
func Xats_i0exp_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0exp_ityp_get(p any) any { return xatsIRfield(p, 1) }
func Xats_i0exp_node_get(p any) any { return xatsIRfield(p, 2) }

// i0pat = I0PAT of (loctn, i0typ, i0pat_node)
func Xats_i0pat_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0pat_ityp_get(p any) any { return xatsIRfield(p, 1) }
func Xats_i0pat_node_get(p any) any { return xatsIRfield(p, 2) }

// i0pat_make_ityp$node(loc, ityp, node) = I0PAT(loc, ityp, node)
func Xats_i0pat_make_ityp_node(loc any, ityp any, node any) any {
	return &XatsCon{Tag: 0, Args: []any{loc, ityp, node}}
}

// i0dcl = I0DCL of (loctn, i0dcl_node)
func Xats_i0dcl_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0dcl_node_get(p any) any { return xatsIRfield(p, 1) }

// i0typ = I0TYP of (sort2, i0typ_node)
func Xats_i0typ_node_get(p any) any { return xatsIRfield(p, 1) }

// i0var = I0VAR of (d2var, sint lvl0, sint bvk0, i0typ)
func Xats_i0var_dvar_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0var_ityp_get(p any) any { return xatsIRfield(p, 3) }

// i0fundcl = I0FUNDCL of (loc_t, sint lvl0, d2var dpid, d2varlst, fiarglst farg, teqi0exp tdxp, i0varlst)
func Xats_i0fundcl_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0fundcl_dpid_get(p any) any { return xatsIRfield(p, 2) }
func Xats_i0fundcl_farg_get(p any) any { return xatsIRfield(p, 4) }
func Xats_i0fundcl_tdxp_get(p any) any { return xatsIRfield(p, 5) }

// i0vardcl = I0VARDCL of (loctn, i0var dpid, teqi0exp dini)
func Xats_i0vardcl_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0vardcl_dpid_get(p any) any { return xatsIRfield(p, 1) }
func Xats_i0vardcl_dini_get(p any) any { return xatsIRfield(p, 2) }

// i0valdcl = I0VALDCL of (loctn, i0pat ipat, teqi0exp tdxp)
func Xats_i0valdcl_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0valdcl_ipat_get(p any) any { return xatsIRfield(p, 1) }
func Xats_i0valdcl_tdxp_get(p any) any { return xatsIRfield(p, 2) }

// i0gua = I0GUA of (loctn, i0gua_node)
func Xats_i0gua_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0gua_node_get(p any) any { return xatsIRfield(p, 1) }

// i0gpt = I0GPT of (loctn, i0gpt_node)
func Xats_i0gpt_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0gpt_node_get(p any) any { return xatsIRfield(p, 1) }

// i0cls = I0CLS of (loctn, i0cls_node)
func Xats_i0cls_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0cls_node_get(p any) any { return xatsIRfield(p, 1) }

// fiarg = FIARG of (loctn, fiarg_node)
func Xats_fiarg_lctn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_fiarg_node_get(p any) any { return xatsIRfield(p, 1) }

// t0imp = T0IMP of (stamp, t0imp_node)
func Xats_t0imp_stmp_get(p any) any { return xatsIRfield(p, 0) }
func Xats_t0imp_node_get(p any) any { return xatsIRfield(p, 1) }

// i0parsed = I0PARSED of (sint stadyn, sint nerror, lcsrc source, i0dclistopt parsed)
func Xats_i0parsed_stadyn_get(p any) any { return xatsIRfield(p, 0) }
func Xats_i0parsed_nerror_get(p any) any { return xatsIRfield(p, 1) }
func Xats_i0parsed_source_get(p any) any { return xatsIRfield(p, 2) }
func Xats_i0parsed_parsed_get(p any) any { return xatsIRfield(p, 3) }

// strn_fprint(s, filr): write the string body s to a FILR-like writer (mirrors
// Xats_XATS2GO_chrfpr's writer handling). The emitter's strnfpr lowers to this.
func Xats_strn_fprint(s any, filr any) any {
	str, _ := s.(string)
	if w, ok := filr.(interface{ Write([]byte) (int, error) }); ok {
		_, _ = w.Write([]byte(str))
	}
	return XATSNIL()
}

// -- template-method worker-forwarding wrappers ------------------------------
//
// A template-method call (list_map, list_exists, ...) that reaches the emitter
// UNRESOLVED (the self-hosted frontend's template query failed, F3PERR0-TIMQ1)
// shortcuts to a worker-less 1-arg prim name. The emitter's Task-#8 forwarding
// re-attaches the worker: the in-scope `#impltmp` is emitted as a local closure
// and the prim VALUE is emitted as `Xats_<prim>_w(<adapter>)` -- these wrappers
// take the adapted worker (canonical func(any) any) and return the function of
// the arity the downstream application expects. Lists are Tag 0 nil / Tag 1
// cons with Args[0]=head, Args[1]=tail.
func Xats_list_map_w(f func(any) any) func(any) any {
	return func(xsa any) any {
		xs := xsa.(*XatsCon)
		var items []any
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			items = append(items, f(c.Args[0]))
		}
		out := &XatsCon{Tag: 0, Args: nil}
		for i := len(items) - 1; i >= 0; i-- {
			out = &XatsCon{Tag: 1, Args: []any{items[i], out}}
		}
		return out
	}
}

func Xats_list_exists_w(f func(any) any) func(any) any {
	return func(xsa any) any {
		xs := xsa.(*XatsCon)
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			if f(c.Args[0]).(bool) {
				return true
			}
		}
		return false
	}
}

// Xats_as_fun1/2: idempotent any -> canonical-func coercions (the Xats_as_con
// pattern). A nullary (eta-contracted) worker thunk may return its function
// EITHER as an `any` (needs the assert) OR as a concrete func type (a bare
// `.()` assert would be invalid Go); the `any` parameter accepts both.
func Xats_as_fun1(f any) func(any) any      { return f.(func(any) any) }
func Xats_as_fun2(f any) func(any, any) any { return f.(func(any, any) any) }

// e1nv family: the worker takes (element, env); the call takes (xs, env).
func Xats_list_map_e1nv_w(f func(any, any) any) func(any, any) any {
	return func(xsa any, env any) any {
		xs := xsa.(*XatsCon)
		var items []any
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			items = append(items, f(c.Args[0], env))
		}
		out := &XatsCon{Tag: 0, Args: nil}
		for i := len(items) - 1; i >= 0; i-- {
			out = &XatsCon{Tag: 1, Args: []any{items[i], out}}
		}
		return out
	}
}

func Xats_list_foritm_e1nv_w(f func(any, any) any) func(any, any) any {
	return func(xsa any, env any) any {
		xs := xsa.(*XatsCon)
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			_ = f(c.Args[0], env)
		}
		return XATSNIL()
	}
}

// optn is Tag 0 none / Tag 1 some with Args[0] the payload.
func Xats_optn_map_e1nv_w(f func(any, any) any) func(any, any) any {
	return func(oxa any, env any) any {
		ox := oxa.(*XatsCon)
		if ox == nil || ox.Tag == 0 {
			return &XatsCon{Tag: 0, Args: nil}
		}
		return &XatsCon{Tag: 1, Args: []any{f(ox.Args[0], env)}}
	}
}

// strn_foldl over the chars of a string; the worker takes (accumulator, char).
// The returned func takes/returns `any` (asserting inside) so a call site with
// an interface-typed string argument compiles; the result is coerced by the
// caller's own boundary (Xats_as_int).
func Xats_strn_foldl_w(f func(any, any) any) func(any, any) any {
	return func(s any, r0 any) any {
		acc := r0.(int)
		for _, c := range s.(string) {
			acc = f(acc, int32(c)).(int)
		}
		return acc
	}
}

// list_forall over a cons list; the worker returns bool (boxed any).
func Xats_list_forall_w(f func(any) any) func(any) any {
	return func(xsa any) any {
		xs := xsa.(*XatsCon)
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			if !f(c.Args[0]).(bool) {
				return false
			}
		}
		return true
	}
}

// simple prims for the emitted frontend floor.
func Xats_castlin10(x any) any { return x }
func Xats_list_head(xs any) any {
	return xs.(*XatsCon).Args[0]
}
func Xats_list_singq(xs any) bool {
	c, ok := xs.(*XatsCon)
	if !ok || c == nil || c.Tag != 1 {
		return false
	}
	t := c.Args[1].(*XatsCon)
	return t == nil || t.Tag == 0
}
func Xats_list_vt_reverse0(xs any) *XatsCon {
	out := &XatsCon{Tag: 0, Args: nil}
	for c, ok := xs.(*XatsCon); ok && c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
		out = &XatsCon{Tag: 1, Args: []any{c.Args[0], out}}
	}
	return out
}

// generic compare/min/max over the scalar reps the frontend uses (int, string).
func xatsGcmp(a any, b any) int {
	switch x := a.(type) {
	case int:
		y := b.(int)
		if x < y {
			return -1
		}
		if x > y {
			return 1
		}
		return 0
	case string:
		return strings.Compare(x, b.(string))
	case int32:
		y := b.(int32)
		if x < y {
			return -1
		}
		if x > y {
			return 1
		}
		return 0
	}
	panic("xatsgo: Xats_g_cmp: unsupported operand")
}
func Xats_g_cmp(a any, b any) int { return xatsGcmp(a, b) }
func Xats_g_max(a any, b any) any {
	if xatsGcmp(a, b) >= 0 {
		return a
	}
	return b
}
func Xats_g_min(a any, b any) any {
	if xatsGcmp(a, b) <= 0 {
		return a
	}
	return b
}
func Xats_gint_cmp_sint_sint(a any, b any) int { return xatsGcmp(a, b) }
func Xats_gint_asrn_sint(a any, n any) any     { return a.(int) >> uint(n.(int)) }
func Xats_gint_land_uint(a any, b any) any     { return a.(int) & b.(int) }
func Xats_list_nilq(xs any) bool {
	c, ok := xs.(*XatsCon)
	return !ok || c == nil || c.Tag == 0
}
func Xats_list_pair(x1 any, x2 any) *XatsCon {
	return &XatsCon{Tag: 1, Args: []any{x1,
		&XatsCon{Tag: 1, Args: []any{x2, &XatsCon{Tag: 0, Args: nil}}}}}
}

// ===========================================================================
// Self-hosting floor: JS-arm leaves (the _XATS2JS_ prelude arm resolved by the
// frontend routes its extern leaves here — the Go analogue of basics*.cats /
// NODE/basics0.cats), plus the sort/compare leaves of the compiler's own
// labeled-list templates.
// ===========================================================================

// -- NODE handles + fprint (NODE/basics0.cats) -------------------------------
//
// The JS arm's file handles are process.stdout/stderr; here the analogous
// io.Writer values. Every *_fprint below writes via the same duck-typed
// Write([]byte) the existing FILR helpers use.
var Xats_XATS2JS_NODE_g_stdout = func() any { return os.Stdout }
var Xats_XATS2JS_NODE_g_stderr = func() any { return os.Stderr }

// XATS2JS_NODE_strn_fprint(obj, out): out.write(obj) — arg order (obj, out).
var Xats_XATS2JS_NODE_strn_fprint = func(obj any, out any) any {
	s, ok := obj.(string)
	if !ok {
		s = xatsValueString(obj)
	}
	if w, ok := out.(interface{ Write([]byte) (int, error) }); ok {
		_, _ = w.Write([]byte(s))
	}
	return XATSNIL()
}

// -- stderr print family (synoug0's gs_prerr chain) --------------------------
//
// Every emitted call to the generic gs_fproc_n1/n2 hooks originates from
// gs_prerr_n1/n2 (synoug0.dats lines 478/489 — verified: ALL call-site source
// locations in the assembled output point there), whose local `#impltmp
// g_fproc = g_prerr` makes the observable behavior "print each arg to stderr".
var Xats_g_prerr = func(x any) any { gsPrerrOne(x); return XATSNIL() }
var Xats_gs_fproc_n1 = func(x0 any) any { gsPrerrOne(x0); return XATSNIL() }
var Xats_gs_fproc_n2 = func(x0 any, x1 any) any {
	gsPrerrOne(x0)
	gsPrerrOne(x1)
	return XATSNIL()
}

// -- generic ordering --------------------------------------------------------
func Xats_g_lte(a any, b any) bool { return xatsGcmp(a, b) <= 0 }
func Xats_g_gte(a any, b any) bool { return xatsGcmp(a, b) >= 0 }

// -- labeled-list sortedq/mergesort ------------------------------------------
//
// The compiler's two list_sortedq/list_mergesort instances (statyp2's
// f0_orderize over l2t2p, trxi0i1's over l1i1v) both sort single-constructor
// labeled pairs CON(label, item) by LABEL ONLY (xatsopt_tmplib's
// g_cmp<s2lab(x0)> compares just the labels; ditto the i1lab domain).
//
// label = LABint(sint) | LABsym(symbl): LABint(tag 0) < LABsym(tag 1); ints
// numerically; symbols by their STAMP (symbl = SYMBL(name, stamp), stamp is a
// plain int at runtime) — mirrors xlabel0's label_cmp + xsymbol's symbl_cmp.
func xatsLabelCmp(l1 any, l2 any) int {
	c1 := l1.(*XatsCon)
	c2 := l2.(*XatsCon)
	if c1.Tag != c2.Tag {
		if c1.Tag < c2.Tag {
			return -1
		}
		return 1
	}
	if c1.Tag == 0 { // LABint(i)
		return xatsGcmp(c1.Args[0], c2.Args[0])
	}
	// LABsym(SYMBL(name, stamp)): stamp compare
	s1 := c1.Args[0].(*XatsCon)
	s2 := c2.Args[0].(*XatsCon)
	return xatsGcmp(s1.Args[1], s2.Args[1])
}

// element = CON(label, item) — Args[0] is the label in both l2t2p and l1i1v.
func xatsLabItemCmp(a any, b any) int {
	return xatsLabelCmp(a.(*XatsCon).Args[0], b.(*XatsCon).Args[0])
}

func Xats_list_sortedq(xs any) bool {
	c := xs.(*XatsCon)
	for c.Tag != 0 {
		next := c.Args[1].(*XatsCon)
		if next.Tag == 0 {
			break
		}
		if xatsLabItemCmp(c.Args[0], next.Args[0]) > 0 {
			return false
		}
		c = next
	}
	return true
}

// stable merge sort over a cons-list (prelude list_mergesort semantics: the
// prelude's split/merge with g_cmp<=0 keeping the left element is stable).
func Xats_list_mergesort(xs any) *XatsCon {
	var elems []any
	for c := xs.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
		elems = append(elems, c.Args[0])
	}
	// insertion-free stable sort (mergesort)
	var merge func(a, b []any) []any
	merge = func(a, b []any) []any {
		out := make([]any, 0, len(a)+len(b))
		for len(a) > 0 && len(b) > 0 {
			if xatsLabItemCmp(a[0], b[0]) <= 0 {
				out = append(out, a[0])
				a = a[1:]
			} else {
				out = append(out, b[0])
				b = b[1:]
			}
		}
		out = append(out, a...)
		return append(out, b...)
	}
	var msort func(v []any) []any
	msort = func(v []any) []any {
		if len(v) <= 1 {
			return v
		}
		m := len(v) / 2
		return merge(msort(v[:m]), msort(v[m:]))
	}
	elems = msort(elems)
	acc := &XatsCon{Tag: 0}
	for i := len(elems) - 1; i >= 0; i-- {
		acc = &XatsCon{Tag: 1, Args: []any{elems[i], acc}}
	}
	return acc
}

// -- i0pat_allq (xats2cc/srcgen1 intrep0_utils0.dats) -------------------------
//
// Is the pattern irrefutable? i0pat_node tags follow intrep0.sats declaration
// order: I0Pany=0 I0Pvar=1 ... I0Ptup0=16(npf,i0ps) I0Ptup1=17(knd,npf,i0ps)
// I0Prcd2=18(knd,npf,l0i0ps with l0i0p=I0LAB(label,pat) — pat at Args[1]).
func Xats_i0pat_allq(p any) bool {
	node := Xats_i0pat_node_get(p).(*XatsCon)
	allList := func(lst any, patOf func(any) any) bool {
		for c := lst.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
			if !Xats_i0pat_allq(patOf(c.Args[0])) {
				return false
			}
		}
		return true
	}
	switch node.Tag {
	case 0, 1: // I0Pany, I0Pvar
		return true
	case 16: // I0Ptup0(npf, i0ps)
		return allList(node.Args[1], func(x any) any { return x })
	case 17: // I0Ptup1(knd, npf, i0ps)
		return allList(node.Args[2], func(x any) any { return x })
	case 18: // I0Prcd2(knd, npf, l0i0ps)
		return allList(node.Args[2], func(x any) any { return x.(*XatsCon).Args[1] })
	default:
		return false
	}
}

// -- jshmap (basics3.cats: the JS-object hashmap behind xlibext's mydict) -----
//
// JS Object.keys ordering is OBSERVABLE by the compiler (template-instance
// emission order): integer-like keys ascend numerically FIRST, then string
// keys in insertion order. xatsJSHMap reproduces exactly that.
type xatsJSHMap struct {
	m    map[any]any
	keys []any // insertion order of first insertion
}

func Xats_XATS2JS_jshmap_make_nil() any {
	return &xatsJSHMap{m: make(map[any]any)}
}

func Xats_XATS2JS_jshmap_insert_any(mp any, key any, itm any) any {
	h := mp.(*xatsJSHMap)
	if _, dup := h.m[key]; !dup {
		h.keys = append(h.keys, key)
	}
	h.m[key] = itm
	return XATSNIL()
}

// search$opt: optn_vt_nil()=Tag 0 / optn_vt_cons(itm)=Tag 1.
func Xats_XATS2JS_jshmap_search_opt(mp any, key any) *XatsCon {
	h := mp.(*xatsJSHMap)
	if itm, ok := h.m[key]; ok {
		return &XatsCon{Tag: 1, Args: []any{itm}}
	}
	return &XatsCon{Tag: 0}
}

// get_keys: a jsa1sz (JS array) of the keys — []any, JS enumeration order
// (numeric keys ascending, then string keys by insertion).
func Xats_XATS2JS_jshmap_get_keys(mp any) any {
	h := mp.(*xatsJSHMap)
	var ints []any
	var strs []any
	for _, k := range h.keys {
		switch k.(type) {
		case int:
			ints = append(ints, k)
		default:
			strs = append(strs, k)
		}
	}
	sort.Slice(ints, func(i, j int) bool { return ints[i].(int) < ints[j].(int) })
	return append(ints, strs...)
}

// jsa1sz_strmize: a stream over a JS array — like Xats_strn_strmize, a finite
// input needs no laziness: the equivalent EAGER cons-list (Tag 0/1 shape).
func Xats_XATS2JS_jsa1sz_strmize(xs any) any {
	arr := xs.([]any)
	acc := &XatsCon{Tag: 0}
	for i := len(arr) - 1; i >= 0; i-- {
		acc = &XatsCon{Tag: 1, Args: []any{arr[i], acc}}
	}
	return acc
}

// strm_vt_map0 reaches the runtime only via the worker-less fallback of
// gmap_strmize inside tmpmap_strmize — which no compiler module ever calls
// (declared in xstamp0.sats, zero call sites). Present only so the assembled
// package links; loudly unreachable by construction.
func Xats_strm_vt_map0(xs any) any {
	panic("xatsgo: Xats_strm_vt_map0: worker-less fallback (no live caller in xatsopt)")
}

// -- a0ref/a0ptr boxes (basics2.cats) ----------------------------------------
//
// The JS arm's 1-cell box (A0=[x0]) — same representation as the existing
// XatsA0Ref cell above; a0ptr2ref/a0ref2ptr are representation identity.
func Xats_a0ptr_make_1val(x0 any) any { return &XatsA0Ref{val: x0} }
func Xats_a0ptr2ref(a0 any) any       { return a0 }
func Xats_a0ref2ptr(a0 any) any       { return a0 }
func Xats_a0ref_dtget(a0 any) any     { return a0.(*XatsA0Ref).val }
func Xats_a0ref_dtset(a0, x0 any) any { a0.(*XatsA0Ref).val = x0; return XATSNIL() }

// -- self-hosting floor, round 2 ---------------------------------------------

// gs_println_n<N>: the `printsln` overload family (synoug0's gs_println_n<N> =
// gs_fproc_n<N> where g_fproc = g_print, then a newline) — print each arg to
// the stdout store, then "\n" (same shape as gs_println_a<N> above).
var Xats_gs_println_n6 = func(x0, x1, x2, x3, x4, x5 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	gsPrintOne(x4)
	gsPrintOne(x5)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}

// cast10 — representation-identity cast (same as castlin10).
func Xats_cast10(x any) any { return x }

// XATSOPT_XATSHOME_get: the compiler's XATSHOME root (JS arm reads the env).
func Xats_XATSOPT_XATSHOME_get() any { return os.Getenv("XATSHOME") }

// NODE gint fprint (NODE/basics0.cats sint_fprint): decimal int to the writer.
var Xats_XATS2JS_NODE_gint_fprint_sint = func(obj any, out any) any {
	if w, ok := out.(interface{ Write([]byte) (int, error) }); ok {
		_, _ = w.Write([]byte(strconv.Itoa(obj.(int))))
	}
	return XATSNIL()
}

// list_filter worker-forwarding wrapper (Task-#8 family `filter$test`): keep
// the elements the predicate accepts, preserving order.
func Xats_list_filter_w(f func(any) any) func(any) any {
	return func(xsa any) any {
		xs := xsa.(*XatsCon)
		var kept []any
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			if f(c.Args[0]).(bool) {
				kept = append(kept, c.Args[0])
			}
		}
		acc := &XatsCon{Tag: 0}
		for i := len(kept) - 1; i >= 0; i-- {
			acc = &XatsCon{Tag: 1, Args: []any{kept[i], acc}}
		}
		return acc
	}
}

// -- idempotent scalar coercions (Task-#10 arg boundary) ----------------------
//
// Like Xats_as_con/Xats_as_fun1: take `any`, return the concrete type.  A call
// site can wrap ANY argument expression — already-concrete (auto-boxed, then
// unboxed: compiles and is exact) or interface-typed (asserted) — so the
// emitter never needs to prove the arg's static Go type at a typed boundary.
func Xats_as_str(x any) string { return x.(string) }
func Xats_as_int(x any) int    { return x.(int) }
func Xats_as_bool(x any) bool  { return x.(bool) }
func Xats_as_rune(x any) rune {
	switch v := x.(type) {
	case rune:
		return v
	case int:
		return rune(v)
	}
	return x.(rune)
}

// -- self-hosting floor, round 3 (filpath / string-builder leaves) -----------

// strtmp_vt: the JS arm's mutable char buffer (basics1.cats: an Array with a
// trailing 0 sentinel).  A pointer-boxed rune slice mirrors the reference
// semantics; vt2t drops the sentinel and materializes the string.
type xatsStrTmp struct{ cs []rune }

func Xats_strtmp_vt_alloc(bsz any) any {
	n := bsz.(int)
	return &xatsStrTmp{cs: make([]rune, n+1)}
}
func Xats_strtmp_vt_set_at(cs any, i0 any, c0 any) any {
	b := cs.(*xatsStrTmp)
	switch v := c0.(type) {
	case rune:
		b.cs[i0.(int)] = v
	case int:
		b.cs[i0.(int)] = rune(v)
	}
	return XATSNIL()
}
func Xats_strn_vt2t(cs any) any {
	b := cs.(*xatsStrTmp)
	return string(b.cs[:len(b.cs)-1])
}
func Xats_UN_strn_vt_cast(x any) any { return x }

// strn_make_llist: build a string from a linear cons-list of chars.
func Xats_strn_make_llist(cs any) any {
	var b strings.Builder
	for c := cs.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
		switch v := c.Args[0].(type) {
		case rune:
			b.WriteRune(v)
		case int:
			b.WriteRune(rune(v))
		}
	}
	return b.String()
}

// list_vt basics: linear frees are GC no-ops; append0 is structural append.
func Xats_list_vt_free(xs any) any { return XATSNIL() }
func Xats_list_vt_append0(xs any, ys any) *XatsCon {
	var elems []any
	for c := xs.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
		elems = append(elems, c.Args[0])
	}
	acc := ys.(*XatsCon)
	for i := len(elems) - 1; i >= 0; i-- {
		acc = &XatsCon{Tag: 1, Args: []any{elems[i], acc}}
	}
	return acc
}

func Xats_gint_suc_sint(x any) any { return x.(int) + 1 }
func Xats_gint_pre_sint(x any) any { return x.(int) - 1 }

// gseq_z2cmp11<clst><cgtz><strn><cgtz>(x1, x2): lexicographic compare of a
// char cons-list against a string (filpath's z2eq "."/".."/"" tests).
func Xats_gseq_z2cmp11(x1 any, x2 any) int {
	rs := []rune(x2.(string))
	i := 0
	c := x1.(*XatsCon)
	for c.Tag != 0 && i < len(rs) {
		var ch rune
		switch v := c.Args[0].(type) {
		case rune:
			ch = v
		case int:
			ch = rune(v)
		}
		if ch < rs[i] {
			return -1
		}
		if ch > rs[i] {
			return 1
		}
		c = c.Args[1].(*XatsCon)
		i++
	}
	if c.Tag != 0 {
		return 1
	}
	if i < len(rs) {
		return -1
	}
	return 0
}

// gseq_group_lstrm_llist worker wrapper (bridge family `group$test`): split a
// char sequence (a string here — the <strn><cgtz> instances in filpath) into
// an EAGER stream of char cons-list groups.  Prelude strm_vt_group0 semantics:
// a char failing the test CLOSES the current group and is DISCARDED; the final
// group is always emitted (so "a//b" -> ["a","","b"], "/x" -> ["","x"]).
func Xats_gseq_group_lstrm_llist_w(f func(any) any) func(any) any {
	return func(xs any) any {
		var runes []rune
		switch v := xs.(type) {
		case string:
			runes = []rune(v)
		case *XatsCon:
			for c := v; c.Tag != 0; c = c.Args[1].(*XatsCon) {
				switch cv := c.Args[0].(type) {
				case rune:
					runes = append(runes, cv)
				case int:
					runes = append(runes, rune(cv))
				}
			}
		}
		var groups []*XatsCon
		cur := []rune{}
		for _, ch := range runes {
			if f(ch).(bool) {
				cur = append(cur, ch)
			} else {
				groups = append(groups, xatsRunesToList(cur))
				cur = []rune{}
			}
		}
		groups = append(groups, xatsRunesToList(cur))
		acc := &XatsCon{Tag: 0}
		for i := len(groups) - 1; i >= 0; i-- {
			acc = &XatsCon{Tag: 1, Args: []any{groups[i], acc}}
		}
		return acc
	}
}

func xatsRunesToList(rs []rune) *XatsCon {
	acc := &XatsCon{Tag: 0}
	for i := len(rs) - 1; i >= 0; i-- {
		acc = &XatsCon{Tag: 1, Args: []any{rs[i], acc}}
	}
	return acc
}

// -- self-hosting floor, round 4 (full-pipeline surface) ----------------------

// gs_max_n<N>: the variadic `maxs(...)` family (synoug0) — generic max.
func Xats_gs_max_n2(x1, x2 any) any { return Xats_g_max(x1, x2) }
func Xats_gs_max_n3(x1, x2, x3 any) any {
	return Xats_g_max(Xats_g_max(x1, x2), x3)
}
func Xats_gs_max_n4(x1, x2, x3, x4 any) any {
	return Xats_g_max(Xats_gs_max_n3(x1, x2, x3), x4)
}
func Xats_gs_min_n2(x1, x2 any) any { return Xats_g_min(x1, x2) }
func Xats_gs_min_n3(x1, x2, x3 any) any {
	return Xats_g_min(Xats_g_min(x1, x2), x3)
}

// gs_println_n<N>: print each arg + newline (stdout store).
var Xats_gs_println_n0 = func() any {
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_n2 = func(x0, x1 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_n4 = func(x0, x1, x2, x3 any) any {
	gsPrintOne(x0)
	gsPrintOne(x1)
	gsPrintOne(x2)
	gsPrintOne(x3)
	XATS2JS_strn_print("\n")
	return XATSNIL()
}

// gs_fproc_n3: like n1/n2 — every assembled call site originates from
// synoug0's gs_prerr_n3 (verified) — print each arg to stderr.
var Xats_gs_fproc_n3 = func(x0, x1, x2 any) any {
	gsPrerrOne(x0)
	gsPrerrOne(x1)
	gsPrerrOne(x2)
	return XATSNIL()
}

// char/code conversions (int <-> char; chars are rune/int32 or int at runtime).
func Xats_char_make_code(c any) any {
	switch v := c.(type) {
	case int:
		return rune(v)
	case rune:
		return v
	}
	return c
}
func Xats_char_code(c any) any {
	switch v := c.(type) {
	case rune:
		return int(v)
	case int:
		return v
	}
	return c
}

func Xats_list_last(xs any) any {
	c := xs.(*XatsCon)
	for c.Args[1].(*XatsCon).Tag != 0 {
		c = c.Args[1].(*XatsCon)
	}
	return c.Args[0]
}

func Xats_g_neq(a any, b any) bool { return !Xats_g_eq(a, b) }

// linearity casts — representation identity.
func Xats_enlinear(x any) any { return x }
func Xats_delinear(x any) any { return x }

// XATSOPT_a0ref_set = a0ref_set (the xlibext JS-arm extern).
func Xats_XATSOPT_a0ref_set(a0 any, x0 any) any {
	a0.(*XatsA0Ref).val = x0
	return XATSNIL()
}
func Xats_XATSOPT_a0ref_get(a0 any) any { return a0.(*XatsA0Ref).val }

// foritm worker wrappers (bridge family `foritm$work` — the plain, env-less
// foritm): apply the worker to each element for its effect.
func Xats_list_foritm_w(f func(any) any) func(any) any {
	return func(xsa any) any {
		xs := xsa.(*XatsCon)
		for c := xs; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			f(c.Args[0])
		}
		return XATSNIL()
	}
}
func Xats_optn_foritm_w(f func(any) any) func(any) any {
	return func(xsa any) any {
		xs := xsa.(*XatsCon)
		if xs != nil && xs.Tag == 1 {
			f(xs.Args[0])
		}
		return XATSNIL()
	}
}

// list_map$e1nv_vt — the linear (list_vt) variant of list_map$e1nv; the
// runtime list representation is identical (cons Tag 0/1).
func Xats_list_map_e1nv_vt_w(f func(any, any) any) func(any, any) any {
	return Xats_list_map_e1nv_w(f)
}

// -- self-hosting floor, round 5 ----------------------------------------------

// char classification / conversion (chars are rune or int at runtime).
func xatsRuneOf(c any) rune {
	switch v := c.(type) {
	case rune:
		return v
	case int:
		return rune(v)
	}
	return c.(rune)
}
func Xats_char_make_sint(i any) any  { return xatsRuneOf(i) }
func Xats_char_isdigit(c any) bool   { r := xatsRuneOf(c); return r >= '0' && r <= '9' }
func Xats_char_isalpha(c any) bool {
	r := xatsRuneOf(c)
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}
func Xats_char_isalnum(c any) bool { return Xats_char_isdigit(c) || Xats_char_isalpha(c) }
func Xats_char_isxdigit(c any) bool {
	r := xatsRuneOf(c)
	return (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
}
func Xats_sub_char_char(a any, b any) int { return int(xatsRuneOf(a)) - int(xatsRuneOf(b)) }

// bool_mul = conjunction (prelude bool 'multiplication').
func Xats_bool_mul(a any, b any) bool { return a.(bool) && b.(bool) }

// a1ptr / jsa1sz (JS array) — []any at runtime.
func Xats_a1ptr_get_at1(arr any, i any) any { return arr.([]any)[i.(int)] }
// some call sites pass the array's size along (a1ptr_free(ptr, n)) — accept
// and ignore it (freeing is the GC's job either way).
func Xats_a1ptr_free(arr any, _ ...any) any { return XATSNIL() }
func Xats_a1ptr_make_llist(xs any) any {
	var out []any
	for c := xs.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
		out = append(out, c.Args[0])
	}
	return out
}

// NODE char/uint fprint (NODE/basics0.cats).
var Xats_XATS2JS_NODE_char_fprint = func(obj any, out any) any {
	if w, ok := out.(interface{ Write([]byte) (int, error) }); ok {
		_, _ = w.Write([]byte(string(xatsRuneOf(obj))))
	}
	return XATSNIL()
}
var Xats_XATS2JS_NODE_gint_fprint_uint = Xats_XATS2JS_NODE_gint_fprint_sint

// list basics.
func Xats_list_vt_length1(xs any) int { return Xats_list_length(xs.(*XatsCon)) }
func Xats_list_get_at(xs any, i any) any {
	c := xs.(*XatsCon)
	for k := i.(int); k > 0; k-- {
		c = c.Args[1].(*XatsCon)
	}
	return c.Args[0]
}
// list_rappendx0_vt(xs, ys): reverse xs onto ys (prelude revappend).
func Xats_list_rappendx0_vt(xs any, ys any) *XatsCon {
	acc := ys.(*XatsCon)
	for c := xs.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
		acc = &XatsCon{Tag: 1, Args: []any{c.Args[0], acc}}
	}
	return acc
}
// list_extend(xs, x): append one element.
func Xats_list_extend(xs any, x any) *XatsCon {
	var elems []any
	for c := xs.(*XatsCon); c.Tag != 0; c = c.Args[1].(*XatsCon) {
		elems = append(elems, c.Args[0])
	}
	acc := &XatsCon{Tag: 1, Args: []any{x, &XatsCon{Tag: 0}}}
	for i := len(elems) - 1; i >= 0; i-- {
		acc = &XatsCon{Tag: 1, Args: []any{elems[i], acc}}
	}
	return acc
}

// gseq generics over string / cons-list sequences.
func xatsSeqItems(xs any) []any {
	switch v := xs.(type) {
	case string:
		var out []any
		for _, r := range v {
			out = append(out, r)
		}
		return out
	case []any:
		return v
	case *XatsCon:
		var out []any
		for c := v; c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			out = append(out, c.Args[0])
		}
		return out
	}
	return nil
}
func Xats_gseq_memberq(xs any, x0 any) bool {
	for _, it := range xatsSeqItems(xs) {
		if Xats_g_eq(it, x0) {
			return true
		}
	}
	return false
}
// gseq_last_ini(xs) / gseq_last_ini(xs, ini): last item, or [ini] when the
// sequence is empty (the 2-arg form is what the frontend emits).
func Xats_gseq_last_ini(xs any, ini ...any) any {
	items := xatsSeqItems(xs)
	if len(items) == 0 {
		if len(ini) > 0 {
			return ini[0]
		}
		panic("xatsgo: Xats_gseq_last_ini: empty sequence, no initial value")
	}
	return items[len(items)-1]
}
func Xats_gseq_get_at_opt(xs any, i any) *XatsCon {
	items := xatsSeqItems(xs)
	k := i.(int)
	if k >= 0 && k < len(items) {
		return &XatsCon{Tag: 1, Args: []any{items[k]}}
	}
	return &XatsCon{Tag: 0}
}
// gseq_prefixq(xs, ys): is xs a prefix of ys?
func Xats_gseq_prefixq(xs any, ys any) bool {
	a := xatsSeqItems(xs)
	b := xatsSeqItems(ys)
	if len(a) > len(b) {
		return false
	}
	for i := range a {
		if !Xats_g_eq(a[i], b[i]) {
			return false
		}
	}
	return true
}

// gs_println n7/n8.
var Xats_gs_println_n7 = func(x0, x1, x2, x3, x4, x5, x6 any) any {
	for _, x := range []any{x0, x1, x2, x3, x4, x5, x6} {
		gsPrintOne(x)
	}
	XATS2JS_strn_print("\n")
	return XATSNIL()
}
var Xats_gs_println_n8 = func(x0, x1, x2, x3, x4, x5, x6, x7 any) any {
	for _, x := range []any{x0, x1, x2, x3, x4, x5, x6, x7} {
		gsPrintOne(x)
	}
	XATS2JS_strn_print("\n")
	return XATSNIL()
}

func Xats_gflt_eq_dflt_dflt(a any, b any) bool { return a.(float64) == b.(float64) }

// strings.
func Xats_strn_nilq(s any) bool { return len(s.(string)) == 0 }
// strn_strxize: like strn_strmize — the char stream of a string (eager).
var Xats_strn_strxize = Xats_strn_strmize
func Xats_strm_vt_nil() *XatsCon { return &XatsCon{Tag: 0} }

// stropt: the JS arm's nullable string.
func Xats_stropt_nilq(x any) bool   { return x == nil }
func Xats_stropt_unsome(x any) any  { return x.(string) }

// g_parse / XATSOPT_strn_dflt_parse_exn: string -> float.
func Xats_g_parse(s any) any {
	f, err := strconv.ParseFloat(s.(string), 64)
	if err != nil {
		panic("xatsgo: Xats_g_parse: " + s.(string))
	}
	return f
}
// typed dflt return: the emitted reference site returns it as a
// `func(any) float64` value (token2sflt's parse hook).
func Xats_XATSOPT_strn_dflt_parse_exn(s any) float64 { return Xats_g_parse(s).(float64) }

// XATSOPT_argv$get: the driver's argv, shaped like the JS arm's
// (argv[0]=node, argv[1]=script, argv[2]=source, flags from 3) — two dummy
// slots are prepended so the emitted index arithmetic works unchanged.
func Xats_XATSOPT_argv_get() []any {
	out := []any{"xats2go", "goemit"}
	for _, a := range os.Args[1:] {
		out = append(out, a)
	}
	return out
}

// file I/O leaves (the compiler's source reading).
func Xats_XATSOPT_fpath_rexists(path any) bool {
	_, err := os.Stat(path.(string))
	return err == nil
}
func Xats_XATSOPT_fpath_full_read(path any) any {
	bs, err := os.ReadFile(path.(string))
	if err != nil {
		return nil // stropt none
	}
	return string(bs)
}

// gseq_foldl worker wrapper (bridge family foldl$fopr, generic sequences).
func Xats_gseq_foldl_w(f func(any, any) any) func(any, any) any {
	return func(xs any, ini any) any {
		acc := ini
		for _, it := range xatsSeqItems(xs) {
			acc = f(acc, it)
		}
		return acc
	}
}

// list_maprev worker wrapper (map$fopr family): map then reverse.
func Xats_list_maprev_w(f func(any) any) func(any) any {
	return func(xs any) any {
		acc := &XatsCon{Tag: 0}
		for c := xs.(*XatsCon); c != nil && c.Tag == 1; c = c.Args[1].(*XatsCon) {
			acc = &XatsCon{Tag: 1, Args: []any{f(c.Args[0]), acc}}
		}
		return acc
	}
}

// loudly-unreachable stubs (no live compiler caller; present so the package
// links — revisit if self-emission ever reaches them).
func Xats_strx_vt_map0(xs any) any {
	panic("xatsgo: Xats_strx_vt_map0: worker-less fallback")
}
func Xats_list_make_fwork(n any) any {
	panic("xatsgo: Xats_list_make_fwork: worker-less fallback")
}
func Xats_list_iforitm(xs any) any {
	panic("xatsgo: Xats_list_iforitm: worker-less fallback")
}

// -- self-hosting floor, round 6 ----------------------------------------------

// strn head/tail (prelude strn000): head_opt as optn_vt, tail as the rest.
func Xats_strn_head_opt(s any) *XatsCon {
	rs := []rune(s.(string))
	if len(rs) == 0 {
		return &XatsCon{Tag: 0}
	}
	return &XatsCon{Tag: 1, Args: []any{rs[0]}}
}
func Xats_strn_tail_raw(s any) any {
	rs := []rune(s.(string))
	if len(rs) == 0 {
		return ""
	}
	return string(rs[1:])
}

// strm_vt basics over the eager cons-list stream representation.
func Xats_strmcon_vt_sing(x any) *XatsCon {
	return &XatsCon{Tag: 1, Args: []any{x, &XatsCon{Tag: 0}}}
}
func Xats_strm_vt_listize0(xs any) any { return xs } // identical representation

// gseq_foritm: worker-less fallback — the bridged family covers the live
// call shapes; loud stub for the rest.
func Xats_gseq_foritm(xs any) any {
	panic("xatsgo: Xats_gseq_foritm: worker-less fallback")
}
func Xats_foritm_e1nv_work(x any, env any) any {
	panic("xatsgo: Xats_foritm_e1nv_work: unresolved default hook")
}

// datacopy: shallow copy of a con cell (linear copy — fresh cell, shared args).
func Xats_datacopy(x any) any {
	c := x.(*XatsCon)
	args := make([]any, len(c.Args))
	copy(args, c.Args)
	return &XatsCon{Tag: c.Tag, Args: args, Name: c.Name}
}
