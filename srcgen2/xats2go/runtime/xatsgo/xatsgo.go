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
