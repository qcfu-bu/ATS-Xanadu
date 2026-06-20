# record literal (uses '=' for fields) + comment + blank line + a float/string/char
type Point = { x: Int, y: Int }

let origin = { x = 0, y = 3.14 }

let s = "he\"llo"
let c = 'a'
let hex = 0xFF
let ok = true and not false
