def apply(f: (Int) -> Int, x: Int) -> Int:
    f(x)

def double(x: Int) -> Int:
    x + x

def go() -> Int:
    apply(double, 5)
