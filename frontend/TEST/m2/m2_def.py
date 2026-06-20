def fact(n: Int) -> Int:
    if n <= 0: 1
    elif n == 1: 1
    else: n * fact(n - 1)
