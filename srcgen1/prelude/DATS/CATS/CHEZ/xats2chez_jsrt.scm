;;;====================================================================
;;; xats2chez_jsrt.scm
;;;
;;; Mechanical port of the ATS3 JS-backend runtime primitives to Chez
;;; Scheme.  Mirrors the existing CHEZ runtime files; value-rep mapping
;;; per the porting spec (numbers->numbers, chars->int codes,
;;; strings->strings, arrays->vectors, a0ref->box, datacons->0-based
;;; tagged vectors, print -> existing (XATS2JS_strn_print ...) store).
;;;
;;; Functions already defined in xats2chez_{cats,runtime,collrt,
;;; generics,jsffi}.scm are SKIPPED here (noted inline).
;;;====================================================================

;;;====================================================================
;;; [srcgen2_prelude.js]
;;;====================================================================

;; -- xtop000 --
;; XATS2JS_console_log : already defined (cats/runtime) -- SKIPPED
;; XATS2JS_the_print_store / prout / prerr : print store already exists -- SKIPPED
;; XATS2JS_the_print_store_clear : already defined -- SKIPPED
;; XATS2JS_the_print_store_flush : already defined -- SKIPPED
(define (XATS2JS_the_prout_store_flush)
  (XATS2JS_the_print_store_flush))
(define (XATS2JS_the_prerr_store_flush)
  (XATS2JS_the_print_store_flush))

