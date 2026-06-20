def sum_count(n: Int) -> Int:
    let mut acc = 0
    let mut cnt = 0
    for i in range(0, n):
        acc = acc + i
        cnt = cnt + 1
    acc
