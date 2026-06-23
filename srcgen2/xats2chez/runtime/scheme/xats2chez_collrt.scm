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
