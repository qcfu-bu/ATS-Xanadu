def find(grid: Grid, target: Int) -> Pair:
    let mut i = 0
    for row in grid:
        let mut j = 0
        for cell in row:
            if cell == target:
                return (i, j)
            j = j + 1
        i = i + 1
    return (-1, -1)
