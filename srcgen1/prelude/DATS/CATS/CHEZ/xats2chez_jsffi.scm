;;;====================================================================
;;; xats2chez_jsffi.scm — a MECHANICAL port of the srcgen1 JS backend FFI
;;; primitives (prelude/DATS/CATS/JS/*.cats) to Chez Scheme.
;;;
;;; One (define (XATS2JS_name args) body) per JS `function XATS2JS_*` (and the
;;; XATSOPT_* ones), keeping the EXACT JS names (with `$`).  Value reps follow
;;; the CHEZ contract (NOT the JS tags):
;;;   number (int|float) -> Scheme number;  char -> integer code
;;;   bool -> #t/#f;  string -> Scheme string;  JS array -> Scheme vector
;;;   a0ref / mutable ref -> Scheme box;  void -> (if #f #f)
;;;   datacon / option -> 0-BASED tagged vector (None=#(0), Some=#(1 x), ...)
;;;
;;; Names ALREADY defined in the other CHEZ runtime files are SKIPPED here:
;;;   XATS2JS_strn_print, XATS2JS_the_print_store_clear,
;;;   XATS2JS_the_print_store_flush, XATS2JS_console_log, XATS2JS_a0ref_set,
;;;   XATSOPT_strn_append_uint.
;;;
;;; Loaded alongside the other CHEZ runtime .scm files.
;;;====================================================================

;;;====================================================================
;;; basics1.cats — bool / char / int / float / string primitives
;;;====================================================================

;; prelude/bool000.sats
(define (XATS2JS_bool_neg b0) (not b0))
(define (XATS2JS_bool_add b1 b2) (or b1 b2))
(define (XATS2JS_bool_mul b1 b2) (and b1 b2))

;; prelude/char000.sats  (a char is its integer code)
(define (XATS2JS_char_eq c1 c2) (= c1 c2))
(define (XATS2JS_char_neq c1 c2) (not (= c1 c2)))
(define (XATS2JS_char_cmp c1 c2)
  (if (< c1 c2) -1 (if (<= c1 c2) 0 1)))
(define (XATS2JS_char_eqz c0) (= 0 c0))
(define (XATS2JS_char_neqz c0) (not (= 0 c0)))
(define (XATS2JS_char_equal c1 c2) (= c1 c2))
(define (XATS2JS_char_noteq c1 c2) (not (= c1 c2)))

(define (XATS2JS_char_lowerq ch) (and (<= 97 ch) (<= ch 122)))
(define (XATS2JS_sint_lowerq ch) (and (<= 97 ch) (<= ch 122)))
(define (XATS2JS_char_upperq ch) (and (<= 65 ch) (<= ch 90)))
(define (XATS2JS_sint_upperq ch) (and (<= 65 ch) (<= ch 90)))

(define (XATS2JS_char_isdigit ch) (and (<= 48 ch) (<= ch 57)))
(define (XATS2JS_sint_isdigit ch) (and (<= 48 ch) (<= ch 57)))

(define (XATS2JS_char_isalpha ch)
  (or (XATS2JS_char_lowerq ch) (XATS2JS_char_upperq ch)))
(define (XATS2JS_sint_isalpha ch)
  (or (XATS2JS_sint_lowerq ch) (XATS2JS_sint_upperq ch)))

(define (XATS2JS_char_isalnum ch)
  (or (XATS2JS_char_isalpha ch) (XATS2JS_char_isdigit ch)))
(define (XATS2JS_sint_isalnum ch)
  (or (XATS2JS_sint_isalpha ch) (XATS2JS_sint_isdigit ch)))

(define (XATS2JS_char_lohexq ch) (and (<= 97 ch) (<= ch 102)))
;; NB: the JS source defines XATS2JS_sint_lohexq TWICE (the 2nd shadows the 1st
;; and is really an UPPER-hex check 65..70).  JS keeps the last def; we follow
;; suit (65..70), so XATS2JS_sint_lohexq below ends up = the upper-hex range.
(define (XATS2JS_char_uphexq ch) (and (<= 65 ch) (<= ch 70)))
(define (XATS2JS_sint_lohexq ch) (and (<= 65 ch) (<= ch 70)))

(define (XATS2JS_char_isxdigit ch)
  (or (XATS2JS_char_isdigit ch) (XATS2JS_char_lohexq ch) (XATS2JS_char_uphexq ch)))
;; NB: the JS body references XATS2JS_sint_uphexq, which is never defined in the
;; source (the 2nd sint_lohexq took its place).  Kept faithful: this calls the
;; same not-defined name, so it errors only if invoked — matching JS.
(define (XATS2JS_sint_isxdigit ch)
  (or (XATS2JS_sint_isdigit ch) (XATS2JS_sint_lohexq ch) (XATS2JS_sint_uphexq ch)))

;; prelude/gint000.sats
(define (XATS2JS_gint_neg$sint x0) (- x0))
(define (XATS2JS_gint_abs$sint x0) (if (>= x0 0) x0 (- x0)))

(define (XATS2JS_sint_suc i0) (+ i0 1))
(define (XATS2JS_uint_suc u0) (+ u0 1))
(define (XATS2JS_gint_suc$sint x0) (+ x0 1))
(define (XATS2JS_gint_suc$uint x0) (+ x0 1))
(define (XATS2JS_gint_pre$sint x0) (- x0 1))
(define (XATS2JS_gint_pre$uint x0) (- x0 1))

;; bitwise / logical (JS ~, |, &, ^)
(define (XATS2JS_uint_lnot x0) (bitwise-not x0))
(define (XATS2JS_uint_ladd x0 y0) (bitwise-ior x0 y0))
(define (XATS2JS_uint_lmul x0 y0) (bitwise-and x0 y0))
(define (XATS2JS_uint_lneq x0 y0) (bitwise-xor x0 y0))
(define (XATS2JS_gint_lnot$uint x0) (bitwise-not x0))
(define (XATS2JS_gint_lor2$uint x0 y0) (bitwise-ior x0 y0))
(define (XATS2JS_gint_l2or$uint x0 y0) (bitwise-ior x0 y0))
(define (XATS2JS_gint_land$uint x0 y0) (bitwise-and x0 y0))
(define (XATS2JS_gint_lxor$uint x0 y0) (bitwise-xor x0 y0))

;; shifts (JS >>, <<, >>>)
(define (XATS2JS_gint_asrn$sint x0 n0) (bitwise-arithmetic-shift-right x0 n0))
(define (XATS2JS_gint_lsln$uint x0 n0) (bitwise-arithmetic-shift-left x0 n0))
(define (XATS2JS_gint_lsrn$uint x0 n0) (bitwise-arithmetic-shift-right x0 n0))

;; comparisons
(define (XATS2JS_gint_lt$sint$sint x1 x2) (< x1 x2))
(define (XATS2JS_gint_lt$uint$uint x1 x2) (< x1 x2))
(define (XATS2JS_gint_gt$sint$sint x1 x2) (> x1 x2))
(define (XATS2JS_gint_gt$uint$uint x1 x2) (> x1 x2))
(define (XATS2JS_gint_eq$sint$sint x1 x2) (= x1 x2))
(define (XATS2JS_gint_eq$uint$uint x1 x2) (= x1 x2))
(define (XATS2JS_gint_lte$sint$sint x1 x2) (<= x1 x2))
(define (XATS2JS_gint_lte$uint$uint x1 x2) (<= x1 x2))
(define (XATS2JS_gint_gte$sint$sint x1 x2) (>= x1 x2))
(define (XATS2JS_gint_gte$uint$uint x1 x2) (>= x1 x2))
(define (XATS2JS_gint_neq$sint$sint x1 x2) (not (= x1 x2)))
(define (XATS2JS_gint_neq$uint$uint x1 x2) (not (= x1 x2)))

(define (XATS2JS_gint_cmp$sint$sint x1 x2)
  (if (< x1 x2) -1 (if (<= x1 x2) 0 1)))
(define (XATS2JS_gint_cmp$uint$uint x1 x2)
  (if (< x1 x2) -1 (if (<= x1 x2) 0 1)))

;; arithmetic
(define (XATS2JS_gint_add$sint$sint x1 x2) (+ x1 x2))
(define (XATS2JS_gint_sub$sint$sint x1 x2) (- x1 x2))
(define (XATS2JS_gint_mul$sint$sint x1 x2) (* x1 x2))
(define (XATS2JS_gint_mod$sint$sint x1 x2) (remainder x1 x2))
;; JS div truncates toward zero (floor for q>=0, ceil for q<0) = quotient
(define (XATS2JS_gint_div$sint$sint x1 x2) (quotient x1 x2))
(define (XATS2JS_gint_add$uint$uint x1 x2) (+ x1 x2))
(define (XATS2JS_gint_sub$uint$uint x1 x2) (- x1 x2))

;; casts — identities
(define (XATS2JS_sint_to$uint x0) x0)
(define (XATS2JS_uint_to$sint x0) x0)
(define (XATS2JS_gint_sint2uint x0) x0)
(define (XATS2JS_gint_uint2sint x0) x0)

;; parse: JS parseInt(rep,10), NaN -> 0
(define (XATS2JS_gint_parse_sint rep)
  (let ((res (string->number rep 10)))
    (if (and res (integer? res)) res 0)))
(define (XATS2JS_gint_parse_uint rep)
  (let ((res (XATS2JS_gint_parse_sint rep)))
    (if (>= res 0) res 0)))

;; prelude/gflt000.sats  (floats are Scheme numbers)
(define (XATS2JS_gflt_si_dflt x0) x0)
(define (XATS2JS_gflt_neg_dflt x0) (- x0))
(define (XATS2JS_gflt_abs_dflt x0) (if (>= x0 0.0) x0 (- x0)))
(define (XATS2JS_gflt_suc_dflt x0) (+ x0 1))
(define (XATS2JS_gflt_pre_dflt x0) (- x0 1))
(define (XATS2JS_gflt_lt_dflt_dflt x1 x2) (< x1 x2))
(define (XATS2JS_gflt_gt_dflt_dflt x1 x2) (> x1 x2))
(define (XATS2JS_gflt_eq_dflt_dflt x1 x2) (= x1 x2))
(define (XATS2JS_gflt_lte_dflt_dflt x1 x2) (<= x1 x2))
(define (XATS2JS_gflt_gte_dflt_dflt x1 x2) (>= x1 x2))
(define (XATS2JS_gflt_neq_dflt_dflt x1 x2) (not (= x1 x2)))
(define (XATS2JS_gflt_cmp_dflt_dflt x1 x2)
  (if (< x1 x2) -1 (if (<= x1 x2) 0 1)))
(define (XATS2JS_gflt_add_dflt_dflt x1 x2) (+ x1 x2))
(define (XATS2JS_gflt_sub_dflt_dflt x1 x2) (- x1 x2))
(define (XATS2JS_gflt_mul_dflt_dflt x1 x2) (* x1 x2))
(define (XATS2JS_gflt_div_dflt_dflt x1 x2) (/ x1 x2))

;; prelude/strn000.sats
;; A (strn)-val is a Scheme string; a (strn_vt)/lstrn-val is a Scheme VECTOR of
;; char codes, terminated by a trailing 0 (the JS '\0' sentinel).
(define (XATS2JS_strn_vt2t cs)
  ;; cs : vector of char-codes ending with a 0 sentinel -> drop it, make a string
  (let* ((n (vector-length cs)))
    (let loop ((i 0) (acc '()))
      (if (>= i (- n 1))
          (list->string (reverse acc))
          (loop (+ i 1) (cons (integer->char (vector-ref cs i)) acc))))))

(define (XATS2JS_strn_nilq cs) (= 0 (string-length cs)))
(define (XATS2JS_strn_consq cs) (not (= 0 (string-length cs))))
;; stropt: none is the JS null -> we use #f as the none sentinel (matches the
;; existing stropt convention: some(s) = the string itself, none = non-string).
(define (XATS2JS_stropt_nilq opt) (not (string? opt)))
(define (XATS2JS_stropt_consq opt) (string? opt))

(define (XATS2JS_strn_lt x1 x2) (string<? x1 x2))
(define (XATS2JS_strn_gt x1 x2) (string>? x1 x2))
(define (XATS2JS_strn_eq x1 x2) (string=? x1 x2))
(define (XATS2JS_strn_lte x1 x2) (string<=? x1 x2))
(define (XATS2JS_strn_gte x1 x2) (string>=? x1 x2))
(define (XATS2JS_strn_neq x1 x2) (not (string=? x1 x2)))
(define (XATS2JS_strn_cmp x1 x2)
  (if (string<? x1 x2) -1 (if (string=? x1 x2) 0 1)))

(define (XATS2JS_strn_head$raw cs) (char->integer (string-ref cs 0)))
(define (XATS2JS_strn_head$opt cs)
  (if (<= (string-length cs) 0) 0 (char->integer (string-ref cs 0))))
(define (XATS2JS_strn_tail$raw cs) (substring cs 1 (string-length cs)))

(define (XATS2JS_strn_length cs) (string-length cs))
;; strn_vt is a vector with a trailing null sentinel -> length skips it
(define (XATS2JS_strn_vt_length0 cs) (- (vector-length cs) 1))
(define (XATS2JS_strn_vt_length1 cs) (- (vector-length cs) 1))

(define (XATS2JS_strn_get$at cs i0) (char->integer (string-ref cs i0)))
;; strn_vt: a vector of char codes
(define (XATS2JS_strn_vt_get$at cs i0) (vector-ref cs i0))
(define (XATS2JS_strn_vt_set$at cs i0 c0) (vector-set! cs i0 c0))

(define (XATS2JS_strtmp_vt_alloc bsz)
  (let ((cs (make-vector (+ bsz 1))))
    (vector-set! cs bsz 0) cs))
(define (XATS2JS_strtmp_vt_set$at cs i0 c0) (vector-set! cs i0 c0))

;; forall over a (string) of char codes
(define (XATS2JS_strn_forall$f1un cs f0)
  (let ((len (string-length cs)))
    (let loop ((i0 0))
      (cond ((>= i0 len) #t)
            ((not (f0 (char->integer (string-ref cs i0)))) #f)
            (else (loop (+ i0 1)))))))
(define (XATS2JS_strn_rforall$f1un cs f0)
  (let ((len (string-length cs)))
    (let loop ((i0 len))
      (cond ((< i0 1) #t)
            ((not (f0 (char->integer (string-ref cs (- i0 1))))) #f)
            (else (loop (- i0 1)))))))
;; forall over a (strn_vt) vector of char codes (skip trailing null)
(define (XATS2JS_strn_vt_forall$f1un cs f0)
  (let ((len (- (vector-length cs) 1)))
    (let loop ((i0 0))
      (cond ((>= i0 len) #t)
            ((not (f0 (vector-ref cs i0))) #f)
            (else (loop (+ i0 1)))))))
(define (XATS2JS_strn_vt_rforall$f1un cs f0)
  (let ((len (- (vector-length cs) 1)))
    (let loop ((i0 len))
      (cond ((< i0 1) #t)
            ((not (f0 (vector-ref cs (- i0 1)))) #f)
            (else (loop (- i0 1)))))))

;; srcgen1<->srcgen2 bridge wrappers
(define (XATS2JS_sint_neg x0) (XATS2JS_gint_neg$sint x0))
(define (XATS2JS_sint_abs x0) (XATS2JS_gint_abs$sint x0))
(define (XATS2JS_sint_lt$sint x0 y0) (XATS2JS_gint_lt$sint$sint x0 y0))
(define (XATS2JS_sint_gt$sint x0 y0) (XATS2JS_gint_gt$sint$sint x0 y0))
(define (XATS2JS_sint_eq$sint x0 y0) (XATS2JS_gint_eq$sint$sint x0 y0))
(define (XATS2JS_sint_lte$sint x0 y0) (XATS2JS_gint_lte$sint$sint x0 y0))
(define (XATS2JS_sint_gte$sint x0 y0) (XATS2JS_gint_gte$sint$sint x0 y0))
(define (XATS2JS_sint_neq$sint x0 y0) (XATS2JS_gint_neq$sint$sint x0 y0))
(define (XATS2JS_sint_add$sint x0 y0) (XATS2JS_gint_add$sint$sint x0 y0))
(define (XATS2JS_sint_sub$sint x0 y0) (XATS2JS_gint_sub$sint$sint x0 y0))
(define (XATS2JS_sint_mul$sint x0 y0) (XATS2JS_gint_mul$sint$sint x0 y0))
(define (XATS2JS_sint_div$sint x0 y0) (XATS2JS_gint_div$sint$sint x0 y0))

;;;====================================================================
;;; basics2.cats — arrays (0/1-D), refs, p2tr, lazy streams
;;; JS arrays -> Scheme vectors;  a0ref/mutable ref -> Scheme box.
;;;====================================================================

;; 0-dimensional (a single mutable cell).  JS used a 1-elem array; we use a box.
(define (XATS2JS_a0ptr_alloc) (box (if #f #f)))
(define (XATS2JS_a0ptr_make_1val x0)
  (let ((A0 (XATS2JS_a0ptr_alloc))) (set-box! A0 x0) A0))
(define (XATS2JS_a0ref_get A0) (unbox A0))
;; XATS2JS_a0ref_set is already defined in xats2chez_generics.scm — SKIPPED.
(define (XATS2JS_a0ref_dtget A0) (unbox A0))
(define (XATS2JS_UN_a0ref_dtset A0 x0) (set-box! A0 x0))

;; 1-dimensional (a sized array) -> Scheme vector.
(define (XATS2JS_a1ptr_alloc asz) (make-vector asz))
(define (XATS2JS_a1ref_get$at A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1ptr_get$at1 A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1ref_set$at A0 i0 x0) (vector-set! A0 i0 x0))
(define (XATS2JS_a1ptr_set$at1 A0 i0 x0) (vector-set! A0 i0 x0))
(define (XATS2JS_a1ref_dtget$at A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1ref_cget$at A0 i0) (vector-ref A0 i0))

;; prelude/unsafex.sats — p2tr get/set via the lval helpers (in runtime.cats).
(define (XATS2JS_UN_p2tr_get ptr) (XATS2JS_lval_get ptr))
(define (XATS2JS_UN_p2tr_set ptr obj) (XATS2JS_lval_set ptr obj))

;; lazy linear char-code streams (strm_vt / strx_vt).  These reference the
;; precats lazy/strmcon/strxcon helpers (XATS2JS_lazy_vt_*, XATS2JS_strmcon_vt_*,
;; XATS2JS_strxcon_vt_*) by name, faithfully to the JS; they error only if those
;; helpers are absent AND the function is actually called.
(define (XATS2JS_strm_vt_forall0$f1un fxs test)
  (let ((nilq1 XATS2JS_strmcon_vt_nilq1))
    (let loop ((fxs fxs))
      (let ((cxs (XATS2JS_lazy_vt_eval fxs)))
        (if (nilq1 cxs)
            #t
            (let ((x01 (XATS2JS_strmcon_vt_head$raw1 cxs)))
              (if (test x01)
                  (loop (XATS2JS_strmcon_vt_tail$raw0 cxs))
                  (let ((fxs2 (XATS2JS_strmcon_vt_tail$raw0 cxs)))
                    (XATS2JS_lazy_vt_free fxs2) #f))))))))

(define (XATS2JS_strm_vt_filter0$f1un fxs test free)
  (XATS2JS_lazy_vt_make_f0un
    (lambda ()
      (XATS2JS_strmcon_vt_filter0$f1un (XATS2JS_lazy_vt_eval fxs) test free))))

(define (XATS2JS_strmcon_vt_filter0$f1un cxs test free)
  (let ((nilq1 XATS2JS_strmcon_vt_nilq1))
    (let loop ((cxs cxs))
      (if (nilq1 cxs)
          (XATS2JS_strmcon_vt_nil)
          (let ((x01 (XATS2JS_strmcon_vt_head$raw1 cxs))
                (fxs (XATS2JS_strmcon_vt_tail$raw0 cxs)))
            (if (test x01)
                (XATS2JS_strmcon_vt_cons
                  x01 (XATS2JS_strm_vt_filter0$f1un fxs test free))
                (begin (free x01)
                       (loop (XATS2JS_lazy_vt_eval fxs)))))))))

(define (XATS2JS_strx_vt_forall0$f1un fxs test)
  (let loop ((fxs fxs))
    (let* ((cxs (XATS2JS_lazy_vt_eval fxs))
           (x01 (XATS2JS_strxcon_vt_head$raw1 cxs)))
      (if (test x01)
          (loop (XATS2JS_strxcon_vt_tail$raw0 cxs))
          (let ((fxs2 (XATS2JS_strxcon_vt_tail$raw0 cxs)))
            (XATS2JS_lazy_vt_free fxs2) #f)))))

(define (XATS2JS_strx_vt_filter0$f1un fxs test free)
  (XATS2JS_lazy_vt_make_f0un
    (lambda ()
      (XATS2JS_strxcon_vt_filter0$f1un (XATS2JS_lazy_vt_eval fxs) test free))))

(define (XATS2JS_strxcon_vt_filter0$f1un cxs test free)
  (let loop ((cxs cxs))
    (let ((x01 (XATS2JS_strxcon_vt_head$raw1 cxs))
          (fxs (XATS2JS_strxcon_vt_tail$raw0 cxs)))
      (if (test x01)
          (XATS2JS_strxcon_vt_cons
            x01 (XATS2JS_strx_vt_filter0$f1un fxs test free))
          (begin (free x01)
                 (loop (XATS2JS_lazy_vt_eval fxs)))))))

;;;====================================================================
;;; basics3.cats — JS objects / native arrays / native hashmaps.
;;; JS object  -> a Chez eq-hashtable (string/symbol keys)
;;; native arr -> Scheme vector;  hashmap -> Chez equal-hashtable.
;;;====================================================================

;; jsobj: a JS object as a key->item map (a Chez hashtable keyed by equal?).
(define (XATS2JS_jsobj_get$at obj key) (hashtable-ref obj key (if #f #f)))
(define (XATS2JS_jsobj_set$at obj key itm) (hashtable-set! obj key itm))

;; native sized array -> Scheme vector
(define (XATS2JS_jsa1sz_size xs) (vector-length xs))
(define (XATS2JS_jsa1sz_length xs) (vector-length xs))
(define (XATS2JS_jsa1sz_get$at xs i0) (vector-ref xs i0))
(define (XATS2JS_jsa1sz_set$at xs i0 x0) (vector-set! xs i0 x0))

;; native hashmap -> Chez equal-hashtable
(define jshmap--absent (list 'jshmap-absent))   ; unique miss sentinel
(define (XATS2JS_jshmap_keyq map key) (hashtable-contains? map key))
(define (XATS2JS_jshmap_get_keys map) (hashtable-keys map))   ; -> vector
(define (XATS2JS_jshmap_make_nil) (make-hashtable equal-hash equal?))
(define (XATS2JS_jshmap_search$opt map key)
  (let ((itm0 (hashtable-ref map key jshmap--absent)))
    (if (eq? itm0 jshmap--absent)
        (XATS2JS_optn_vt_nil)
        (XATS2JS_optn_vt_cons itm0))))
(define (XATS2JS_jshmap_remove$any map key)
  (hashtable-delete! map key) (if #f #f))
(define (XATS2JS_jshmap_insert$any map key itm1)
  (hashtable-set! map key itm1) (if #f #f))
(define (XATS2JS_jshmap_remove$opt map key)
  (let ((itm0 (hashtable-ref map key jshmap--absent)))
    (if (eq? itm0 jshmap--absent)
        (XATS2JS_optn_vt_nil)
        (begin (hashtable-delete! map key)
               (XATS2JS_optn_vt_cons itm0)))))
(define (XATS2JS_jshmap_insert$opt map key itm1)
  (let ((itm0 (hashtable-ref map key jshmap--absent)))
    (if (eq? itm0 jshmap--absent)
        (begin (hashtable-set! map key itm1) (XATS2JS_optn_vt_nil))
        (begin (hashtable-set! map key itm1) (XATS2JS_optn_vt_cons itm0)))))

;;;====================================================================
;;; g_print.cats — the print store.
;;; XATS2JS_strn_print / XATS2JS_the_print_store_clear are defined in
;;; xats2chez_runtime.scm and SKIPPED.  XATS2JS_the_print_store_flush there is
;;; the analog of the JS *_join; we add the JS-named *_join as an alias.
;;;====================================================================

(define (XATS2JS_g_print obj) (XATS2JS_strn_print (xats_value_string obj)))
(define (XATS2JS_bool_print b0)
  (if b0 (XATS2JS_g_print "true") (XATS2JS_g_print "false")) (if #f #f))
(define (XATS2JS_char_print c0)
  (XATS2JS_g_print (string (integer->char c0))) (if #f #f))
(define (XATS2JS_gint_print$sint x0) (XATS2JS_g_print x0) (if #f #f))
(define (XATS2JS_gint_print$uint x0) (XATS2JS_g_print x0) (if #f #f))
(define (XATS2JS_gflt_print$sflt x0) (XATS2JS_g_print x0) (if #f #f))
(define (XATS2JS_gflt_print$dflt x0) (XATS2JS_g_print x0) (if #f #f))
;; XATS2JS_strn_print SKIPPED (in runtime.scm).
;; the_print_store_join : join "" the accumulated reps (no clear) — mirrors the
;; runtime store (kept in REVERSE order in the box `the_print_store`).
(define (XATS2JS_the_print_store_join)
  (apply string-append (reverse (unbox the_print_store))))
;; XATS2JS_the_print_store_clear SKIPPED (in runtime.scm).

;;;====================================================================
;;; runtime.cats — datacons / refs / exceptions / lval paths / lazy.
;;; Datacon/option reps use 0-BASED Chez tags (None=#(0)/Some=#(1 x),
;;; nil=#(0)/cons=#(1 ...)), NOT the JS [1]/[2,..] tags.
;;;====================================================================

;; sentinel globals (JS null) -> Scheme #f
(define XATS2JS_nil #f)
(define XATS2JS_top #f)
(define XATS2JS_none #f)
(define XATS2JS_null #f)
(define XATS2JS_void #f)

(define (XATS2JS_fnull) (error 'XATS2JS_fnull "null function called"))

;; exception-tag allocator (mutable global counters).
(define XATS2JS_excbas 0)
(define XATS2JS_exctag 0)
(define (XATS2JS_new_exctag)
  (let ((bas0 XATS2JS_excbas)
        (tag1 (+ XATS2JS_exctag 1)))
    (set! XATS2JS_exctag tag1)
    (+ bas0 tag1)))

;; char / strn / generic casts
(define (XATS2JS_char cs) (char->integer (string-ref cs 0)))
(define (XATS2JS_strn cs) cs)
(define (XATS2JS_fcast x0) x0)

;; exceptions
(define (XATS2JS_raise exn) (raise exn))
(define (XATS2JS_reraise exn) (raise exn))

(define (XATS2JS_assert b0)
  (if (not b0) (error 'XATS2JS_assert "assertion failed") (if #f #f)))
(define (XATS2JS_assertloc b0 loc)
  (if (not b0) (error 'XATS2JS_assertloc loc) (if #f #f)))
(define (XATS2JS_assertmsg b0 msg)
  (if (not b0) (error 'XATS2JS_assertmsg msg) (if #f #f)))

;; lvalue (path) model.  In JS an lval is a mutable object {root, offs[, prev]}.
;; We model it as a mutable vector tagged with the symbol 'lval:
;;   no-prev : #(lval root offs)
;;   w/ prev : #(lval root offs prev)
;; root is itself a vector (a boxed con / tuple); offs is an index.
(define (XATS2JS_lval_err loc) (error 'XATS2JS_lval_err loc))
(define (lval--has-prev? lvl0) (= (vector-length lvl0) 4))
(define (lval--root lvl0) (vector-ref lvl0 1))
(define (lval--offs lvl0) (vector-ref lvl0 2))
(define (lval--prev lvl0) (vector-ref lvl0 3))
(define (XATS2JS_lval_get lvl0)
  (let ((root (if (lval--has-prev? lvl0)
                  (XATS2JS_lval_get (lval--prev lvl0))
                  (lval--root lvl0)))
        (offs (lval--offs lvl0)))
    (vector-ref root offs)))
(define (XATS2JS_lval_set lvl0 obj1)
  (let ((offs (lval--offs lvl0)))
    (if (lval--has-prev? lvl0)
        ;; flat tuple: copy-on-write the prev root, write the slot, store back.
        (let ((root (vector-copy (XATS2JS_lval_get (lval--prev lvl0)))))
          (vector-set! root offs obj1)
          (XATS2JS_lval_set (lval--prev lvl0) root))
        ;; boxed: write directly into the root vector.
        (vector-set! (lval--root lvl0) offs obj1))
    (if #f #f)))

;; con / tuple field access.  Under the CHEZ rep a datacon is #(tag f0 f1 ..);
;; the JS x0[0] is the tag, x0[i] field i.  TODO-REP: callers that pass a raw
;; field index i0 assume the JS layout where slot 0 is the tag and fields start
;; at 1; the CHEZ con rep matches that (slot 0 = tag), so these are faithful.
(define (XATS2JS_ctag x0) (vector-ref x0 0))
(define (XATS2JS_carg x0 i0) (vector-ref x0 i0))
(define (XATS2JS_targ x0 i0) (vector-ref x0 i0))

;; match / pattern-check failures
(define (XATS2JS_patckerr0) (error 'XATS2JS_patckerr0 "pattern check failed"))
(define (XATS2JS_patckerr1 loc) (error 'XATS2JS_patckerr1 loc))
(define (XATS2JS_matcherr0) (error 'XATS2JS_matcherr0 "match failed"))
(define (XATS2JS_matcherr1 loc) (error 'XATS2JS_matcherr1 loc))

;; new mutable variable / path cells.  An lval is the tagged vector above.
(define (XATS2JS_new_var0) (vector 'lval (vector #f) 0))
(define (XATS2JS_new_var1 init) (vector 'lval (vector init) 0))
(define (XATS2JS_new_cofs lvl1 idx2) (vector 'lval lvl1 idx2))
(define (XATS2JS_new_tofs lvl1 idx2) (vector 'lval lvl1 idx2))
(define (XATS2JS_new_cptr lvl1 idx2)
  (let ((con1 (XATS2JS_lval_get lvl1)))
    (vector 'lval con1 idx2)))
;; new_tptr: in JS a NEGATIVE first slot flags a flat (prev-linked) tuple.  We
;; keep that test verbatim (tup1[0] >= 0 -> boxed; else prev-linked).
(define (XATS2JS_new_tptr lvl1 idx2)
  (let ((tup1 (XATS2JS_lval_get lvl1)))
    (if (>= (vector-ref tup1 0) 0)
        (vector 'lval tup1 idx2)
        (vector 'lval tup1 idx2 lvl1))))

;; lazy (level-0, MEMOIZED).  JS object {lztag, lzval, lzfun}; here a tagged
;; mutable vector #(lazy lztag lzval lzfun).
(define (XATS2JS_new_lazy thunk) (vector 'lazy 0 #f thunk))
(define (XATS2JS_lazy_eval lzobj)
  (if (= (vector-ref lzobj 1) 0)
      (let ((lzres ((vector-ref lzobj 3))))
        (vector-set! lzobj 1 1)
        (vector-set! lzobj 2 lzres)
        lzres)
      (begin
        (vector-set! lzobj 1 (+ (vector-ref lzobj 1) 1))
        (vector-ref lzobj 2))))

;; llazy (LINEAR lazy, single-use).  JS {lztag, lzfun, lzfrs}; here
;; #(llazy lztag lzfun lzfrs)  (lztag : a boolean used-flag).
(define (XATS2JS_new_llazy thunk frees) (vector 'llazy #f thunk frees))
(define (XATS2JS_llazy_eval lzobj)
  (if (vector-ref lzobj 1) (error 'XATS2JS_llazy_eval "llazy already used") (if #f #f))
  (vector-set! lzobj 1 #t)
  ((vector-ref lzobj 2)))
(define (XATS2JS_llazy_free lzobj)
  (if (vector-ref lzobj 1) (error 'XATS2JS_llazy_free "llazy already used") (if #f #f))
  (vector-set! lzobj 1 #t)
  ((vector-ref lzobj 3)))

;; option / list constructors.  JS uses tags [1]/[2,..]; CHEZ uses 0-based.
(define (XATS2JS_optn_nil) (vector 0))            ; JS tag [1] -> CHEZ #(0)
(define (XATS2JS_optn_cons x0) (vector 1 x0))     ; JS tag [2,x0] -> CHEZ #(1 x0)
(define (XATS2JS_list_nil) (vector 0))            ; JS [1] -> #(0)
(define (XATS2JS_list_cons x0 xs) (vector 1 x0 xs)) ; JS [2,x0,xs] -> #(1 x0 xs)
(define (XATS2JS_optn_vt_nil) (vector 0))         ; JS [1] -> #(0)
(define (XATS2JS_optn_vt_cons x0) (vector 1 x0))  ; JS [2,x0] -> #(1 x0)
(define (XATS2JS_list_vt_nil) (vector 0))         ; JS [1] -> #(0)
(define (XATS2JS_list_vt_cons x0 xs) (vector 1 x0 xs)) ; JS [2,x0,xs] -> #(1 x0 xs)

;;;====================================================================
;;; xatsopt.cats — compiler-specific primitives.
;;; XATSOPT_strn_append_uint is defined in xats2chez_cats.scm — SKIPPED.
;;;====================================================================

;; parseFloat(rep); NaN -> 0.0
(define (XATSOPT_strn_dflt$parse rep)
  (let ((flt (string->number rep)))
    (if (and flt (real? flt)) (exact->inexact flt) 0.0)))
(define (XATSOPT_strn_dflt$parse$exn rep)
  (let ((flt (string->number rep)))
    (if (and flt (real? flt))
        (exact->inexact flt)
        (error 'XATSOPT_strn_dflt$parse$exn (string-append "rep = " rep)))))

;;;====================================================================
;;; end of [xats2chez_jsffi.scm]
;;;====================================================================
