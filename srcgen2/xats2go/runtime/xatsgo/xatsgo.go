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
	"runtime/pprof"
	"sort"
	"strconv"
	"strings"
	"unicode/utf16"
	"unsafe"
)

// thePrintStore mirrors XATS2JS_the_print_store: a growable buffer that
// strn_print appends to and the_print_store_flush drains.
var thePrintStore []string

// -- the -o CLI flag: tee the emission window to a file ---------------------
//
// `xats2go-selfhost -o out.go file.dats` writes the emitted Go program (the
// text between the //==XATS2GO-BEGIN==/END sentinels -- exactly what the
// harness awk extracts) to out.go as a side effect.  The stdout protocol is
// UNTOUCHED: diagnostics and the marked stream stay byte-identical to the
// JS-hosted reference, so every differential suite is blind to the flag.
// The flag is stripped in Xats_XATSOPT_argv_get, so the compiled ATS driver
// sees the same argv shape as before.  NOTE the compiler's error contract
// (JS-parity): an ill-typed compile still exits 0 and still emits a window
// (errored decls erased -- usually the trivial skeleton), with the errors
// reported as F3PERR0-ERROR/TREAD*-ERROR lines.  So out.go mirrors whatever
// the window produced -- callers must check the diagnostic lines, exactly
// as the harness does, not the exit code or the file's existence.
var xatsEmitTee *os.File
var xatsEmitTeeIn bool

const xatsEmitBegin = "//==XATS2GO-BEGIN==\n"
const xatsEmitEnd = "//==XATS2GO-END=="

// xatsEmitTeePut scans default-channel text for the sentinels and mirrors
// the in-window bytes (markers excluded) to the -o file.  Tolerates a
// marker embedded mid-chunk; the emitter in fact writes each marker as its
// own strnfpr call.
func xatsEmitTeePut(cs string) {
	for cs != "" {
		if !xatsEmitTeeIn {
			i := strings.Index(cs, xatsEmitBegin)
			if i < 0 {
				return
			}
			xatsEmitTeeIn = true
			cs = cs[i+len(xatsEmitBegin):]
			continue
		}
		i := strings.Index(cs, xatsEmitEnd)
		if i < 0 {
			_, _ = xatsEmitTee.WriteString(cs)
			return
		}
		_, _ = xatsEmitTee.WriteString(cs[:i])
		xatsEmitTeeIn = false
		_ = xatsEmitTee.Close()
		xatsEmitTee = nil
		return
	}
}

// xatsStorePut is the single choke point for DEFAULT-channel print-store
// appends.  During the diagnostics window (Xats_XATS2GO_report_begin/end)
// the default channel is STDERR and text is written through immediately —
// matching the srcgen1/JS-compiled side, where the reporters' resolved
// hooks write to stderr directly while stdout text stays in the store.
func xatsStorePut(cs string) {
	if xatsEmitTee != nil {
		xatsEmitTeePut(cs)
	}
	if f, ok := xatsDefaultOut.(*os.File); ok && f == os.Stderr {
		fmt.Fprint(os.Stderr, cs)
		return
	}
	thePrintStore = append(thePrintStore, cs)
}

