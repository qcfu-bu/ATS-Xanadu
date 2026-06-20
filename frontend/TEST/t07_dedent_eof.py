# layout edge case: dedent-to-EOF — the file ends DEEP inside nested blocks with
# NO trailing newline; the layout pass must emit all the closing DEDENTs at EOF.
def outer(n: Int) -> Int:
    if n > 0:
        let a = 1
        let b = 2
        a + b