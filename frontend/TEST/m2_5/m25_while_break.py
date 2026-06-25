def read_total() -> Int:
    let mut total = 0
    while true:
        let line = read_line()
        if line == "":
            break
        total = total + length(line)
    return total
