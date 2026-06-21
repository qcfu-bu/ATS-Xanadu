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

// -- low-level value combinators (mirror xats2js_js1emit.js) ----------------

// XATSSTRN is the string-literal combinator (identity on the Go string).
// Mirrors `let XATSSTRN = (cs) => cs` semantics.
func XATSSTRN(cs string) string { return cs }

// XATSSTR0 is the evaluated-string combinator (identity).
func XATSSTR0(cs string) string { return cs }

// XATSNIL is the unit value (ATS `()` / I1Vnil). Represented as nil `any`.
func XATSNIL() any { return nil }

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
// .length over the prelude's char model). Provided for completeness.
var Xats_strn_length = func(s0 any) any {
	return len(s0.(string))
}

// -- integer (sint) arithmetic / compare (any-typed fallback) ----------------

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
func gsPrintOne(x any) {
	switch v := x.(type) {
	case string:
		thePrintStore = append(thePrintStore, v)
	case int:
		thePrintStore = append(thePrintStore, strconv.Itoa(v))
	case bool:
		if v {
			thePrintStore = append(thePrintStore, "true")
		} else {
			thePrintStore = append(thePrintStore, "false")
		}
	case float64:
		thePrintStore = append(thePrintStore, XatsFloatToString(v))
	case int32: // a char literal is emitted as a Go rune (int32)
		thePrintStore = append(thePrintStore, string(rune(v)))
	default:
		thePrintStore = append(thePrintStore, fmt.Sprintf("%v", v))
	}
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
