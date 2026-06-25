enum VBox[A: Linear]:
    case VWrap(A)

def unwrapv(b: VBox[Int]) -> Int:
    match b:
        case VWrap(x): x
