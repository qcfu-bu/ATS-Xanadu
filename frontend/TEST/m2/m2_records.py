from "prelude" import *

type Point = { x: Int, y: Int }

def manhattan(p: Point, q: Point) -> Int:
    abs(p.x - q.x) + abs(p.y - q.y)

let origin = { x = 0, y = 0 }
let p = { x = 3, y = 4 }
print_int(manhattan(origin, p))
