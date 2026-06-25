def first_hit(xs: List[Int]) -> Int:
    let mut found = 0
    for x in xs:
        if x > 0:
            found = x
            break
    found
