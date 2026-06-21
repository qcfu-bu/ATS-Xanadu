@linear
enum Tree[A: Linear @unboxed]:
    case Nil
    case Cons(A, Tree[A])

enum Shape:
    case Circle(Float)
    case Rect(Float, Float)

struct Point[A]:
    x: A
    y: A

type Ints = List[Int]
