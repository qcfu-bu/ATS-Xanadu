;;;====================================================================
;;; xats2chez_runtime.scm — the hand-written Chez Scheme runtime for code
;;; emitted by the xats2chez backend.  Analog of xats2js_js1emit.js +
;;; srcgen2_prelude.js: it replicates the JS runtime's OBSERVABLE semantics
;;; so emitted-program stdout matches the JS backend byte-for-byte.
;;;
;;; Value representation (mirrors the JS contract):
;;;   data constructor c(f0,f1,..) -> vector #(tag f0 f1 ..)  (tag = int)
;;;   flat tuple / record          -> vector #(f0 f1 ..)      (no tag)
;;;   mutable var / lvalue         -> a box (1-slot) / path cell
;;;   char                         -> integer code (JS charCodeAt)
;;;   bool/int/float/string        -> native Scheme values
;;;   exception                    -> raise / guard on a constructor vector
;;;====================================================================

;;;--------------------------------------------------------------------
;;; Core: data constructors, tuples, projection, match failure.
;;; (Used from M2+ once the emitter emits constructors/tuples/patterns.)
;;;--------------------------------------------------------------------

;; constructor application: tag is a small int at slot 0, fields follow.
(define (XATSCAPP tag . fs) (list->vector (cons tag fs)))
;; constructor-tag test:  v[0] == t
(define (XATS000_ctgeq v t) (= (vector-ref v 0) t))
;; project constructor field i (skip the tag at slot 0).
(define (XATSPCON pcon i) (vector-ref pcon (+ i 1)))
;; flat tuple / record construction + projection (no tag).
(define (XATSTUP0 . fs) (list->vector fs))
(define (XATSP0RJ tup i) (vector-ref tup i))

