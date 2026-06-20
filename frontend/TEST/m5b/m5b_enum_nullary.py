enum Color:
    case Red
    case Green
    case Blue

def rank(c: Color) -> Int:
    match c:
        case Red: 0
        case Green: 1
        case Blue: 2
