enum Tree:
    case Leaf
    case Node(Tree, Int, Tree)

def root(t: Tree) -> Tree:
    match t:
        case Leaf: t
        case Node(l, x, r) as whole: whole
