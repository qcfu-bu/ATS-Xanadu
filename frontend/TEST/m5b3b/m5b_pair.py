struct Pair[A, B]:
    fst: A
    snd: B

def first(p: Pair[Int, Int]) -> Int:
    p.fst
