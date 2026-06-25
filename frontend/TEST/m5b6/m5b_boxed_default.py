enum BOpt:
    case BNone
    case BSome(Int)

struct BPair:
    a: Int
    b: Int

def use_bopt(o: BOpt) -> Int:
    match o:
        case BNone: 0
        case BSome(x): x

def bfst(p: BPair) -> Int:
    p.a
