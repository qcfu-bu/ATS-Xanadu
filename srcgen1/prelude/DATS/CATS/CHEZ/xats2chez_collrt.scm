;;;====================================================================
;;; xats2chez_collrt.scm — collection runtime floor: the linear list / lazy
;;; stream low-level constructors + accessors (analog of the JS precats), plus
;;; the higher-order ops that the JS backend gets via trxi0i1 instance
;;; materialization (which the intrep0-direct chez emitter skips).
;;; Reps (CANONICAL JS-precats tags): strmcon_vt_nil=#(0), strmcon_vt_cons=#(1 h t)
;;; (a terminating strm_vt); strxcon_vt_cons=#(0 h t) (an INFINITE strx_vt, no nil).
;;; A lazy stream is an l1azy thunk forcing to a strmcon/strxcon cell.  Higher-order
;;; ops take their continuation as a trailing arg (lambda-lifting + map seeding).
;;;====================================================================

;; strmcon_vt (a FORCED strm_vt cell) + list_vt (a linear list): nil/cons/tests.
(define (strmcon_vt_nil) (vector 0))
(define (strmcon_vt_cons h t) (vector 1 h t))          ; t : lazy strm_vt
(define (strmcon_vt_sing x) (vector 1 x (XATS000_l1azy (lambda (_) (vector 0)))))
(define (strmcon_vt_nilq1 s) (= (vector-ref s 0) 0))
(define (strmcon_vt_consq1 s) (= (vector-ref s 0) 1))
;; strxcon_vt (a FORCED strx_vt cell): the lone constructor strxcon_vt_cons = #(0 h t).
(define (strxcon_vt_cons h t) (vector 0 h t))          ; t : lazy strx_vt
(define (list_vt_nilq1 xs) (= (vector-ref xs 0) 0))
(define (list_vt_consq1 xs) (= (vector-ref xs 0) 1))
(define (list_vt_head$raw1 xs) (vector-ref xs 1))
(define (list_vt_tail$raw0 xs) (vector-ref xs 2))
(define (strm_vt_nil) (XATS000_l1azy (lambda (_) (vector 0))))

;;;--------------------------------------------------------------------
;;; mydict (= pyhmap): a mutable dictionary backed by a Chez hashtable.
;;; The compiler keys dicts by interned symbols / strings, so value
;;; equality (equal-hash/equal?) is the safe hash.  Reps:
;;;   mydict          -> a Chez hashtable
;;;   mydict_search$opt-> optn_vt:  None=#(0), Some(x)=#(1 x)
;;;   mydict_get_keys -> mya1sz   :  a Scheme vector of keys
;;; insert mutates and returns void (XATSTOP0).
;;;--------------------------------------------------------------------
(define pyhmap--absent (list 'pyhmap-absent))           ; unique miss sentinel
(define (XATS2PY_pyhmap_make_nil) (make-hashtable equal-hash equal?))
(define (XATS2PY_pyhmap_insert$any m k x) (hashtable-set! m k x) XATSTOP0)
(define (XATS2PY_pyhmap_search$opt m k)
  (let ((r (hashtable-ref m k pyhmap--absent)))
    (if (eq? r pyhmap--absent) (vector 0) (vector 1 r))))
(define (XATS2PY_pyhmap_get_keys m) (hashtable-keys m))   ; -> vector (mya1sz)
;; XATSOPT_mydict_* : the non-FFI flavor (xlibext_tmplib) — same hashtable rep.
(define (XATSOPT_mydict_make_nil) (make-hashtable equal-hash equal?))
(define (XATSOPT_mydict_insert$any m k x) (hashtable-set! m k x) XATSTOP0)
(define (XATSOPT_mydict_search$opt m k)
  (let ((r (hashtable-ref m k pyhmap--absent)))
    (if (eq? r pyhmap--absent) (vector 0) (vector 1 r))))
(define (XATSOPT_mydict_get_keys m) (hashtable-keys m))

;;; mya1sz (= pya1sz): a sized array of keys, rep = Scheme vector.  strmize
;;; turns it into a terminating lazy strm_vt (l1azy thunk -> strmcon cell:
;;; nil=#(0), cons=#(1 head lazytail)).
(define (pya1sz--strmize v i n)
  (XATS000_l1azy (lambda (_)
    (if (>= i n) (vector 0)
        (vector 1 (vector-ref v i) (pya1sz--strmize v (+ i 1) n))))))
(define (XATS2PY_pya1sz_strmize v) (pya1sz--strmize v 0 (vector-length v)))
(define (XATSOPT_mya1sz_strmize v) (pya1sz--strmize v 0 (vector-length v)))