// XATS2JS_strn_print pushes cs onto the print store (no output yet).
// Mirrors srcgen2_prelude.js: XATS2JS_strn_print(cs){ store.push(cs) }.
func XATS2JS_strn_print(cs string) {
	xatsStorePut(cs)
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
// -- CPU profiling hook (dev-cycle tooling) ---------------------------------
// XATSGO_CPUPROFILE=<path> starts a pprof CPU profile at first use of the
// print machinery... no: profiling must start at process START.  The driver
// calls XATS2GO_prof_begin from an init below and XATS2GO_flush_pending
// stops it at exit.
var xatsProfF *os.File

func init() {
	if p := os.Getenv("XATSGO_CPUPROFILE"); p != "" {
		f, err := os.Create(p)
		if err == nil {
			xatsProfF = f
			_ = pprof.StartCPUProfile(f)
		}
	}
}

func XATS2GO_flush_pending() {
	if len(thePrintStore) != 0 {
		fmt.Print(XATS2JS_the_print_store_flush())
	}
	if xatsEmitTee != nil { // emission never ended (failed compile): close
		_ = xatsEmitTee.Close()
		xatsEmitTee = nil
	}
	if xatsProfF != nil {
		pprof.StopCPUProfile()
		_ = xatsProfF.Close()
		xatsProfF = nil
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

// p2tr pointer primitives: EXACT typed semantics over real Go pointers
// (`$addr(x)` emits `&x`).  Used when a pointer flows through an `any`-typed
// generic-instance parameter, where native `*p` syntax cannot compile.
var Xats_p2tr_get = func(p any) any {
	switch q := p.(type) {
	case *any:
		return *q
	case *int:
		return *q
	case *bool:
		return *q
	case *string:
		return *q
	case *int32:
		return *q
	case *float64:
		return *q
	case **XatsHdr:
		// a by-ref DATATYPE cell.  Before datatype fields were typed, such a
		// cell was declared `any` and arrived here as `*any`; it is now
		// `*xatsgo.XatsCon`, so without this arm every one of the ~928
		// emitted p2tr sites fell through to reflection.
		return *q
	}
	return reflect.ValueOf(p).Elem().Interface()
}
var Xats_p2tr_set = func(p any, v any) any {
	switch q := p.(type) {
	case *any:
		*q = v
	case *int:
		*q = v.(int)
	case *bool:
		*q = v.(bool)
	case *string:
		*q = v.(string)
	case *int32:
		*q = v.(int32)
	case *float64:
		*q = v.(float64)
	case **XatsHdr:
		*q = Xats_as_con(v)
	default:
		reflect.ValueOf(p).Elem().Set(reflect.ValueOf(v))
	}
	return XATSNIL()
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
// XatsCon is the datatype HANDLE: an ALIAS of the common header, so every
// emitted `*xatsgo.XatsCon` annotation, `Xats_as_con`, and `v.Tag == N` test
// keeps working while the PAYLOAD lives in per-layout constructor structs
// emitted into package main (docs/11-datatype-representation.md).
// ATS2 equivalent: ATStysum() = struct{ int contag; }.
type XatsCon = XatsHdr

// LAYOUT MIRRORS: xatsgo cannot name main's `zzs_*` structs (no import
// cycle), but an unsafe cast only needs the LAYOUT to agree — which is how
// ATS2's C runtime works with generated tysum structs.  Keep in sync with
// go_dcon_layout_name's encoding.
type xatsConA struct {
	XatsHdr
	F0 any
}
type xatsConAA struct {
	XatsHdr
	F0 any
	F1 any
}
type xatsConAP struct {
	XatsHdr
	F0 any
	F1 *XatsHdr
}
type xatsConIII struct {
	XatsHdr
	F0 int
	F1 int
	F2 int
}

// EXCEPTIONS are an OPEN sum (all ctag -1, distinguished by Name), so they
// keep a name + boxed args beside the header.  The helpers keep `unsafe`
// inside xatsgo rather than in every emitted try/with.
type XatsExn struct {
	XatsHdr
	Name string
	Args []any
}

func Xats_exn_new(name string, args ...any) *XatsHdr {
	e := &XatsExn{XatsHdr{-1}, name, args}
	return &e.XatsHdr
}
func Xats_exn_name(v any) string {
	c, ok := v.(*XatsHdr)
	if !ok || c == nil || c.Tag != -1 {
		return ""
	}
	return (*XatsExn)(unsafe.Pointer(c)).Name
}
func Xats_exn_arg(v any, i int) any {
	c, ok := v.(*XatsHdr)
	if !ok || c == nil {
		return nil
	}
	e := (*XatsExn)(unsafe.Pointer(c))
	if i < 0 || i >= len(e.Args) {
		return nil
	}
	return e.Args[i]
}

// XatsHdr is the COMMON HEADER of the per-layout constructor structs
// (docs/11-datatype-representation.md).  Every datatype handle points at one
// of these; each constructor struct embeds it FIRST, so a handle can be cast
// to the constructor's own struct for typed field access — ATS2's
// `ATStysum(){int contag;}` + `ATSSELcon` model.  Keeping the handle common
// is what makes ATS's representation casts (list_vt <-> list, 620 sites, all
// identities today) free.
type XatsHdr struct{ Tag int }

func Xats_as_con(x any) *XatsCon {
	if x == nil {
		// XATSTOP0() -- the type checker's uninitialized placeholder -- is an
		// untyped nil `any` (266 emitted sites).  Under ERASED datatype fields
		// it was stored into an `any` slot bare, with no coercion; a typed "p"
		// slot coerces its argument, and a bare assertion panics on nil.
		// A nil datatype handle is the faithful image, and matches what the
		// erased model stored.  A later deref still panics, just at the read.
		return nil
	}
	return x.(*XatsCon)
}

// ---------------------------------------------------------------------------
// CON CONSTRUCTION — one allocation instead of two, none for nullary.
//
// `&XatsCon{Tag: t, Args: []any{a, b}}` costs TWO heap objects: the struct and
// the slice's backing array.  Measured over the emitted compiler: 5801 con
// constructions, 26.0% arity 0, 87.2% arity <= 2, 95.5% arity <= 3.
//
// So: carry inline storage for arity <= conInline and point Args into it (one
// allocation), and INTERN the nullary cons (zero allocations for a quarter of
// all constructions).  Interning is sound because a nullary con has no fields
// to mutate, nothing mutates Tag, and Name is written only by exception

func Xats_list_vt2t(xs *XatsCon) *XatsCon {
	// (formerly stamped xs.Name = "list" for the generic printer; that printer
	// is gone and nothing reads Name except exception matching, so the write
	// was dead — and removing it is what makes nullary-con INTERNING safe.)
	return xs
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
	if w, ok := xatsWriter(filr); ok {
		_, _ = w.Write([]byte(string(r)))
	}
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

// -- integer (sint) arithmetic / compare (any-typed fallback) ----------------

var Xats_sint_lt_sint = func(i1 any, i2 any) any { return i1.(int) < i2.(int) }
var Xats_sint_gt_sint = func(i1 any, i2 any) any { return i1.(int) > i2.(int) }
var Xats_sint_eq_sint = func(i1 any, i2 any) any { return i1.(int) == i2.(int) }

var Xats_gint_div_sint_sint = func(i1 any, i2 any) any { return i1.(int) / i2.(int) }
var Xats_gint_mod_sint_sint = func(i1 any, i2 any) any { return i1.(int) % i2.(int) }
var Xats_gint_gt_sint_sint = func(i1 any, i2 any) any { return i1.(int) > i2.(int) }

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

// typed int return: negation results flow into `int`-declared vars/globals
// (an `any` return needed an assertion Go's initializer position can't take).
var Xats_gint_neg_sint = func(i any) int { return -i.(int) }
var Xats_gint_uint2sint = func(i any) any { return i.(int) }

// XATSOPT_strn_append_uint(name, stmp): append the uint's decimal digits to a
// string (xsymbol's symbl_extend_stamp builds "name<stmp>").
var Xats_XATSOPT_strn_append_uint = func(name any, stmp any) any {
	return name.(string) + strconv.Itoa(stmp.(int))
}

// xatsStrmFrom/Xats_strm_of_items: the CALL-BY-NAME stream over [items] --
// a strm_vt is a `func() any` thunk yielding a strmcon (Tag 0 nil / Tag 1
// cons(x, next-strm)).  Emitted stream consumers FORCE each cell
// (`cs.(func() any)()`, the prelude's `!cs`), so producers must yield this
// thunk shape (the earlier eager cons-list shortcut only satisfied runtime-
// internal consumers).
func xatsStrmFrom(items []any, i int) func() any {
	return func() any {
		if i >= len(items) {
			return &XatsHdr{Tag: 0}
		}
		c := &xatsConAA{XatsHdr{1}, items[i], xatsStrmFrom(items, i+1)}
		return &c.XatsHdr
	}
}
func Xats_strm_of_items(items []any) func() any { return xatsStrmFrom(items, 0) }

// -- float (dflt) arithmetic / compare (any-typed fallback) ------------------

// -- char comparison (any-typed fallback; prelude names have no $ suffix) -----

var Xats_char_eq = func(c1 any, c2 any) any { return c1.(int32) == c2.(int32) }
var Xats_char_neq = func(c1 any, c2 any) any { return c1.(int32) != c2.(int32) }

// -- bool comparison (any-typed fallback; prelude names have no $ suffix) -----

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

// g_print: the STRINGS-ONLY residue of the old generic printer.  The
// resolved prelude prints everything through compiled ATS bodies down to the
// typed fprint leaves; the only remaining g_print references are the tmplib
// diagnostic printers' string-literal calls.  A non-string reaching here is
// a resolver regression -- fail loudly instead of approximating.
var Xats_g_print = func(x any) any {
	s, ok := x.(string)
	if !ok {
		panic(fmt.Sprintf("xatsgo: Xats_g_print: non-string %T reached the strings-only residue", x))
	}
	xatsStorePut(s)
	return XATSNIL()
}

// list_consq(xs): is xs a non-empty (cons) list? (prelude list000). The call
// site consumes the result as a Go bool.
var Xats_list_consq = func(xs any) bool {
	c, _ := xs.(*XatsCon)
	return c != nil && c.Tag != 0
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

// xatsWriter: resolve a FILR-like value to its io.Writer.  A value-like
// stdout/stderr instance can arrive UNPEELED — `val filr = g_stdout<>()`
// binds the runtime FUNC value without the final application (the
// nullary-instance thunk gap, driver zz_driver wiring) — so call through
// func layers until a writer emerges.  Silently-dropping a func-valued filr
// is what made the self-hosted emitter produce ZERO output with exit 0.
// xatsStoreWriter routes stdout-destined FILR writes through thePrintStore.
// The self-hosted emitter interleaves TWO output paths on stdout: direct
// strnfpr writes (the emitted Go text) and store-appending prints (the
// bridged print$ instances + the F3PERR d3exp debug lines).  If the direct
// path wrote immediately while the store flushed at exit, the store text
// would land AFTER the sentinels as one blob (observed).  Appending both to
// the store keeps everything in chronological append order, flushed once by
// XATS2GO_flush_pending — matching the JS bundle's single ordered stream.
type xatsStoreWriter struct{}

func (xatsStoreWriter) Write(p []byte) (int, error) {
	xatsStorePut(string(p))
	return len(p), nil
}

func xatsWriter(out any) (interface{ Write([]byte) (int, error) }, bool) {
	for i := 0; i < 4; i++ {
		if f, ok := out.(*os.File); ok && f == os.Stdout {
			return xatsStoreWriter{}, true
		}
		if w, ok := out.(interface{ Write([]byte) (int, error) }); ok {
			return w, true
		}
		if f, ok := out.(func() any); ok {
			out = f()
			continue
		}
		break
	}
	return nil, false
}

// Xats_as_fun1/2: idempotent any -> canonical-func coercions (the Xats_as_con
// pattern). A nullary (eta-contracted) worker thunk may return its function
// EITHER as an `any` (needs the assert) OR as a concrete func type (a bare
// `.()` assert would be invalid Go); the `any` parameter accepts both.
func Xats_as_fun1(f any) func(any) any {
	if fn, ok := f.(func(any) any); ok {
		return fn
	}
	// concrete return type (e.g. a list/map worker `func(any) *XatsCon`):
	// adapt through the reflection-tolerant apply so the result boxes to any.
	return func(a any) any { return Xats_applyN(f, a) }
}
func Xats_as_fun2(f any) func(any, any) any {
	if fn, ok := f.(func(any, any) any); ok {
		return fn
	}
	return func(a any, b any) any { return Xats_applyN(f, a, b) }
}

// simple prims for the emitted frontend floor.
func Xats_castlin10(x any) any { return x }

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
	case *XatsCon:
		// the only STRUCTURED value the frontend compares via g_cmp/g_min/g_max
		// is a `postn` = POSTN(ntot, nrow, ncol) (location arithmetic:
		// add_loctn_loctn's g_min(pbeg)/g_max(pend)), which orders by ntot
		// (postn_cmp).  Compare the leading int field.
		if y, ok := b.(*XatsCon); ok {
			{
				{
					xi := (*xatsConIII)(unsafe.Pointer(x)).F0
					yi := (*xatsConIII)(unsafe.Pointer(y)).F0
					if xi < yi {
						return -1
					}
					if xi > yi {
						return 1
					}
					return 0
				}
			}
		}
	}
	panic("xatsgo: Xats_g_cmp: unsupported operand")
}

// Xats_applyN: call a func VALUE whose concrete Go signature is not statically
// known at the call site (a value-like template instance whose result func
// returns a CONCRETE scalar, e.g. cmp_prcdv : func(any,any) int used in fixity
// resolution).  The emitter's generic `.(func(..) any)` assertion fails when
// the real return type is not `any`; this dispatches the common shapes and
// falls back to reflection, always returning `any` (box the result).
func Xats_applyN(f any, args ...any) any {
	switch fn := f.(type) {
	case func(any) any:
		return fn(args[0])
	case func(any, any) any:
		return fn(args[0], args[1])
	case func(any, any, any) any:
		return fn(args[0], args[1], args[2])
	case func(any) int:
		return fn(args[0])
	case func(any, any) int:
		return fn(args[0], args[1])
	case func(any) bool:
		return fn(args[0])
	case func(any, any) bool:
		return fn(args[0], args[1])
	}
	rv := reflect.ValueOf(f)
	in := make([]reflect.Value, len(args))
	for i, a := range args {
		if a == nil {
			in[i] = reflect.New(rv.Type().In(i)).Elem()
		} else {
			in[i] = reflect.ValueOf(a)
		}
	}
	out := rv.Call(in)
	if len(out) == 0 {
		return XATSNIL()
	}
	return out[0].Interface()
}
func Xats_gint_asrn_sint(a any, n any) any { return a.(int) >> uint(n.(int)) }
func Xats_gint_land_uint(a any, b any) any { return a.(int) & b.(int) }

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
var Xats_XATS2JS_NODE_g_stdout = func() any { return xatsDefaultOut }

// REPORT-CHANNEL OVERRIDE.  The srcgen2 resolver does not apply local
// `g_print$out<>() = out` hooks, so the print family in srcgen2-emitted code
// always writes to the DEFAULT channel.  The compiler's diagnostics window
// (driver: f3perr0_d3parsed with out0 = g_stderr) is stderr on the
// srcgen1/JS-compiled side; the driver brackets that window with these two
// leaves so the self-hosted binary's report lands on stderr identically.
var xatsDefaultOut any = os.Stdout

func Xats_XATS2GO_report_begin() any { xatsDefaultOut = os.Stderr; return nil }
func Xats_XATS2GO_report_end() any   { xatsDefaultOut = os.Stdout; return nil }

var Xats_XATS2JS_NODE_g_stderr = func() any { return os.Stderr }

// XATS2JS_NODE_strn_fprint(obj, out): out.write(obj) — arg order (obj, out).
var Xats_XATS2JS_NODE_strn_fprint = func(obj any, out any) any {
	s, ok := obj.(string)
	if !ok {
		// a non-string here means a print chain resolved to the WRONG leaf
		// (strn_fprint takes a strn) -- fail loudly, never approximate.
		panic(fmt.Sprintf("xatsgo: XATS2JS_NODE_strn_fprint: non-string %T", obj))
	}
	if w, ok := xatsWriter(out); ok {
		_, _ = w.Write([]byte(s))
	}
	return XATSNIL()
}

// bool/float fprint leaves (same (value, out) order as strn_fprint): the
// tmplib g_print<bool>/g_print<dflt> instances lower to these.
var Xats_XATS2JS_NODE_bool_fprint = func(b any, out any) any {
	s := "false"
	if v, ok := b.(bool); ok && v {
		s = "true"
	}
	return Xats_XATS2JS_NODE_strn_fprint(s, out)
}
var Xats_XATS2JS_NODE_gflt_fprint_dflt = func(f any, out any) any {
	v, _ := f.(float64)
	return Xats_XATS2JS_NODE_strn_fprint(XatsFloatToString(v), out)
}

// prelude JS-CATS scalar leaves (srcgen1/prelude/DATS/CATS/JS/basics3.dats
// extern names) reached by the resolved prelude bodies under --go-arm.
var Xats_XATS2JS_gint_suc_sint = func(x any) any { return x.(int) + 1 }
var Xats_XATS2JS_gint_gt_sint_sint = func(a any, b any) any { return a.(int) > b.(int) }
var Xats_XATS2JS_gint_gte_sint_sint = func(a int, b int) bool { return a >= b }
var Xats_XATS2JS_gint_lt_sint_sint = func(a any, b any) any { return a.(int) < b.(int) }
var Xats_XATS2JS_gint_lte_sint_sint = func(a any, b any) any { return a.(int) <= b.(int) }
var Xats_XATS2JS_gint_eq_sint_sint = func(a any, b any) any { return a.(int) == b.(int) }
var Xats_XATS2JS_gint_neq_sint_sint = func(a any, b any) any { return a.(int) != b.(int) }
var Xats_XATS2JS_gint_add_sint_sint = func(a any, b any) any { return a.(int) + b.(int) }
var Xats_XATS2JS_gint_sub_sint_sint = func(a any, b any) any { return a.(int) - b.(int) }
var Xats_XATS2JS_gint_mul_sint_sint = func(a any, b any) any { return a.(int) * b.(int) }

// -- generic ordering --------------------------------------------------------
//
// XatsGlteConHook: package-registered `<=` for CONSTRUCTOR operands.  Every
// bridged g_lte site in the self-host assembly compares sort2 values (the
// frontend's `#impltmp g_lte<sort2> = lte_sort2_sort2` reaches the emitter
// UNRESOLVED as a prelude-cst dapp and bridges here by name; the sort2
// subsort logic -- t2bas lattice, S2Tint EQUALITY, structural recursion --
// cannot be mirrored by a generic shape compare, so zz_shims.go registers
// the package's real stamped lte_sort2_sort2 at init).  nil = no frontend
// hook (rung/suite programs): plain xatsGcmp ordering as before.
var XatsGlteConHook func(a any, b any) any

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
		c := &xatsConA{XatsHdr{1}, itm}
		return &c.XatsHdr
	}
	return &XatsHdr{Tag: 0}
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

// jsa1sz_strmize: the stream over a JS array (same thunk shape).
func Xats_XATS2JS_jsa1sz_strmize(xs any) any {
	return xatsStrmFrom(xs.([]any), 0)
}

// -- a0ref/a0ptr boxes (basics2.cats) ----------------------------------------
//
// The JS arm's 1-cell box (A0=[x0]) — same representation as the existing
// XatsA0Ref cell above; a0ptr2ref/a0ref2ptr are representation identity.
func Xats_a0ptr_make_1val(x0 any) any { return &XatsA0Ref{val: x0} }
func Xats_a0ptr2ref(a0 any) any       { return a0 }
func Xats_a0ref_dtget(a0 any) any     { return a0.(*XatsA0Ref).val }
func Xats_a0ref_dtset(a0, x0 any) any { a0.(*XatsA0Ref).val = x0; return XATSNIL() }

// -- self-hosting floor, round 2 ---------------------------------------------

// cast10 — representation-identity cast (same as castlin10).
func Xats_cast10(x any) any { return x }

// XATSOPT_XATSHOME_get: the compiler's XATSHOME root (JS arm reads the env).
func Xats_XATSOPT_XATSHOME_get() any { return os.Getenv("XATSHOME") }

// NODE gint fprint (NODE/basics0.cats sint_fprint): decimal int to the writer.
var Xats_XATS2JS_NODE_gint_fprint_sint = func(obj any, out any) any {
	if w, ok := xatsWriter(out); ok {
		_, _ = w.Write([]byte(strconv.Itoa(obj.(int))))
	}
	return XATSNIL()
}

// -- idempotent scalar coercions (Task-#10 arg boundary) ----------------------
//
// Like Xats_as_con/Xats_as_fun1: take `any`, return the concrete type.  A call
// site can wrap ANY argument expression — already-concrete (auto-boxed, then
// unboxed: compiles and is exact) or interface-typed (asserted) — so the
// emitter never needs to prove the arg's static Go type at a typed boundary.
func Xats_as_str(x any) string { return x.(string) }
func Xats_as_int(x any) int {
	switch v := x.(type) {
	case int:
		return v
	case rune:
		// JS-numeric parity: a char is its code (one number type in JS);
		// the Go image splits int/rune, so the int boundary converts.
		return int(v)
	}
	return x.(int)
}
func Xats_as_bool(x any) bool { return x.(bool) }
func Xats_as_rune(x any) rune {
	switch v := x.(type) {
	case rune:
		return v
	case int:
		return rune(v)
	}
	return x.(rune)
}

// -- flat-tuple repack (arg boundary, anonymous-struct identity) --------------
//
// A flat ATS tuple emits as an ANONYMOUS Go struct; producer and consumer
// recover the field types independently, so the same logical tuple can be
// built as struct{F0 any; F1 any} yet consumed as struct{F0 int; F1 *XatsCon}.
// Go type-asserts on anonymous structs need EXACT identity, so an `any`-typed
// tuple crossing a concretely-typed param boundary repacks field-by-field via
// reflection instead (idempotent when the identities already agree).
func xatsTupField[T any](v reflect.Value, i int) T {
	f := v.Field(i).Interface()
	if t, ok := f.(T); ok {
		return t
	}
	var zero T
	switch any(zero).(type) {
	case rune: // int-carried char (the Xats_as_rune leniency)
		if n, ok := f.(int); ok {
			return any(rune(n)).(T)
		}
	case int:
		if r, ok := f.(rune); ok {
			return any(int(r)).(T)
		}
	}
	return f.(T)
}

func Xats_as_tup2[A, B any](x any) struct {
	F0 A
	F1 B
} {
	v := reflect.ValueOf(x)
	return struct {
		F0 A
		F1 B
	}{xatsTupField[A](v, 0), xatsTupField[B](v, 1)}
}

func Xats_as_tup3[A, B, C any](x any) struct {
	F0 A
	F1 B
	F2 C
} {
	v := reflect.ValueOf(x)
	return struct {
		F0 A
		F1 B
		F2 C
	}{xatsTupField[A](v, 0), xatsTupField[B](v, 1), xatsTupField[C](v, 2)}
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

func Xats_gint_pre_sint(x any) any { return x.(int) - 1 }

// -- self-hosting floor, round 4 (full-pipeline surface) ----------------------

// linearity casts — representation identity.
func Xats_enlinear(x any) any { return x }
func Xats_delinear(x any) any { return x }

// XATSOPT_a0ref_set = a0ref_set (the xlibext JS-arm extern).
func Xats_XATSOPT_a0ref_set(a0 any, x0 any) any {
	a0.(*XatsA0Ref).val = x0
	return XATSNIL()
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
func Xats_char_isdigit(c any) bool { r := xatsRuneOf(c); return r >= '0' && r <= '9' }
func Xats_char_isalpha(c any) bool {
	r := xatsRuneOf(c)
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}
func Xats_char_isalnum(c any) bool { return Xats_char_isdigit(c) || Xats_char_isalpha(c) }
func Xats_char_isxdigit(c any) bool {
	r := xatsRuneOf(c)
	return (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
}

// bool_mul = conjunction (prelude bool 'multiplication').
func Xats_bool_mul(a any, b any) bool { return a.(bool) && b.(bool) }

// a1ptr / jsa1sz (JS array) — []any at runtime.
func Xats_a1ptr_get_at1(arr any, i any) any { return arr.([]any)[i.(int)] }

// NODE char/uint fprint (NODE/basics0.cats).
var Xats_XATS2JS_NODE_char_fprint = func(obj any, out any) any {
	if w, ok := xatsWriter(out); ok {
		_, _ = w.Write([]byte(string(xatsRuneOf(obj))))
	}
	return XATSNIL()
}
var Xats_XATS2JS_NODE_gint_fprint_uint = Xats_XATS2JS_NODE_gint_fprint_sint

// gseq generics over string / cons-list sequences.
func xatsSeqItems(xs any) []any {
	switch v := xs.(type) {
	case func() any:
		// a call-by-name stream: force each cell.
		var out []any
		cur := v
		for {
			c := Xats_as_con(cur())
			if c == nil || c.Tag != 1 {
				break
			}
			cc := (*xatsConAA)(unsafe.Pointer(c))
			out = append(out, cc.F0)
			nxt, ok := cc.F1.(func() any)
			if !ok {
				// eager tail (mixed producer): fall back to the con walk.
				for t := Xats_as_con(cc.F1); t != nil && t.Tag == 1; {
					tc := (*xatsConAP)(unsafe.Pointer(t))
					out = append(out, tc.F0)
					t = tc.F1
				}
				break
			}
			cur = nxt
		}
		return out
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
		for c := v; c != nil && c.Tag == 1; {
			cc := (*xatsConAP)(unsafe.Pointer(c))
			out = append(out, cc.F0)
			c = cc.F1
		}
		return out
	}
	return nil
}

func Xats_gflt_eq_dflt_dflt(a any, b any) bool { return a.(float64) == b.(float64) }

// stropt: the JS arm's nullable string.
func Xats_stropt_nilq(x any) bool  { return x == nil }
func Xats_stropt_unsome(x any) any { return x.(string) }

// g_parse / XATSOPT_strn_dflt_parse_exn: string -> float.
// Xats_g_parse mirrors the JS bundle's Number(s) hook, EXCEPT an integer
// string yields a Go int: the JS float64-for-everything convention breaks
// int consumers (staexp0's `LABint(g_parse(tok))` is asserted `.(int)` by
// label_cmp).  JS-observable behavior is unchanged -- "42" compares/prints
// as 42 either way, "0x10" -> 16 (base-detected like Number) -- and a
// non-integer string still parses as float64.
func Xats_g_parse(s any) any {
	str := s.(string)
	if i, err := strconv.Atoi(str); err == nil {
		return i
	}
	if i, err := strconv.ParseInt(str, 0, 64); err == nil {
		return int(i)
	}
	f, err := strconv.ParseFloat(str, 64)
	if err != nil {
		panic("xatsgo: Xats_g_parse: " + str)
	}
	return f
}

// typed dflt return: the emitted reference site returns it as a
// `func(any) float64` value (token2sflt's parse hook).
func Xats_XATSOPT_strn_dflt_parse_exn(s any) float64 {
	switch v := Xats_g_parse(s).(type) {
	case float64:
		return v
	case int:
		return float64(v)
	}
	panic("xatsgo: strn_dflt_parse_exn")
}

// XATSOPT_argv$get: the driver's argv, shaped like the JS arm's
// (argv[0]=node, argv[1]=script, argv[2]=source, flags from 3) — two dummy
// slots are prepended so the emitted index arithmetic works unchanged.
func Xats_XATSOPT_argv_get() []any {
	args := os.Args[1:]
	out := []any{"xats2go", "goemit"}
	for i := 0; i < len(args); i++ {
		if args[i] == "-o" {
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "xats2go: -o needs a file argument")
				os.Exit(1)
			}
			if xatsEmitTee == nil {
				f, err := os.Create(args[i+1])
				if err != nil {
					fmt.Fprintf(os.Stderr, "xats2go: -o %s: %v\n", args[i+1], err)
					os.Exit(1)
				}
				xatsEmitTee = f
			}
			i++
			continue
		}
		out = append(out, args[i])
	}
	return out
}

// jsa1sz (the JS-arm array) ops the driver's argv loop uses.
func Xats_XATS2JS_jsa1sz_length(a any) int        { return len(a.([]any)) }
func Xats_XATS2JS_jsa1sz_get_at(a any, i any) any { return a.([]any)[i.(int)] }

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

// -- self-hosting floor, round 6 ----------------------------------------------

// strn head/tail (prelude strn000): head_opt as optn_vt, tail as the rest.
// strn_head$opt: every emitted use compares the result DIRECTLY as a char
// (`strn_head$opt(sym) = '?'`), so return the head rune; NUL for the empty
// string (equal to no real compared char).
func Xats_strn_head_opt(s any) rune {
	rs := []rune(s.(string))
	if len(rs) == 0 {
		return rune(0)
	}
	return rs[0]
}
func Xats_strn_tail_raw(s any) any {
	rs := []rune(s.(string))
	if len(rs) == 0 {
		return ""
	}
	return string(rs[1:])
}

// datacopy: IDENTITY (matches the JS backend, where datacopy is an fcast ->
// XATSCAST -> returns its argument unchanged).  A real copy breaks shared
// mutable state threaded through linear values — e.g. the lexer's position
// cell in genv000's g_foritm$e1nv, where the worker mutates the pstn IN
// PLACE; a fresh copy silently drops every position update, corrupting token
// locations and desyncing the declaration parser (the self-host D0Ctkerr
// storm).
func Xats_datacopy(x any) any { return x }

// ////////////////////////////////////////////////////////////////
// CATS LEAF BINDINGS -- the XATS2JS extern-name surface.
//
// Under universal resolved-prelude emission, every prelude template chain
// resolves through compiled ATS source down to the per-target `<>` impls of
// libcats/basics, whose bodies are the XATS2JS_* externs (srcgen1 xatslib
// CATS/JS/NODE).  Those extern names arrive here via d2cstgo1's bare-name
// emission (an $extnam with no body has i1dclq optn_nil), so THIS block is
// the runtime's real semantic surface: exact, typed primitives keyed by the
// extern names the prelude source binds.  Aliases delegate to the audited
// helpers above (same Go signature -- so call-shape behavior is unchanged);
// only the primitives with no prior helper are implemented fresh, against
// the srcgen1_prelude.js / basics1.cats(PY) reference bodies.
// ////////////////////////////////////////////////////////////////

// strings (a strn is a Go string; chars are runes/int32 codes)
// The JS backend's string model is UTF-16: XATS2JS_strn_get_at is
// charCodeAt (UNIT-indexed) and XATS2JS_strn_length is .length (UNIT count).
// The Go byte model diverges on any non-ASCII source char (an em-dash in a
// comment shifted every downstream diagnostic offset by +2), so the CATS
// leaves index a cached UTF-16 view.  Single-entry cache: the lexer walks one
// source string at a time, so the conversion amortizes to O(1) per access.
var xatsU16LastS string
var xatsU16Last []uint16

func xatsU16Of(s string) []uint16 {
	if s == xatsU16LastS && xatsU16Last != nil {
		return xatsU16Last
	}
	u := utf16.Encode([]rune(s))
	xatsU16LastS, xatsU16Last = s, u
	return u
}

func Xats_XATS2JS_strn_get_at(s any, i int) rune { return rune(xatsU16Of(s.(string))[i]) }
func Xats_XATS2JS_strn_length(s any) int         { return len(xatsU16Of(s.(string))) }
func Xats_XATS2JS_strn_eq(s1 any, s2 any) bool   { return s1.(string) == s2.(string) }
func Xats_XATS2JS_strn_neq(s1 any, s2 any) bool  { return s1.(string) != s2.(string) }

var Xats_XATS2JS_strn_vt2t = Xats_strn_vt2t
var Xats_XATS2JS_strn_head_opt = Xats_strn_head_opt
var Xats_XATS2JS_strn_tail_raw = Xats_strn_tail_raw

// strn_forall_f1un(cs, test): does [test] pass on EVERY char code of [cs]?
func Xats_XATS2JS_strn_forall_f1un(cs any, test any) bool {
	f := Xats_as_fun1(test)
	for _, r := range cs.(string) {
		if !Xats_as_bool(f(r)) {
			return false
		}
	}
	return true
}

// string builders + string options
func Xats_XATS2JS_strtmp_vt_alloc(bsz int) any                { return Xats_strtmp_vt_alloc(bsz) }
func Xats_XATS2JS_strtmp_vt_set_at(cs any, i int, c rune) any { return Xats_strtmp_vt_set_at(cs, i, c) }

var Xats_XATS2JS_stropt_nilq = Xats_stropt_nilq

// strm_vt_forall0_f1un(xs, test): force the stream; [test] on every item.
func Xats_XATS2JS_strm_vt_forall0_f1un(xs any, test any) bool {
	f := Xats_as_fun1(test)
	for _, x := range xatsSeqItems(xs) {
		if !Xats_as_bool(f(x)) {
			return false
		}
	}
	return true
}

// chars
var Xats_XATS2JS_char_eq = Xats_char_eq
var Xats_XATS2JS_char_neq = Xats_char_neq

func Xats_XATS2JS_char_equal(c1 rune, c2 rune) bool { return c1 == c2 }

var Xats_XATS2JS_char_isdigit = Xats_char_isdigit
var Xats_XATS2JS_char_isalnum = Xats_char_isalnum
var Xats_XATS2JS_char_isxdigit = Xats_char_isxdigit

func Xats_XATS2JS_char_eqz(c any) bool { return xatsRuneOf(c) == 0 }
func Xats_XATS2JS_char_cmp(r1 rune, r2 rune) int {
	if r1 < r2 {
		return -1
	}
	if r1 > r2 {
		return 1
	}
	return 0
}

// integers (uints share the int rep, as in the JS backend)
var Xats_XATS2JS_gint_neg_sint = Xats_gint_neg_sint
var Xats_XATS2JS_gint_pre_sint = Xats_gint_pre_sint
var Xats_XATS2JS_gint_suc_uint = Xats_gint_suc_uint
var Xats_XATS2JS_gint_sint2uint = Xats_gint_sint2uint
var Xats_XATS2JS_gint_uint2sint = Xats_gint_uint2sint
var Xats_XATS2JS_gint_land_uint = Xats_gint_land_uint
var Xats_XATS2JS_gint_asrn_sint = Xats_gint_asrn_sint
var Xats_XATS2JS_gint_div_sint_sint = Xats_gint_div_sint_sint
var Xats_XATS2JS_gint_mod_sint_sint = Xats_gint_mod_sint_sint

func Xats_XATS2JS_gint_cmp_sint_sint(a int, b int) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

var Xats_XATS2JS_gint_cmp_uint_uint = Xats_gint_cmp_uint_uint
var Xats_XATS2JS_gint_eq_uint_uint = Xats_gint_eq_uint_uint

// gint_parse_sint(rep): decimal parse (JS parseInt(rep, 10)).
func Xats_XATS2JS_gint_parse_sint(rep any) int {
	n, err := strconv.Atoi(rep.(string))
	if err != nil {
		panic("xatsgo: Xats_XATS2JS_gint_parse_sint: " + rep.(string))
	}
	return n
}

// floats + bools
var Xats_XATS2JS_gflt_eq_dflt_dflt = Xats_gflt_eq_dflt_dflt
var Xats_XATS2JS_bool_neg = Xats_bool_neg
var Xats_XATS2JS_bool_mul = Xats_bool_mul

// mutable cells + 1-dim arrays
var Xats_XATS2JS_a0ref_get = Xats_a0ref_get
var Xats_XATS2JS_a0ref_set = Xats_a0ref_set
var Xats_XATS2JS_a0ref_dtget = Xats_a0ref_dtget
var Xats_XATS2JS_a0ref_dtset = Xats_a0ref_dtset
var Xats_XATS2JS_a0ptr_make_1val = Xats_a0ptr_make_1val
var Xats_XATS2JS_a1ptr_get_at1 = Xats_a1ptr_get_at1

func Xats_XATS2JS_a1ptr_alloc(asz any) any { return make([]any, asz.(int)) }
func Xats_XATS2JS_a1ptr_set_at1(arr any, i any, x any) any {
	arr.([]any)[i.(int)] = x
	return XATSNIL()
}

// casts: representation-identical views (the JS backend's XATSCAST).
func Xats_cast01(x any) any    { return x }
func Xats_castlin01(x any) any { return x }
func Xats_optn_vt2t(x any) any { return x }

// Xats_as_dflt: the float boundary coercion (the Xats_as_int pattern).  An
// `any` produced by JS-semantics arithmetic may hold an int where a dflt is
// expected (JS numbers are one type); unbox either.
func Xats_as_dflt(x any) float64 {
	switch v := x.(type) {
	case float64:
		return v
	case int:
		return float64(v)
	}
	return x.(float64)
}

// ////////////////////////////////////////////////////////////////
// CATS LEAF BINDINGS, part 2 -- the sint/dflt/char/bool scalar families and
// the print leaves the RESOLVED prelude reaches in USER programs (the psuite
// exercises simpler prelude chains than the compiler: `print`, sint arith).
// Print leaves all route through the ONE default channel (xatsStorePut via
// the un-prefixed helpers) so interleaving matches the JS driver's
// store-then-flush model byte-for-byte.
// ////////////////////////////////////////////////////////////////

var Xats_XATS2JS_sint_add_sint = func(a any, b any) any { return a.(int) + b.(int) }
var Xats_XATS2JS_sint_sub_sint = func(a any, b any) any { return a.(int) - b.(int) }
var Xats_XATS2JS_sint_mul_sint = func(a any, b any) any { return a.(int) * b.(int) }
var Xats_XATS2JS_sint_div_sint = func(a any, b any) any { return a.(int) / b.(int) } // trunc toward 0 == JS Math.trunc
var Xats_XATS2JS_sint_mod_sint = func(a any, b any) any { return a.(int) % b.(int) }
var Xats_XATS2JS_sint_neg = func(a any) any { return -a.(int) }
var Xats_XATS2JS_sint_eq_sint = func(a any, b any) any { return a.(int) == b.(int) }
var Xats_XATS2JS_sint_neq_sint = func(a any, b any) any { return a.(int) != b.(int) }
var Xats_XATS2JS_sint_lt_sint = func(a any, b any) any { return a.(int) < b.(int) }
var Xats_XATS2JS_sint_lte_sint = func(a any, b any) any { return a.(int) <= b.(int) }
var Xats_XATS2JS_sint_gt_sint = func(a any, b any) any { return a.(int) > b.(int) }
var Xats_XATS2JS_sint_gte_sint = func(a any, b any) any { return a.(int) >= b.(int) }

var Xats_XATS2JS_dflt_add_dflt = func(a any, b any) any { return Xats_as_dflt(a) + Xats_as_dflt(b) }
var Xats_XATS2JS_dflt_sub_dflt = func(a any, b any) any { return Xats_as_dflt(a) - Xats_as_dflt(b) }
var Xats_XATS2JS_dflt_mul_dflt = func(a any, b any) any { return Xats_as_dflt(a) * Xats_as_dflt(b) }
var Xats_XATS2JS_dflt_div_dflt = func(a any, b any) any { return Xats_as_dflt(a) / Xats_as_dflt(b) }
var Xats_XATS2JS_dflt_lt_dflt = func(a any, b any) any { return Xats_as_dflt(a) < Xats_as_dflt(b) }

var Xats_XATS2JS_char_lt = func(a any, b any) any { return xatsRuneOf(a) < xatsRuneOf(b) }
var Xats_XATS2JS_char_lte = func(a any, b any) any { return xatsRuneOf(a) <= xatsRuneOf(b) }
var Xats_XATS2JS_char_gte = func(a any, b any) any { return xatsRuneOf(a) >= xatsRuneOf(b) }

var Xats_XATS2JS_bool_eq = func(a any, b any) any { return a.(bool) == b.(bool) }
var Xats_XATS2JS_bool_neq = func(a any, b any) any { return a.(bool) != b.(bool) }

// strn_cmp: lexicographic -1/0/1 (the JS reference compares code units;
// strings.Compare is bytewise -- identical ordering for ASCII sources).
var Xats_XATS2JS_strn_cmp = func(a any, b any) any { return strings.Compare(a.(string), b.(string)) }

// strn_get_at_raw: the unchecked charCodeAt (same unit model as strn_get_at).
var Xats_XATS2JS_strn_get_at_raw = Xats_XATS2JS_strn_get_at

// print leaves: one channel (the store choke point), flushed at exit.
var Xats_XATS2JS_strn_print = Xats_strn_print

func Xats_XATS2JS_NODE_strn_print(cs any) any { return Xats_strn_print(cs) }
func Xats_XATS2JS_NODE_sint_print(i int) any {
	XATS2JS_strn_print(strconv.Itoa(i))
	return XATSNIL()
}

var Xats_XATS2JS_sint_print = func(i any) any {
	XATS2JS_strn_print(strconv.Itoa(i.(int)))
	return XATSNIL()
}
var Xats_XATS2JS_dflt_print = func(f any) any {
	XATS2JS_strn_print(XatsFloatToString(Xats_as_dflt(f)))
	return XATSNIL()
}
var Xats_XATS2JS_char_print = func(c any) any {
	XATS2JS_strn_print(string(xatsRuneOf(c)))
	return XATSNIL()
}
var Xats_XATS2JS_console_log = func(x any) any {
	XATS2JS_console_log(x)
	return XATSNIL()
}
var Xats_XATS2JS_the_print_store_flush = func() any {
	return XATS2JS_the_print_store_flush()
}

// XATS000_strn_get_at_raw: the srcgen1-core-prefixed alias of the unchecked
// charCodeAt (test94's foritm chain resolves through the XATS000_ extern).
var Xats_XATS000_strn_get_at_raw = Xats_XATS2JS_strn_get_at

// LOUD FAILURES for datacon access with no constructor evidence.  A layout is
// what fixes a field's OFFSET (F1 sits after a 16-byte `any` in one layout and
// after an 8-byte int in another), so guessing would read the wrong bytes
// silently.  If either of these is ever reached, the emitter lost the
// constructor somewhere upstream — see docs/11-datatype-representation.md.
func Xats_proj_nolayout(v any, i int) any {
	panic(fmt.Sprintf("xatsgo: datacon projection with no layout (field %d of %T)", i, v))
}
func Xats_lvalue_nolayout(v any) *any {
	panic(fmt.Sprintf("xatsgo: datacon lvalue with no layout (%T)", v))
}
