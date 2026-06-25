@linear
enum LOpt:
    case LNone
    case LSome(Int)

def use_lopt(o: LOpt) -> Int:
    match o:
        case LNone: 0
        case LSome(x): x
