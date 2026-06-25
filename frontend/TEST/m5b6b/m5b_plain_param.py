enum PBox[A]:
    case PWrap(A)

def unwrapp(b: PBox[Int]) -> Int:
    match b:
        case PWrap(x): x
