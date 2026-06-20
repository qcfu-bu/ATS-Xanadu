enum Tree[A]:
    case Leaf
    case Node(Tree[A], A, Tree[A])

def sum_tree(t: Tree[Int]) -> Int:
    match t:
        case Leaf: 0
        case Node(l, x, r): sum_tree(l) + x + sum_tree(r)
