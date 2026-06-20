def scan_until() -> Int:
    let mut found = 0
    while true:
        let x = next_item()
        if x == 0:
            break
        if pred(x):
            found = x
            break
    else:
        found = handle_exhausted()
    found
