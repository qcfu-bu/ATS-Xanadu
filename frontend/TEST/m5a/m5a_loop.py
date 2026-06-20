def sum_upto(n: Int) -> Int:
    let mut acc: Int = 0
    let mut i: Int = 0
    while i < n:
        acc = acc + i
        i = i + 1
    acc
