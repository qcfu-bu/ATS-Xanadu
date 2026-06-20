enum Tree[A]:
    case Leaf
    case Node(A, Tree[A])

def root(t: Tree[Int]) -> Int:
    match t:
        case Leaf: 0
        case Node(x, rest): x
