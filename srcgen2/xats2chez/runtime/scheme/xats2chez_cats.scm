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

;;;--------------------------------------------------------------------
;;; jshmap — hash maps (the JS Map; symbol tables, environments).  Keys are
;;; compared by equal? (strings, ints, interned symbols).
;;;--------------------------------------------------------------------
(define (jshmap_make_nil) (make-hashtable equal-hash equal?))
(define (jshmap_size m) (hashtable-size m))
(define (jshmap_keyq m k) (hashtable-contains? m k))
(define (jshmap_search$tst m k) (hashtable-contains? m k))
(define (jshmap_get$at$raw m k) (hashtable-ref m k #f))
(define (jshmap_set$at$raw m k v) (hashtable-set! m k v))
(define (jshmap_insert$raw m k v) (hashtable-set! m k v))

;; mydict — the dictionary template (key -> item), built on jshmap.  search$opt
;; returns an option (#(0) none / #(1 item) some).  Polymorphic under Chez.
(define (mydict_make_nil) (make-hashtable equal-hash equal?))
(define (mydict_search$opt m k) (if (hashtable-contains? m k) (vector 1 (hashtable-ref m k #f)) (vector 0)))
(define (mydict_insert$any m k v) (hashtable-set! m k v))
(define (mydict_keyq m k) (hashtable-contains? m k))
(define (mydict_size m) (hashtable-size m))
;; NB: symbl_search$opt / symbl_insert$any are NOT bridged here — they are
;; template instances that CAPTURE the global symbol table (1-arg: the name),
;; so their bodies must be emitted by the compiler (the next self-hosting
;; frontier: emit template-instance bodies that close over module globals,
;; rather than erasing them).

;;;--------------------------------------------------------------------
;;; jsdasz / a1sz — sized arrays (vector-backed).
;;;--------------------------------------------------------------------
(define (jsdasz_make_nfun n f) (let ((v (make-vector n))) (let loop ((i 0)) (if (< i n) (begin (vector-set! v i (f i)) (loop (+ i 1))) v))))
(define (jsdasz_make_1val n x) (make-vector n x))
(define (jsdasz_length a) (vector-length a))
(define (jsdasz_get a i) (vector-ref a i))
(define (jsdasz_set a i x) (vector-set! a i x))
(define (XATS2JS_a1sz_length a) (vector-length a))
(define (XATS2JS_a1sz_lget a i) (vector-ref a i))
(define (XATS2JS_a1sz_lset a i x) (vector-set! a i x))

;;;--------------------------------------------------------------------
;;; Symbols (symbl) — minimal: a symbol IS its interned name string, so two
;;; symbols with the same name are eq? (identity).  Enough for the symbol
;;; tables / label comparisons the foundational libraries need.
;;;--------------------------------------------------------------------
(define the_symbl_table (make-hashtable string-hash string=?))
(define (symbl_make_name nm)
  (or (hashtable-ref the_symbl_table nm #f)
      (begin (hashtable-set! the_symbl_table nm nm) nm)))
(define (symbl_get_name s) s)
(define (symbl_cmp a b) (g_cmp (symbl_get_name a) (symbl_get_name b)))

;;;--------------------------------------------------------------------
;;; list_vt — linear lists (same vector rep as list: #(0) nil / #(1 h t) cons;
;;; "_vt" = linear/at-view, but under Chez GC there is nothing to free).
;;;--------------------------------------------------------------------
(define (list_vt_free xs) (if #f #f))
(define (list_vt_reverse0 xs)
  (let loop ((xs xs) (acc (vector 0)))
    (if (= (vector-ref xs 0) 0) acc
        (loop (vector-ref xs 2) (vector 1 (vector-ref xs 1) acc)))))
(define (list_vt_append0 xs ys)
  (let loop ((xs (list_vt_reverse0 xs)) (acc ys))
    (if (= (vector-ref xs 0) 0) acc
        (loop (vector-ref xs 2) (vector 1 (vector-ref xs 1) acc)))))

;;;--------------------------------------------------------------------
;;; String building from char-code lists / functions; misc string ops.
;;; A char is its integer code (see xats2chez_runtime.scm).
;;;--------------------------------------------------------------------
(define (strn_make_llist cs)
  ;; cs : a list (#(0) | #(1 code rest)) of char codes -> a Scheme string
  (let loop ((cs cs) (acc '()))
    (if (= (vector-ref cs 0) 0)
        (list->string (reverse acc))
        (loop (vector-ref cs 2) (cons (integer->char (vector-ref cs 1)) acc)))))
(define (strn_tabulate$f1un n f)
  ;; build an n-char string s where s[i] = (integer->char (f i))
  (let ((s (make-string n)))
    (let loop ((i 0)) (if (< i n) (begin (string-set! s i (integer->char (f i))) (loop (+ i 1))) s))))
(define (XATSOPT_strn_append_uint s u) (string-append s (number->string u)))
(define (strn_append s t) (string-append s t))
;; string -> a lazy char-code stream (strmcon: #(0) nil / #(1 code lazytail));
;; the whole stream is a memoized l0azy thunk.  Used by the lexer's char source.
(define (strn_strmize s)
  (let ((n (string-length s)))
    (let mk ((i 0))
      (XATS000_l0azy
        (lambda ()
          (if (>= i n) (vector 0)
              (vector 1 (char->integer (string-ref s i)) (mk (+ i 1)))))))))

;;;--------------------------------------------------------------------
;;; Variadic prerr (gs_prerrln_n* / gs_prerr_*) — like gs_print but to stderr.
;;;--------------------------------------------------------------------
(define (cats-prerr1 x) (display (xats_value_string x) (current-error-port)))
(define (gs_prerr_n0) XATSTOP0)
(define (gs_prerrln_n0) (newline (current-error-port)) XATSTOP0)
(define (gs_prerrln_n1 a) (cats-prerr1 a) (gs_prerrln_n0))
(define (gs_prerrln_n2 a b) (cats-prerr1 a) (cats-prerr1 b) (gs_prerrln_n0))
(define (gs_prerrln_n3 a b c) (cats-prerr1 a) (cats-prerr1 b) (cats-prerr1 c) (gs_prerrln_n0))

;;;--------------------------------------------------------------------
;;; Misc CATS floor.
;;;--------------------------------------------------------------------
(define (g_free x) (if #f #f))          ; linear free: GC no-op
(define (XATS000_g_free x) (if #f #f))

;;;====================================================================
;;; end of [xats2chez_cats.scm]  (grows as more compiler units are compiled)
;;;====================================================================
