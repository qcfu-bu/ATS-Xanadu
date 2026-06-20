enum Opt[A]:
    case Nothing
    case Just(A)

def unwrap(o: Opt[Int]) -> Int:
    match o:
        case Nothing: 0
        case Just(x): x
