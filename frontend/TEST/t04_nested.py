# a nested block with a let mut + while loop (layout: INDENT/DEDENT nesting)
def sum_upto(n: Int) -> Int:
    let mut total = 0
    let mut i = 1
    while i <= n:
        total = total + i
        i = i + 1
    total
