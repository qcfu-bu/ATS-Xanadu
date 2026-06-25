# layout edge case: a bracketed multi-line expression — the newlines INSIDE the
# parens/brackets are SUPPRESSED (no NEWLINE/INDENT/DEDENT), then a normal line.
let xs = [
    1,
    2,
    3
]
let r = f(a,
          b,
          c)
