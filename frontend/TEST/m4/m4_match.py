def classify(n: Int) -> Int:
    match n:
        case 0:
            100
        case x if x < 0:
            200
        case x:
            300