;; -- gbas000 --
(define (XATS2JS_g_tostr obj) (xats_value_string obj))
(define (XATS2JS_strn_sint$parse$fwork rep0 work)
  (let ((i0 (string->number rep0)))
    (if (and i0 (integer? i0)) (work i0) (if #f #f))
    (if #f #f)))
(define (XATS2JS_strn_dflt$parse$fwork rep0 work)
  (let ((f0 (string->number rep0)))
    (if f0 (work (exact->inexact f0)) (if #f #f))
    (if #f #f)))

;; -- gdbg000 --
(define (XATS2JS_bool_assert$errmsg cond emsg)
  (if (not cond)
      (error 'XATS2JS_bool_assert$errmsg
             (string-append "emsg = " emsg)))
  (if #f #f))

;; -- gint000 --
;; XATS2JS_sint_neg : already defined (runtime) -- SKIPPED
;; XATS2JS_sint_lt$sint / gt / lte / gte / eq / neq : already defined -- SKIPPED
;; XATS2JS_sint_add$sint / sub / mul / div : already defined -- SKIPPED
(define (XATS2JS_sint_mod$sint i1 i2) (remainder i1 i2)) ;; JS % truncates toward 0
(define (XATS2JS_sint_print i0)
  (XATS2JS_strn_print (number->string i0)))
(define (XATS2JS_uint_print u0)
  (XATS2JS_strn_print (number->string u0)))
;; XATS2JS_sint_to$uint : already defined (runtime) -- SKIPPED
;; XATS2JS_uint_to$sint : already defined (runtime) -- SKIPPED

;; -- bool000 --
(define (XATS2JS_bool_lt b1 b2)
  (and (not b1) b2))
(define (XATS2JS_bool_gt b1 b2)
  (and b1 (not b2)))
(define (XATS2JS_bool_lte b1 b2)
  (or (not b1) b2))
(define (XATS2JS_bool_gte b1 b2)
  (or b1 (not b2)))
(define (XATS2JS_bool_eq b1 b2) (eq? b1 b2))
(define (XATS2JS_bool_neq b1 b2) (not (eq? b1 b2)))

;; -- char000 (chars are integer codes) --
(define (XATS2JS_char_lt c1 c2) (< c1 c2))
(define (XATS2JS_char_gt c1 c2) (> c1 c2))
(define (XATS2JS_char_lte c1 c2) (<= c1 c2))
(define (XATS2JS_char_gte c1 c2) (>= c1 c2))
;; XATS2JS_char_eq / neq : already defined -- SKIPPED
(define (XATS2JS_char_add$sint c1 i2)
  (modulo (+ c1 i2) 256)) ; char=int8
(define (XATS2JS_char_sub$char c1 c2) (- c1 c2))
;; XATS2JS_char_print : already defined (cats/runtime) -- SKIPPED
(define (XATS2JS_char_make_sint i0) i0)
(define (XATS2JS_sint_make_char ch) ch)

;; -- gflt000 --
(define (XATS2JS_dflt_neg df) (- df))
(define (XATS2JS_dflt_abs df) (if (>= df 0.0) df (- df)))
(define (XATS2JS_dflt_sqrt df) (sqrt df))
(define (XATS2JS_dflt_cbrt df) (expt df (/ 1.0 3.0)))
(define (XATS2JS_dflt_lt$dflt f1 f2) (< f1 f2))
(define (XATS2JS_dflt_gt$dflt f1 f2) (> f1 f2))
(define (XATS2JS_dflt_lte$dflt f1 f2) (<= f1 f2))
(define (XATS2JS_dflt_gte$dflt f1 f2) (>= f1 f2))
(define (XATS2JS_dflt_eq$dflt f1 f2) (= f1 f2))
(define (XATS2JS_dflt_neq$dflt f1 f2) (not (= f1 f2)))
(define (XATS2JS_dflt_cmp$dflt f1 f2)
  (if (< f1 f2) -1 (if (> f1 f2) 1 0)))
(define (XATS2JS_dflt_add$dflt f1 f2) (+ f1 f2))
(define (XATS2JS_dflt_sub$dflt f1 f2) (- f1 f2))
(define (XATS2JS_dflt_mul$dflt f1 f2) (* f1 f2))
(define (XATS2JS_dflt_div$dflt f1 f2) (/ f1 f2))
(define (XATS2JS_dflt_mod$dflt f1 f2)
  (- f1 (* (truncate (/ f1 f2)) f2))) ; JS % on floats
(define (XATS2JS_dflt_ceil df) (ceiling df))
(define (XATS2JS_dflt_floor df) (floor df))
(define (XATS2JS_dflt_round df) (round df))
(define (XATS2JS_dflt_trunc df) (truncate df))
(define (XATS2JS_dflt_print f0)
  (XATS2JS_strn_print (xats_dflt_tostring f0))) ;; JS Number.toString: 10.0 -> "10"

;; -- strn000 --
;; XATS2JS_strn_cmp : already defined (srcgen1 variant) -- SKIPPED
;; XATS2JS_strn_length : already defined -- SKIPPED
;; XATS000_strn_length : NOT yet defined under this $-free name; this is
;;   the plain-named version below.
(define (XATS000_strn_length cs) (string-length cs))
(define (XATS2JS_strn_get$at$raw cs i0)
  (char->integer (string-ref cs i0)))
(define (XATS000_strn_get$at$raw cs i0)
  (XATS2JS_strn_get$at$raw cs i0))
(define (XATS2JS_strn_make_fwork fwork)
  (let ((cs '()))
    (fwork (lambda (ch) (set! cs (cons ch cs)) (if #f #f)))
    (list->string (map integer->char (reverse cs)))))
(define (XATS000_strn_make_fwork fwork)
  (XATS2JS_strn_make_fwork fwork))
;; XATS000_strn_print : already defined (runtime) -- SKIPPED
;; XATS2JS_strn_print : already defined (runtime) -- SKIPPED
(define (XATS2JS_strn_make_env$fwork env fwork)
  (let ((cs '()))
    (fwork env (lambda (ch) (set! cs (cons ch cs)) (if #f #f)))
    (list->string (map integer->char (reverse cs)))))
(define (XATS2JS_strn_make1_env$fwork env fwork)
  (let ((cs '()))
    (fwork env (lambda (ch) (set! cs (cons ch cs)) (if #f #f)))
    (list->string (map integer->char (reverse cs)))))
(define (XATS000_strn_make_env$fwork env fwork)
  (XATS2JS_strn_make_env$fwork env fwork))
(define (XATS000_strn_make1_env$fwork env fwork)
  (XATS2JS_strn_make1_env$fwork env fwork))

;; -- list000 --
(define (XATS2JS_list_vt_foritm0$f1un xs work)
  (let loop ((xs xs))
    (if (XATS2JS_list_vt_nilq1 xs)
        (if #f #f)
        (let ((x1 (XATS2JS_list_vt_head$raw1 xs)))
          (work x1)
          (loop (XATS2JS_list_vt_tail$raw0 xs))))))
(define (XATS2JS_list_vt_forall0$f1un xs test free)
  (let loop ((xs xs))
    (if (XATS2JS_list_vt_nilq1 xs)
        #t
        (let ((x1 (XATS2JS_list_vt_head$raw1 xs)))
          (if (test x1)
              (loop (XATS2JS_list_vt_tail$raw0 xs))
              (begin
                (XATS2JS_list_vt_foritm0$f1un
                 (XATS2JS_list_vt_tail$raw0 xs) free)
                #f))))))

;; -- strm000 --
;; XATS2JS_strm_vt_forall0$f1un : already defined (jsffi) -- SKIPPED
;; XATS2JS_strm_vt_filter0$f1un : already defined (jsffi) -- SKIPPED
;; XATS2JS_strmcon_vt_filter0$f1un : already defined (jsffi) -- SKIPPED

;; -- strx000 --
;; XATS2JS_strx_vt_forall0$f1un : already defined (jsffi) -- SKIPPED
;; XATS2JS_strx_vt_filter0$f1un : already defined (jsffi) -- SKIPPED
;; XATS2JS_strxcon_vt_filter0$f1un : already defined (jsffi) -- SKIPPED

;; -- axrf000 --
;; XATS2JS_a0rf_lget / a0rf_lset / a0rf_make_1val : already defined (cats,
;;   using boxes) -- SKIPPED
(define (XATS2JS_a1rf_lget$at A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1rf_lset$at A0 i0 x1) (vector-set! A0 i0 x1) (if #f #f))
(define (XATS2JS_a1rf_make_ncpy n0 x0)
  (make-vector n0 x0))
(define (XATS2JS_a1rf_make_nfun n0 fopr)
  (let ((A0 (make-vector n0)))
    (let loop ((i0 0))
      (if (< i0 n0)
          (begin (vector-set! A0 i0 (fopr i0)) (loop (+ i0 1)))
          A0))))

;; -- axsz000 --
;; XATS2JS_a1sz_length : already defined -- SKIPPED
;; XATS2JS_a1sz_lget$at : (existing name is XATS2JS_a1sz_lget) -- this is
;;   the $at-suffixed name, not yet defined.
(define (XATS2JS_a1sz_lget$at A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1sz_lset$at A0 i0 x1) (vector-set! A0 i0 x1) (if #f #f))
(define (XATS2JS_a1sz_make_none n0) (make-vector n0))
(define (XATS2JS_a1sz_make_ncpy n0 x0) (make-vector n0 x0))
(define (XATS2JS_a1sz_make_nfun n0 fopr)
  (let ((A0 (make-vector n0)))
    (let loop ((i0 0))
      (if (< i0 n0)
          (begin (vector-set! A0 i0 (fopr i0)) (loop (+ i0 1)))
          A0))))
(define (XATS2JS_a1sz_make_fwork fwork)
  (let ((A0 '()))
    (fwork (lambda (x0) (set! A0 (cons x0 A0)) (if #f #f)))
    (list->vector (reverse A0))))

;;;====================================================================
;;; [srcgen2_precats.js]
;;;
;;; Datacon predicates / accessors / constructors.  Reps use the CHEZ
;;; 0-based tagged vectors already established in jsffi/collrt:
;;;   optn/list/strmcon/strxcon nil  -> #(0)
;;;   optn/list/strmcon/strxcon cons -> #(1 ...)  (strxcon_cons uses 0)
;;; The 0-based tags below come straight from the srcgen2 XATSCTAG(...,N).
;;;====================================================================

;; -- optn --
(define (XATS2JS_optn_nilq xs)
  (cond ((XATS000_ctgeq xs 0) #t)
        ((XATS000_ctgeq xs 1) #f)
        (else (XATS000_cfail))))
(define (XATS2JS_optn_consq xs)
  (cond ((XATS000_ctgeq xs 0) #f)
        ((XATS000_ctgeq xs 1) #t)
        (else (XATS000_cfail))))
(define (XATS2JS_optn_head$raw xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 0))
        (else (XATS000_cfail))))
(define (XATS2JS_optn_uncons$raw xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 0))
        (else (XATS000_cfail))))

;; -- list --
(define (XATS2JS_list_nilq xs)
  (cond ((XATS000_ctgeq xs 0) #t)
        ((XATS000_ctgeq xs 1) #f)
        (else (XATS000_cfail))))
(define (XATS2JS_list_consq xs)
  (cond ((XATS000_ctgeq xs 0) #f)
        ((XATS000_ctgeq xs 1) #t)
        (else (XATS000_cfail))))
(define (XATS2JS_list_head$raw xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 0))
        (else (XATS000_cfail))))

;; -- lazy --
(define (XATS2JS_lazy_make_f0un f0)
  (XATS000_l0azy (lambda () (f0))))

;; -- strmcon / strxcon (immutable streams) --
(define (XATS2JS_strmcon_nil) (vector 0))
(define (XATS2JS_strmcon_cons x1 xs) (vector 1 x1 xs))
;; strxcon has only a cons constructor -> tag 0
(define (XATS2JS_strxcon_cons x1 xs) (vector 0 x1 xs))
(define (XATS2JS_strmcon_nilq xs)
  (cond ((XATS000_ctgeq xs 0) #t)
        ((XATS000_ctgeq xs 1) #f)
        (else (XATS000_cfail))))
(define (XATS2JS_strmcon_consq xs)
  (cond ((XATS000_ctgeq xs 0) #f)
        ((XATS000_ctgeq xs 1) #t)
        (else (XATS000_cfail))))
(define (XATS2JS_strmcon_head$raw xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 0))
        (else (XATS000_cfail))))
(define (XATS2JS_strmcon_tail$raw xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 1))
        (else (XATS000_cfail))))
(define (XATS2JS_strxcon_head$raw xs)
  (cond ((XATS000_ctgeq xs 0) (XATSPCON xs 0))
        (else (XATS000_cfail))))
(define (XATS2JS_strxcon_tail$raw xs)
  (cond ((XATS000_ctgeq xs 0) (XATSPCON xs 1))
        (else (XATS000_cfail))))

;; -- optn_vt --
(define (XATS2JS_optn_vt_nilq1 xs)
  (cond ((XATS000_ctgeq xs 0) #t)
        ((XATS000_ctgeq xs 1) #f)
        (else (XATS000_cfail))))
(define (XATS2JS_optn_vt_consq1 xs)
  (cond ((XATS000_ctgeq xs 0) #f)
        ((XATS000_ctgeq xs 1) #t)
        (else (XATS000_cfail))))
(define (XATS2JS_optn_vt_head$raw0 xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 0))
        (else (XATS000_cfail))))
(define (XATS2JS_optn_vt_uncons$raw0 xs)
  (cond ((XATS000_ctgeq xs 1) (XATSPCON xs 0))
        (else (XATS000_cfail))))

;; -- list_vt --
(define (XATS2JS_list_vt_nilq1 xs)
  (cond ((XATS000_ctgeq xs 0) #t)
        ((XATS000_ctgeq xs 1) #f)
        (else (XATS000_cfail))))
(define (XATS2JS_list_vt_consq1 xs)
  (cond ((XATS000_ctgeq xs 0) #f)
        ((XATS000_ctgeq xs 1) #t)
        (else (XATS000_cfail))))
(define (XATS2JS_list_vt_head$raw1 xs)
  (cond ((XATS000_ctgeq xs 1)
         (XATS2JS_fcast (XATS2JS_fcast (XATSPCON xs 0))))
        (else (XATS000_cfail))))
(define (XATS2JS_list_vt_tail$raw0 xs)
  (cond ((XATS000_ctgeq xs 1)
         (XATS2JS_fcast (XATSPCON xs 0)) ; delinear head (no-op)
         (XATSPCON xs 1))
        (else (XATS000_cfail))))

;; -- lazy_vt --
(define (XATS2JS_lazy_vt_eval lz) (XATS000_dl1az lz))
(define (XATS2JS_lazy_vt_free lz) (XATS000_free lz))
(define (XATS2JS_lazy_vt_make_f0un f0)
  (XATS000_l1azy (lambda (tlaz) (f0))))

;; -- strmcon_vt / strxcon_vt (linear streams) --
(define (XATS2JS_strmcon_vt_nil) (vector 0))
(define (XATS2JS_strmcon_vt_cons x1 xs) (vector 1 x1 xs))
(define (XATS2JS_strxcon_vt_cons x1 xs) (vector 0 x1 xs))
(define (XATS2JS_strmcon_vt_nilq1 xs)
  (cond ((XATS000_ctgeq xs 0) #t)
        ((XATS000_ctgeq xs 1) #f)
        (else (XATS000_cfail))))
(define (XATS2JS_strmcon_vt_consq1 xs)
  (cond ((XATS000_ctgeq xs 0) #f)
        ((XATS000_ctgeq xs 1) #t)
        (else (XATS000_cfail))))
(define (XATS2JS_strmcon_vt_head$raw1 xs)
  (cond ((XATS000_ctgeq xs 1)
         (XATS2JS_fcast (XATS2JS_fcast (XATSPCON xs 0))))
        (else (XATS000_cfail))))
(define (XATS2JS_strmcon_vt_tail$raw0 xs)
  (cond ((XATS000_ctgeq xs 1)
         (XATS2JS_fcast (XATSPCON xs 0)) ; delinear head (no-op)
         (XATSPCON xs 1))
        (else (XATS000_cfail))))
(define (XATS2JS_strxcon_vt_head$raw1 xs)
  (cond ((XATS000_ctgeq xs 0)
         (XATS2JS_fcast (XATS2JS_fcast (XATSPCON xs 0))))
        (else (XATS000_cfail))))
(define (XATS2JS_strxcon_vt_tail$raw0 xs)
  (cond ((XATS000_ctgeq xs 0)
         (XATS2JS_fcast (XATSPCON xs 0)) ; delinear head (no-op)
         (XATSPCON xs 1))
        (else (XATS000_cfail))))

;;;====================================================================
;;; [srcgen1_prelude.js]
;;;====================================================================

;; -- bool000 --
;; XATS2JS_bool_neg / bool_add / bool_mul : already defined -- SKIPPED

;; -- char000 --
;; XATS2JS_char_eq / neq / cmp / eqz / neqz / equal / noteq : SKIPPED
;; XATS2JS_char_lowerq / upperq / isdigit / isalpha / isalnum : SKIPPED
;; XATS2JS_char_lohexq / uphexq / isxdigit : already defined -- SKIPPED
;; XATS2JS_sint_lowerq / upperq / isdigit / isalpha / isalnum : SKIPPED
;; XATS2JS_sint_lohexq / isxdigit : already defined -- SKIPPED
;; XATS2JS_sint_uphexq : NOT yet defined (referenced by isxdigit) --
;;   provide it (JS file only defined sint_lohexq twice, missing uphexq).
(define (XATS2JS_sint_uphexq ch)
  (and (<= 65 ch) (<= ch 70)))

;; -- gint000 --
;; XATS2JS_gint_neg$sint / abs$sint : already defined -- SKIPPED
;; XATS2JS_sint_suc / uint_suc : already defined -- SKIPPED
;; XATS2JS_gint_suc$sint / suc$uint / pre$sint / pre$uint : SKIPPED
;; XATS2JS_uint_lnot / ladd / lmul / lneq : already defined -- SKIPPED
;; XATS2JS_gint_lnot$uint / lor2$uint / l2or$uint / land$uint /
;;   lxor$uint : already defined -- SKIPPED
;; XATS2JS_gint_asrn$sint / lsln$uint / lsrn$uint : already defined -- SKIPPED
;; XATS2JS_gint_lt/gt/eq/lte/gte/neq/cmp $sint$sint / $uint$uint : SKIPPED
;; XATS2JS_gint_add/sub/mul/mod/div $sint$sint : already defined -- SKIPPED
;; XATS2JS_gint_add$uint$uint / sub$uint$uint : already defined -- SKIPPED
;; XATS2JS_sint_to$uint / uint_to$sint : already defined -- SKIPPED
;; XATS2JS_gint_sint2uint / uint2sint : already defined -- SKIPPED
;; XATS2JS_gint_parse_sint / parse_uint : already defined -- SKIPPED

;; -- gflt000 --
;; XATS2JS_gflt_si_dflt / neg_dflt / abs_dflt / suc_dflt / pre_dflt :
;;   already defined -- SKIPPED
;; XATS2JS_gflt_lt/gt/eq/lte/gte/neq/cmp _dflt_dflt : already defined -- SKIPPED
;; XATS2JS_gflt_add/sub/mul/div _dflt_dflt : already defined -- SKIPPED

;; -- strn000 --
;; XATS2JS_strn_vt2t / strn_nilq / strn_consq : already defined -- SKIPPED
;; XATS2JS_stropt_nilq / stropt_consq : already defined -- SKIPPED
;; XATS2JS_strn_lt/gt/eq/lte/gte/neq / strn_cmp : already defined -- SKIPPED
;; XATS2JS_strn_head$raw / head$opt / tail$raw : already defined -- SKIPPED
;; XATS2JS_strn_length / vt_length0 / vt_length1 : already defined -- SKIPPED
;; XATS2JS_strn_get$at / vt_get$at / vt_set$at : already defined -- SKIPPED
;; XATS2JS_strtmp_vt_alloc / vt_set$at : already defined -- SKIPPED
;; XATS2JS_strn_forall$f1un / rforall$f1un : already defined -- SKIPPED
;; XATS2JS_strn_vt_forall$f1un / vt_rforall$f1un : already defined -- SKIPPED
;; bridging sint_* : neg/abs/lt/gt/eq/lte/gte/neq/add/sub/mul/div :
;;   already defined -- SKIPPED

;; -- array (basics2) --
;; XATS2JS_a0ptr_alloc / a0ptr_make_1val : already defined -- SKIPPED
;; XATS2JS_a0ref_get / a0ref_set / a0ref_dtget / UN_a0ref_dtset : SKIPPED
;; XATS2JS_a1ptr_alloc : already defined -- SKIPPED
;; XATS2JS_a1ref_get$at / a1ptr_get$at1 / a1ref_set$at / a1ptr_set$at1 :
;;   already defined -- SKIPPED
;; XATS2JS_a1ref_dtget$at / a1ref_cget$at : already defined -- SKIPPED
;; XATS2JS_UN_p2tr_get / UN_p2tr_set : already defined -- SKIPPED
;; strm/strx_vt_forall0/filter0 (copied) : already defined -- SKIPPED

;; -- basics3 --
;; XATS2JS_jsobj_get$at / set$at : already defined -- SKIPPED
;; XATS2JS_jsa1sz_size / length / get$at / set$at : already defined -- SKIPPED
;; XATS2JS_jshmap_* : already defined -- SKIPPED

;; -- g_eqref --
;; XATS2JS_g_eqref / g_neqrf : referenced but not in skip-list; provide.
(define (XATS2JS_g_eqref x1 x2) (eq? x1 x2))
(define (XATS2JS_g_neqrf x1 x2) (not (eq? x1 x2)))

;; -- g_print --
;; XATS2JS_the_print_store : already exists -- SKIPPED
;; XATS2JS_g_print : already defined -- SKIPPED
;; XATS2JS_bool_print : already defined -- SKIPPED
;; XATS2JS_char_print : already defined -- SKIPPED
;; XATS2JS_gint_print$sint / gint_print$uint : already defined (jsffi) -- SKIPPED
;; XATS2JS_gflt_print$sflt / gflt_print$dflt : already defined (jsffi) -- SKIPPED
;; XATS2JS_strn_print : already defined -- SKIPPED
;; XATS2JS_the_print_store_join : already defined -- SKIPPED
;; XATS2JS_the_print_store_clear : already defined -- SKIPPED

;; -- xatsopt --
;; XATSOPT_strn_append_uint : already defined -- SKIPPED
;; XATSOPT_strn_dflt$parse / dflt$parse$exn : already defined -- SKIPPED

;;;====================================================================
;;; [srcgen1_prelude_node.js]
;;;
;;; Node I/O variants.  g_stdout -> (current-output-port),
;;; process.stdout.write -> (display rep port).
;;;====================================================================

(define (XATS2JS_NODE_g_print obj)
  (display (xats_value_string obj) (current-output-port))
  (if #f #f))
(define (XATS2JS_NODE_bool_print b0)
  (if b0
      (XATS2JS_NODE_g_print "true")
      (XATS2JS_NODE_g_print "false"))
  (if #f #f))
(define (XATS2JS_NODE_char_print c0)
  (XATS2JS_NODE_g_print (string (integer->char c0)))
  (if #f #f))
(define (XATS2JS_NODE_gint_print$sint x0)
  (XATS2JS_NODE_g_print x0) (if #f #f))
(define (XATS2JS_NODE_gint_print$uint x0)
  (XATS2JS_NODE_g_print x0) (if #f #f))
(define (XATS2JS_NODE_gflt_print$sflt x0)
  (XATS2JS_NODE_g_print x0) (if #f #f))
(define (XATS2JS_NODE_gflt_print$dflt x0)
  (XATS2JS_NODE_g_print x0) (if #f #f))
(define (XATS2JS_NODE_strn_print cs)
  (XATS2JS_NODE_g_print cs))
;; the type-suffixed NODE print wrappers (each -> NODE_g_print)
(define (XATS2JS_NODE_sint_print i0) (XATS2JS_NODE_g_print i0) (if #f #f))
(define (XATS2JS_NODE_uint_print i0) (XATS2JS_NODE_g_print i0) (if #f #f))
(define (XATS2JS_NODE_sflt_print f0) (XATS2JS_NODE_g_print f0) (if #f #f))
(define (XATS2JS_NODE_dflt_print f0) (XATS2JS_NODE_g_print f0) (if #f #f))

;; -- NODE process --
(define (XATS2JS_NODE_argv$get)
  (command-line))
(define (XATSOPT_argv$get)
  (XATS2JS_NODE_argv$get))
;; XATSOPT_XATSHOME_get : already defined (cats) -- SKIPPED
;; XATSOPT_fpath_rexists / fpath_full$read : already defined -- SKIPPED

;;;====================================================================
;;; [srcgen1_xatslib_node.js]
;;;
;;; Node fs / stdio.  g_stdin/out/err -> Chez ports; fprint -> display.
;;;====================================================================

(define (XATS2JS_NODE_g_stdin) (current-input-port))
(define (XATS2JS_NODE_g_stdout) (current-output-port))
(define (XATS2JS_NODE_g_stderr) (current-error-port))
(define (XATS2JS_NODE_g_fprint obj out)
  (display (xats_value_string obj) out)
  (if #f #f))
(define (XATS2JS_NODE_bool_fprint obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_char_fprint obj out)
  (XATS2JS_NODE_g_fprint (string (integer->char obj)) out)
  (if #f #f))
(define (XATS2JS_NODE_strn_fprint obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_sint_fprint obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_uint_fprint obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_gint_fprint$sint obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_gint_fprint$uint obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_gflt_fprint$sflt obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_gflt_fprint$dflt obj out)
  (XATS2JS_NODE_g_fprint obj out) (if #f #f))
(define (XATS2JS_NODE_fs_rexists fpx)
  (if (file-exists? fpx) 1 0))
(define (XATS2JS_NODE_fs_readFileSync fpx)
  (call-with-input-file fpx
    (lambda (port)
      (let loop ((acc '()))
        (let ((ch (read-char port)))
          (if (eof-object? ch)
              (list->string (reverse acc))
              (loop (cons ch acc))))))))

;;;====================================================================
;;; end of [xats2chez_jsrt.scm]
;;;====================================================================
