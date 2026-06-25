def search(xs: List[Int]) -> Int:
    let mut found = 0
    for x in xs:
        if pred(x):
            found = x
            break
    else:
        found = handle_not_found()
    found
