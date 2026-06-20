@viewtype
enum Tree[A: VType @unboxed]:
    case Nil
    case Cons(A, Tree[A])

struct Point[A]:
    x: A
    y: A

type Ints = List[Int]
