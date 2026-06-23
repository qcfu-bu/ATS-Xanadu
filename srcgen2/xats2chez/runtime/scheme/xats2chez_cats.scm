;;;====================================================================
;;; xats2chez_cats.scm — the CATS runtime for SELF-HOSTING.
;;;
;;; This is the hand-written floor of leaf primitives the COMPILER's own
;;; compiled-to-Scheme code bottoms out at (the analog of the JS backend's
;;; srcgen2_prelude.js / precats.js / xatslib.js, but only the genuinely
;;; primitive `$extnam`/CATS operations — anything written in ATS is COMPILED
;;; by the chez emitter, not hand-written here).
;;;
;;; Built EMPIRICALLY: compile a compiler unit to Scheme, run it on Chez,
;;; resolve each undefined symbol here, repeat.  Started from the deps of
;;; xstamp0 (the stamp counter) and grows outward toward the full frontend.
;;;
;;; Loaded BEFORE xats2chez_runtime.scm (which adds the value-rep core and the
;;; print store) and before the compiled compiler Scheme.
;;;====================================================================

;;;--------------------------------------------------------------------
;;; Generic integers (gint).  ATS distinguishes sint/uint/etc. statically;
;;; at runtime they are all Scheme integers, so casts are identities and the
;;; ops are the native integer ops.  `$uint`/`$sint` are template-instance
;;; suffixes the emitter passes through verbatim.
;;;--------------------------------------------------------------------
(define (gint_sint2uint n) n)
(define (gint_uint2sint n) n)
(define (gint_sint2int  n) n)
(define (gint_int2sint  n) n)

(define (gint_suc$uint n) (+ n 1))
(define (gint_suc$sint n) (+ n 1))
(define (gint_pred$uint n) (- n 1))
(define (gint_pred$sint n) (- n 1))

(define (gint_add$uint$uint a b) (+ a b))
(define (gint_sub$uint$uint a b) (- a b))
(define (gint_add$sint$sint a b) (+ a b))
(define (gint_sub$sint$sint a b) (- a b))

(define (gint_eq$uint$uint a b) (= a b))
(define (gint_neq$uint$uint a b) (not (= a b)))
(define (gint_lt$uint$uint a b) (< a b))
(define (gint_gt$uint$uint a b) (> a b))
(define (gint_eq$sint$sint a b) (= a b))
(define (gint_neq$sint$sint a b) (not (= a b)))
(define (gint_lt$sint$sint a b) (< a b))
(define (gint_gt$sint$sint a b) (> a b))

(define (gint_gte$uint$uint a b) (>= a b))
(define (gint_lte$uint$uint a b) (<= a b))
(define (gint_gte$sint$sint a b) (>= a b))
(define (gint_lte$sint$sint a b) (<= a b))

;; comparison -> a sign: -1 / 0 / 1
(define (gint_cmp$uint$uint a b) (cond ((< a b) -1) ((> a b) 1) (else 0)))
(define (gint_cmp$sint$sint a b) (cond ((< a b) -1) ((> a b) 1) (else 0)))

;; negation / mul / div / mod / abs / min / max
(define (gint_neg$sint n) (- n))
(define (gint_neg$uint n) (- n))
(define (gint_mul$sint$sint a b) (* a b))
(define (gint_mul$uint$uint a b) (* a b))
(define (gint_div$sint$sint a b) (quotient a b))
(define (gint_div$uint$uint a b) (quotient a b))
(define (gint_mod$sint$sint a b) (remainder a b))
(define (gint_mod$uint$uint a b) (remainder a b))
(define (gint_abs$sint n) (abs n))
(define (gint_min$sint$sint a b) (min a b))
(define (gint_max$sint$sint a b) (max a b))
(define (gint_min$uint$uint a b) (min a b))
(define (gint_max$uint$uint a b) (max a b))

;; bitwise / shifts (R6RS bitwise ops; asrn/asln shift by a count)
(define (gint_land$uint a b) (bitwise-and a b))
(define (gint_land$sint a b) (bitwise-and a b))
(define (gint_lor$uint a b) (bitwise-ior a b))
(define (gint_lor$sint a b) (bitwise-ior a b))
(define (gint_lxor$uint a b) (bitwise-xor a b))
(define (gint_asln$sint a k) (bitwise-arithmetic-shift a k))
(define (gint_asln$uint a k) (bitwise-arithmetic-shift a k))
(define (gint_asrn$sint a k) (bitwise-arithmetic-shift a (- k)))
(define (gint_asrn$uint a k) (bitwise-arithmetic-shift a (- k)))

;;;--------------------------------------------------------------------
;;; Generic compare / min / max (g_cmp<T> etc.).  In well-typed ATS these are
;;; specialized per type; the compiler also calls bare generic forms (on ints,
;;; chars, strings).  Scheme is dynamically typed, so one polymorphic version
;;; dispatches on the operand kind.  (cmp returns a sign -1/0/1.)
;;;--------------------------------------------------------------------
(define (g_cmp a b)
  (cond ((and (number? a) (number? b)) (cond ((< a b) -1) ((> a b) 1) (else 0)))
        ((and (string? a) (string? b)) (cond ((string<? a b) -1) ((string>? a b) 1) (else 0)))
        (else 0)))
(define (g_min a b) (if (<= (g_cmp a b) 0) a b))
(define (g_max a b) (if (>= (g_cmp a b) 0) a b))
(define (g_eq a b) (equal? a b))
(define (g_neq a b) (not (equal? a b)))

;;;--------------------------------------------------------------------
;;; a0ref — a single-value mutable reference (the JS XATS2JS_a0rf_*).
;;; Represented as a Scheme box.
;;;--------------------------------------------------------------------
(define (a0ref_make_1val v) (box v))
(define (a0ref_get r) (unbox r))
(define (a0ref_set r v) (set-box! r v))
;; the names the emitter may also produce ($extnam form):
(define (XATS2JS_a0rf_make_1val v) (box v))
(define (XATS2JS_a0rf_lget r) (unbox r))
(define (XATS2JS_a0rf_lset r v) (set-box! r v))

;;;====================================================================
;;; end of [xats2chez_cats.scm]  (grows as more compiler units are compiled)
;;;====================================================================
