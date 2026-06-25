enum Duo:
    case Empty
    case Both(Int, Int)

def has_payload(d: Duo) -> Bool:
    match d:
        case Both(_): true
        case Empty: false
