;; self-host validation for xlabel0 (labels: LABint ctag0, LABsym ctag1).
(define (mk_labint i) (XATSCAPP 0 i))
(define (mk_labsym s) (XATSCAPP 1 s))
(display (label_cmp (mk_labint 0) (mk_labint 2))) (display " ")  ; -1
(display (label_cmp (mk_labint 2) (mk_labint 0))) (display " ")  ;  1
(display (label_cmp (mk_labint 1) (mk_labint 1))) (newline)       ;  0
(display (label_cmp (mk_labsym (symbl_make_name "foo"))
                    (mk_labsym (symbl_make_name "foo")))) (newline) ; 0
