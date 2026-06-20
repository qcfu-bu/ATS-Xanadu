def sum_upto(n: Int) -> Int:
    let mut total = 0
    let mut i = 1
    while i <= n:
        total = total + i
        i = i + 1
    total

def first_even(xs: List[Int]) -> Int:
    for x in xs:
        if x % 2 == 0: return x
        continue
    else:
        return -1
