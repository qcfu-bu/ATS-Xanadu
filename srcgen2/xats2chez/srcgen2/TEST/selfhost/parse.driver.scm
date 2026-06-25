;; self-host validation: the chez-compiled FRONTEND parses an ATS snippet.
;; d0parsed_from_atext(stadyn, source-string) -> d0parsed (lex + d0 parse).
(display ";;== SELFHOST PARSE TEST ==") (newline)
(define src1 "val x = 5\n")
(display ";; src1: ") (display src1)
(define dp1 (d0parsed_from_atext 1 src1))
(display ";; src1 parsed OK") (newline)
(define src2 "fun f (x: int): int = x\nval y = f(3)\n")
(define dp2 (d0parsed_from_atext 1 src2))
(display ";; src2 parsed OK") (newline)
(display ";;== PARSE TEST DONE ==") (newline)
