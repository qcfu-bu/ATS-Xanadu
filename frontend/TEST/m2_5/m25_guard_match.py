def classify(n: Int) -> Int:
    match n:
        case x if x < 0:
            return 0
        case 0:
            return 1
        case x if x > 100:
            return 3
        case x:
            return 2