;; non-exhaustive match failure (JS: throw new Error("XATS000_cfail")).
(define (XATS000_cfail)
  (error 'XATS000_cfail "non-exhaustive pattern match"))

;; linear-type markers: no-ops under Chez GC.
(define (XATS000_fold pcon) #f)
(define (XATS000_free pcon) #f)

;; exceptions.
(define (XATS000_raise xcon) (raise xcon))

;; lazy thunks (mirrors JS): level-0 is MEMOIZED, level-1 is call-by-name.
;;   l0azy = #(forced-count thunk-or-value); dl0az forces once then caches.
(define (XATS000_l0azy thunk) (vector 0 thunk))
(define (XATS000_dl0az lz)
  (if (> (vector-ref lz 0) 0)
      (begin (vector-set! lz 0 (+ (vector-ref lz 0) 1)) (vector-ref lz 1))
      (let ((res ((vector-ref lz 1))))
        (vector-set! lz 0 1) (vector-set! lz 1 res) res)))
(define (XATS000_l1azy thunk) thunk)
(define (XATS000_dl1az lz) (lz 1))

;;;--------------------------------------------------------------------
;;; Scalars / coercions (the JS XATS* macros are mostly identity; Scheme
;;; is likewise dynamically typed, so these are identities/thin wrappers).
;;;--------------------------------------------------------------------
(define XATSTOP0 (if #f #f))           ; the unit/void value
(define (XATSSTR0 cs) cs)
(define (XATSSTRN cs) cs)
;; char literal: emitter writes XATSCHR0("<glyph>"); runtime -> integer code
;; (mirrors JS charCodeAt(0)).  A char is its integer code at runtime.
(define (XATSCHR0 s) (char->integer (string-ref s 0)))

;;;--------------------------------------------------------------------
;;; The print store (mirrors srcgen2_prelude.js lines 48-100, 938-943).
;;;   the_print_store : an ordered accumulator of strings
;;;   XATS2JS_strn_print(cs)            : push cs
;;;   XATS2JS_the_print_store_flush()   : join "", clear, return the string
;;;   XATS2JS_console_log(x)            : print x followed by a newline
;;; Implemented with a box holding the pushed strings in REVERSE order
;;; (cons-to-front), reversed at flush — semantically identical to JS push.
;;;--------------------------------------------------------------------
(define the_print_store (box '()))

(define (XATS2JS_strn_print cs)
  (set-box! the_print_store (cons cs (unbox the_print_store)))
  XATSTOP0)

(define (XATS2JS_the_print_store_flush)
  (let ((s (apply string-append (reverse (unbox the_print_store)))))
    (set-box! the_print_store '())
    s))

(define (XATS2JS_the_print_store_clear)
  (set-box! the_print_store '())
  XATSTOP0)

(define (XATS2JS_console_log x)
  (display x) (newline) XATSTOP0)

;;;--------------------------------------------------------------------
;;; User-facing prelude print API (the emitter emits these names directly;
;;; each is the thin wrapper the prelude's template instance resolves to —
;;; see the test01 intrep0 dump).
;;;--------------------------------------------------------------------
(define (XATS000_strn_print cs) (XATS2JS_strn_print cs))
(define (strn_print cs)         (XATS2JS_strn_print cs))
(define (the_print_store_flush) (XATS2JS_the_print_store_flush))
(define (console_log x)         (XATS2JS_console_log x))
;; the_print_store_log() = console_log(the_print_store_flush())
(define (the_print_store_log)   (console_log (the_print_store_flush)))

;;;--------------------------------------------------------------------
;;; Prelude scalar ops (monomorphic instances the emitter emits by name).
;;; Integer (sint) arithmetic matches ATS/C semantics: truncating division
;;; (quotient, toward zero) and dividend-signed remainder.  Print ops push
;;; the value's string form onto the print store (like strn_print).
;;;--------------------------------------------------------------------

;; integer arithmetic
(define (sint_add$sint a b) (+ a b))
(define (sint_sub$sint a b) (- a b))
(define (sint_mul$sint a b) (* a b))
(define (sint_div$sint a b) (quotient a b))   ; trunc toward 0
(define (sint_mod$sint a b) (remainder a b))  ; sign of dividend
(define (sint_neg$sint a)   (- a))

;; integer comparison -> bool
(define (sint_lt$sint  a b) (< a b))
(define (sint_gt$sint  a b) (> a b))
(define (sint_lte$sint a b) (<= a b))
(define (sint_gte$sint a b) (>= a b))
(define (sint_eq$sint  a b) (= a b))
(define (sint_neq$sint a b) (not (= a b)))

;; bool ops
(define (bool_eq  a b) (eq? a b))
(define (bool_neq a b) (not (eq? a b)))
(define (bool_not a)   (not a))

;; float (dflt) arithmetic / comparison
(define (dflt_add$dflt a b) (fl+ a b))
(define (dflt_sub$dflt a b) (fl- a b))
(define (dflt_mul$dflt a b) (fl* a b))
(define (dflt_div$dflt a b) (fl/ a b))
(define (dflt_neg$dflt a)   (fl- a))
(define (dflt_lt$dflt  a b) (fl< a b))
(define (dflt_gt$dflt  a b) (fl> a b))
(define (dflt_lte$dflt a b) (fl<= a b))
(define (dflt_gte$dflt a b) (fl>= a b))
(define (dflt_eq$dflt  a b) (fl= a b))
(define (dflt_neq$dflt a b) (not (fl= a b)))

;; char ops: a char is its integer code (matches JS charCodeAt).
(define (char_eq  a b) (= a b))
(define (char_neq a b) (not (= a b)))
(define (char_lt  a b) (< a b))
(define (char_gt  a b) (> a b))

;; print ops (match JS String(): ints decimal, bools "true"/"false",
;; floats via Number.toString() — whole-valued floats print without ".0",
;; a char prints as its single glyph).
(define (xats_sint_tostring n) (number->string n))
(define (xats_bool_tostring b) (if b "true" "false"))
(define (xats_dflt_tostring x)
  (if (and (flonum? x) (integer? x) (not (infinite? x)) (not (nan? x)))
      (number->string (exact x))     ; 2.0 -> "2"  (JS Number.toString)
      (number->string x)))           ; 2.5 -> "2.5"
(define (sint_print n) (XATS2JS_strn_print (xats_sint_tostring n)))
(define (bool_print b) (XATS2JS_strn_print (xats_bool_tostring b)))
(define (dflt_print x) (XATS2JS_strn_print (xats_dflt_tostring x)))
(define (char_print c) (XATS2JS_strn_print (string (integer->char c))))

;;;--------------------------------------------------------------------
;;; Prelude list ops.  A list is a constructor vector:
;;;   list_nil  = #(0)            list_cons(h,t) = #(1 h t)
;;;--------------------------------------------------------------------
(define (list_nil) (vector 0))
(define (list_cons h t) (vector 1 h t))
(define (list_length xs)
  (let loop ((xs xs) (n 0))
    (if (= (vector-ref xs 0) 0) n (loop (vector-ref xs 2) (+ n 1)))))
(define (list_reverse xs)
  (let loop ((xs xs) (acc (vector 0)))
    (if (= (vector-ref xs 0) 0) acc
        (loop (vector-ref xs 2) (vector 1 (vector-ref xs 1) acc)))))

;;;--------------------------------------------------------------------
;;; Prelude string (strn) ops.  ATS strings are Scheme strings; a char is an
;;; integer code, so strn_get_at returns the code.
;;;--------------------------------------------------------------------
(define (strn_length s) (string-length s))
(define (strn_eq a b) (string=? a b))
(define (strn_neq a b) (not (string=? a b)))
(define (strn_lt a b) (string<? a b))
(define (strn_gt a b) (string>? a b))
(define (strn_append a b) (string-append a b))
(define (strn_get_at s i) (char->integer (string-ref s i)))
(define (strn_get$at s i) (char->integer (string-ref s i)))
(define (XATS000_strn_get_at_raw s i) (char->integer (string-ref s i)))

;;;--------------------------------------------------------------------
;;; Misc: the ATS don't-care value [_]; generic value->string; variadic
;;; prints (gs_print_aN / gs_println_aN) that push each arg's string form
;;; onto the print store (matching the JS backend's per-arg stringification).
;;;--------------------------------------------------------------------
(define _xunit XATSTOP0)

(define (xats_value_string x)
  (cond ((string? x) x)
        ((flonum? x) (xats_dflt_tostring x))
        ((number? x) (number->string x))
        ((boolean? x) (if x "true" "false"))
        ((char? x) (string x))
        (else "?")))

(define (gs_print_one x) (XATS2JS_strn_print (xats_value_string x)))
(define (gs_print_a0) XATSTOP0)
(define (gs_print_a1 a) (gs_print_one a) XATSTOP0)
(define (gs_print_a2 a b) (gs_print_one a) (gs_print_one b) XATSTOP0)
(define (gs_print_a3 a b c) (gs_print_one a) (gs_print_one b) (gs_print_one c) XATSTOP0)
(define (gs_print_a4 a b c d) (gs_print_one a) (gs_print_one b) (gs_print_one c) (gs_print_one d) XATSTOP0)
(define (gs_println_a0) (XATS2JS_console_log (XATS2JS_the_print_store_flush)))
(define (gs_println_a1 a) (gs_print_one a) (gs_println_a0))
(define (gs_println_a2 a b) (gs_print_one a) (gs_print_one b) (gs_println_a0))
(define (gs_println_a3 a b c) (gs_print_one a) (gs_print_one b) (gs_print_one c) (gs_println_a0))

;;;====================================================================
;;; end of [xats2chez_runtime.scm]
;;;====================================================================
