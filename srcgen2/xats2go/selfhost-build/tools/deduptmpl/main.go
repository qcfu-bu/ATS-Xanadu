// deduptmpl — same-package dedup of lifted template instances.
//
// The per-module emitter lifts capture-free instances to named package
// funcs (goxtmpl<stamp>, renamed go<N>tmpl<stamp> by assemble.sh), but the
// one-shot compiler cannot see across modules: the SAME logical instance
// (g_print<d0exp>, ...) is re-emitted by every module that uses it.
// Measured on the selfhost assembly: 3,766 lifted instances, ~450 unique
// bodies.
//
// This pass rewrites ONE package file in place: bodies that are identical
// up to ANF-temp alpha-renaming (go\w*tnm<N> normalized; references to
// OTHER instances must match exactly) keep their FIRST copy; later copies
// are deleted and every reference is renamed to the canonical name.
// Renaming creates new equalities (instance families reference each
// other), so hashing iterates to a fixpoint.
//
// Invoked by split-src.sh per package file; go run is fast enough (<1s).
package main

import (
	"crypto/md5"
	"fmt"
	"os"
	"regexp"
	"strings"
)

var declRe = regexp.MustCompile(`(?m)^func (go\w*?tmpl\d+)\([^)]*\)[^{\n]*\{`)
var tnmRe = regexp.MustCompile(`go\w*?tnm\d+`)
var headRe = regexp.MustCompile(`^func go\w*?tmpl\d+`)

type fn struct {
	name       string
	start, end int // [start, end) byte span incl. trailing newline
	body       string
}

// bodyEnd scans from the opening '{' to its matching '}', skipping Go
// string literals, rune literals, and comments -- the emitter package's
// own bodies contain emitted-code fragments (braces included) inside
// string literals.
func bodyEnd(txt string, open int) int {
	depth := 0
	j := open
	for j < len(txt) {
		switch txt[j] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return j
			}
		case '"':
			j++
			for j < len(txt) && txt[j] != '"' {
				if txt[j] == '\\' {
					j++
				}
				j++
			}
		case '\'':
			j++
			for j < len(txt) && txt[j] != '\'' {
				if txt[j] == '\\' {
					j++
				}
				j++
			}
		case '`':
			j++
			for j < len(txt) && txt[j] != '`' {
				j++
			}
		case '/':
			if j+1 < len(txt) {
				if txt[j+1] == '/' {
					for j < len(txt) && txt[j] != '\n' {
						j++
					}
				} else if txt[j+1] == '*' {
					j += 2
					for j+1 < len(txt) && !(txt[j] == '*' && txt[j+1] == '/') {
						j++
					}
					j++
				}
			}
		}
		j++
	}
	return len(txt) - 1
}

func extract(txt string) []fn {
	var out []fn
	for _, m := range declRe.FindAllStringSubmatchIndex(txt, -1) {
		j := bodyEnd(txt, m[1]-1)
		end := j + 1
		if end < len(txt) && txt[end] == '\n' {
			end++
		}
		out = append(out, fn{
			name:  txt[m[2]:m[3]],
			start: m[0],
			end:   end,
			body:  txt[m[0]:end],
		})
	}
	return out
}

// renameIdents applies whole-word renames.  Names are go<...>tmpl<digits>,
// so a following non-word byte is the boundary; string literals cannot
// contain these assembled names (the emitter's own emitted-code fragments
// use the pre-assembly "goxtmpl" spelling, digit-free).
func renameIdents(s string, ren map[string]string) string {
	if len(ren) == 0 {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	i := 0
	for i < len(s) {
		if s[i] == 'g' && strings.HasPrefix(s[i:], "go") {
			j := i
			for j < len(s) && (isWord(s[j])) {
				j++
			}
			word := s[i:j]
			if c, ok := ren[word]; ok {
				b.WriteString(c)
			} else {
				b.WriteString(word)
			}
			i = j
			continue
		}
		b.WriteByte(s[i])
		i++
	}
	return b.String()
}

func isWord(c byte) bool {
	return c == '_' || ('0' <= c && c <= '9') || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: deduptmpl <pkgfile.go>")
		os.Exit(2)
	}
	path := os.Args[1]
	raw, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "deduptmpl:", err)
		os.Exit(1)
	}
	txt := string(raw)
	fns := extract(txt)

	rename := map[string]string{}
	for {
		// path-compress before each round so hashing sees LIVE names (a
		// later round can rename an earlier round's canonical: A->B->C).
		for a, c := range rename {
			for {
				next, dead := rename[c]
				if !dead {
					break
				}
				c = next
			}
			rename[a] = c
		}
		canon := map[[16]byte]string{}
		grew := false
		for _, f := range fns {
			if _, dead := rename[f.name]; dead {
				continue
			}
			b := renameIdents(f.body, rename)
			norm := tnmRe.ReplaceAllString(b, "T")
			norm = headRe.ReplaceAllString(norm, "func F")
			h := md5.Sum([]byte(norm))
			if c, ok := canon[h]; ok {
				rename[f.name] = c
				grew = true
			} else {
				canon[h] = f.name
			}
		}
		if !grew {
			break
		}
	}
	if len(rename) == 0 {
		fmt.Printf(">> deduptmpl %s: %d instances, 0 duplicates\n", path, len(fns))
		return
	}

	// PATH COMPRESSION: a later fixpoint round can rename a name that an
	// earlier round chose as canonical (A->B, then B->C) -- follow chains
	// so every mapping points at a LIVE name.
	for a, c := range rename {
		for {
			next, dead := rename[c]
			if !dead {
				break
			}
			c = next
		}
		rename[a] = c
	}

	// rebuild: drop dead decls, then rename references globally.
	var b strings.Builder
	b.Grow(len(txt))
	pos := 0
	for _, f := range fns {
		if _, dead := rename[f.name]; dead {
			b.WriteString(txt[pos:f.start])
			pos = f.end
		}
	}
	b.WriteString(txt[pos:])
	out := renameIdents(b.String(), rename)
	if err := os.WriteFile(path, []byte(out), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "deduptmpl:", err)
		os.Exit(1)
	}
	fmt.Printf(">> deduptmpl %s: %d instances, %d duplicates removed\n",
		path, len(fns), len(rename))
}
