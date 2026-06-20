def clamp(x: Int, lo: Int, hi: Int) -> Int:
    if x < lo:
        lo
    elif x > hi:
        hi
    else:
        x
