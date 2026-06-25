;;; xats2cz_runtime.scm — Chez runtime for emitted ATS3 programs.
;;;
;;; M1: minimal & clean.  Grows per milestone — each primitive faithful to the
;;; authoritative JS contract (srcgen2_prelude.js / prelude .cats), NOT inherited
;;; from the prior attempt's CATS/CHEZ.
;;;
;;; Value rep (honored by cz0emit):
;;;   datacon = #(tag field ...) ; tuple = #(field ...) ; char = integer code.
;;; unit = the _xunit value below.

(define _xunit (if #f #f))                 ; the ATS unit value (Chez "void")

;;; match failure (falling off the end of a case with no matching clause).
(define (XATS000_cfail) (error 'xats2cz "match (case) failure"))

;;; ---- datatypes: datacon = #(ctag field ...) ; tuple/record = #(field ...) ----
(define (XATS000_ctgeq v t) (= (vector-ref v 0) t))   ; tag test (slot 0)
(define (XATSPCON con i) (vector-ref con (+ i 1)))      ; datacon field i (skip ctag)

;;; ---- mutable left-values: a var is a Chez box; a field-address is #(cell idx).
;;; XATS_lvget/lvset dispatch on box? so both shapes read/write uniformly. ----
(define (XATS_lvget x)
  (if (box? x) (unbox x) (vector-ref (vector-ref x 0) (vector-ref x 1))))
(define (XATS_lvset x v)
  (if (box? x) (set-box! x v) (vector-set! (vector-ref x 0) (vector-ref x 1) v)))
(define (p2tr_get p) (XATS_lvget p))
(define (p2tr_set p v) (XATS_lvset p v))

;;; ---- lazy: l0azy MEMOIZES (#(forced? thunk/value)); l1azy is call-by-name. ----
(define (XATS000_l0azy thunk) (vector 0 thunk))
(define (XATS000_dl0az lz)
  (if (> (vector-ref lz 0) 0)
      (vector-ref lz 1)
      (let ((res ((vector-ref lz 1))))
        (vector-set! lz 0 1) (vector-set! lz 1 res) res)))
(define (XATS000_l1azy thunk) thunk)
(define (XATS000_dl1az lz) (lz 1))

;;; ---- print store (mirrors XATS2JS_the_print_store in srcgen2_prelude.js) ----
;;; A list of pushed strings, kept in reverse; flush joins in order and clears.
(define XATS2JS_the_print_store '())

(define (XATS2JS_sint_print i)
  (set! XATS2JS_the_print_store
        (cons (number->string i) XATS2JS_the_print_store))
  _xunit)

(define (XATS2JS_strn_print s)
  (set! XATS2JS_the_print_store (cons s XATS2JS_the_print_store))
  _xunit)

(define (XATS2JS_the_print_store_clear)
  (set! XATS2JS_the_print_store '())
  _xunit)

(define (XATS2JS_the_print_store_flush)
  (let ((cs (apply string-append (reverse XATS2JS_the_print_store))))
    (set! XATS2JS_the_print_store '())
    cs))

;;; console.log(s): writes s then a newline (matches Node console.log).
(define (XATS2JS_console_log s)
  (display s) (newline)
  _xunit)

;;; ---- NODE prelude: print DIRECTLY to stdout (process.stdout.write x.toString()),
;;; not via the print store.  Match JS x.toString() formatting. ----
(define (XATS2JS_NODE_g_print x)    (display x) _xunit)
(define (XATS2JS_NODE_sint_print i) (display i) _xunit)
(define (XATS2JS_NODE_uint_print u) (display u) _xunit)
(define (XATS2JS_NODE_strn_print s) (display s) _xunit)
(define (XATS2JS_NODE_bool_print b) (display (if b "true" "false")) _xunit)
(define (XATS2JS_NODE_char_print c) (display (string (integer->char c))) _xunit)
(define (XATS2JS_NODE_dflt_print f) (display (xats_dflt_tostring f)) _xunit)

;;; ---- sint arithmetic (mirrors srcgen2_prelude.js:314-346) ----
;;; div = Math.trunc(i1/i2) -> quotient (truncates toward zero in Chez);
;;; mod = JS % (sign of dividend) -> remainder (sign of dividend in Chez).
(define (XATS2JS_sint_add$sint i1 i2) (+ i1 i2))
(define (XATS2JS_sint_sub$sint i1 i2) (- i1 i2))
(define (XATS2JS_sint_mul$sint i1 i2) (* i1 i2))
(define (XATS2JS_sint_div$sint i1 i2) (quotient i1 i2))
(define (XATS2JS_sint_mod$sint i1 i2) (remainder i1 i2))

;;; ---- strings (value rep = Scheme string) ----
(define (XATS2JS_strn_length cs) (string-length cs))
(define (XATS2JS_strn_get$at$raw cs i) (char->integer (string-ref cs i)))
(define (XATS2JS_strn_get$at cs i) (char->integer (string-ref cs i)))
;; lexicographic by char code; first nonzero code diff, else (n1 - n2) (matches JS).
(define (XATS2JS_strn_cmp x1 x2)
  (let* ((n1 (string-length x1)) (n2 (string-length x2)) (n0 (min n1 n2)))
    (let loop ((i 0))
      (if (< i n0)
          (let ((df (- (char->integer (string-ref x1 i)) (char->integer (string-ref x2 i)))))
            (if (not (= df 0)) df (loop (+ i 1))))
          (- n1 n2)))))
(define (XATS2JS_strn_eq x1 x2) (string=? x1 x2))
(define (XATS2JS_strn_neq x1 x2) (not (string=? x1 x2)))
;; XATS000_* generic aliases (some prelude paths use the generic name).
(define XATS000_strn_length XATS2JS_strn_length)
(define XATS000_strn_get$at$raw XATS2JS_strn_get$at$raw)
(define XATS000_strn_cmp XATS2JS_strn_cmp)
(define (XATS000_strn_print s) (XATS2JS_strn_print s))

;;; ---- sint comparisons (return Scheme booleans = the ATS bool rep) ----
(define (XATS2JS_sint_lt$sint  i1 i2) (< i1 i2))
(define (XATS2JS_sint_gt$sint  i1 i2) (> i1 i2))
(define (XATS2JS_sint_lte$sint i1 i2) (<= i1 i2))
(define (XATS2JS_sint_gte$sint i1 i2) (>= i1 i2))
(define (XATS2JS_sint_eq$sint  i1 i2) (= i1 i2))
(define (XATS2JS_sint_neq$sint i1 i2) (not (= i1 i2)))

;;; ---- bool ----
(define (XATS2JS_bool_eq  b1 b2) (eq? b1 b2))
(define (XATS2JS_bool_neq b1 b2) (not (eq? b1 b2)))

;;; ---- char (value rep = integer code) ----
;;; XATSCHR0: a 1-char source string -> its integer code (char literal emission).
(define (XATSCHR0 s) (char->integer (string-ref s 0)))
(define (XATS2JS_char_lt  c1 c2) (< c1 c2))
(define (XATS2JS_char_lte c1 c2) (<= c1 c2))
(define (XATS2JS_char_gt  c1 c2) (> c1 c2))
(define (XATS2JS_char_gte c1 c2) (>= c1 c2))
(define (XATS2JS_char_eq  c1 c2) (= c1 c2))
(define (XATS2JS_char_neq c1 c2) (not (= c1 c2)))
(define (XATS2JS_char_print c0)
  (set! XATS2JS_the_print_store
        (cons (string (integer->char c0)) XATS2JS_the_print_store))
  _xunit)

;;; ---- dflt (float) ----
(define (XATS2JS_dflt_add$dflt f1 f2) (+ f1 f2))
(define (XATS2JS_dflt_sub$dflt f1 f2) (- f1 f2))
(define (XATS2JS_dflt_mul$dflt f1 f2) (* f1 f2))
(define (XATS2JS_dflt_div$dflt f1 f2) (/ f1 f2))
(define (XATS2JS_dflt_lt$dflt  f1 f2) (< f1 f2))

;;; JS Number.toString(): an integer-valued float prints WITHOUT ".0" (10.0 -> "10").
(define (xats_dflt_tostring f)
  (if (and (not (nan? f)) (not (infinite? f)) (= f (floor f)))
      (number->string (exact (floor f)))
      (number->string f)))
(define (XATS2JS_dflt_print f0)
  (set! XATS2JS_the_print_store
        (cons (xats_dflt_tostring f0) XATS2JS_the_print_store))
  _xunit)
