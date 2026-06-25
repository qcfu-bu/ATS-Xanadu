def normalize(xs: List[Int], k: Int) -> List[Int]:
    let doubled = map(xs, (x) => x * 2)
    let g = (acc, x) =>
        let y = x + k
        cons(y, acc)
    fold(doubled, [], g)
