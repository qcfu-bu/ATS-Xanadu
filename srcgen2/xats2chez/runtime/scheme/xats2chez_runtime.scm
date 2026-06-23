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

;;;--------------------------------------------------------------------
;;; Scalars / coercions (the JS XATS* macros are mostly identity; Scheme
;;; is likewise dynamically typed, so these are identities/thin wrappers).
;;;--------------------------------------------------------------------
(define XATSTOP0 (if #f #f))           ; the unit/void value
(define (XATSSTR0 cs) cs)
(define (XATSSTRN cs) cs)

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

;;;====================================================================
;;; end of [xats2chez_runtime.scm]
;;;====================================================================
