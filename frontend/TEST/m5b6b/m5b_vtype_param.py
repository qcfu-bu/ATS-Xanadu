enum VBox[A: VType]:
    case VWrap(A)

def unwrapv(b: VBox[Int]) -> Int:
    match b:
        case VWrap(x): x
