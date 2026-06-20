type Tree[a] = Leaf | Node(Tree[a], a, Tree[a])

def sum_tree(t: Tree[Int]) -> Int:
    match t:
        case Leaf: 0
        case Node(l, x, r): sum_tree(l) + x + sum_tree(r)
