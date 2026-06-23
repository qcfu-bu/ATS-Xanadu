;; self-host validation: the SYMBOL TABLE (interning, global map, linear options).
(define s1 (symbl_make_name "hello"))
(define s2 (symbl_make_name "hello"))
(define s3 (symbl_make_name "world"))
(display (symbl_get_name s1)) (display "/") (display (symbl_get_name s3)) (newline)
(display (symbl_cmp s1 s2)) (display " ")                 ; 0 : interned "hello" == "hello"
(display (if (= 0 (symbl_cmp s1 s3)) 0 1)) (newline)      ; 1 : differ
