enum Opt:
    case Nothing
    case Just(Int)

def unwrap(o: Opt) -> Int:
    match o:
        case Nothing: 0
        case Just(x): x
