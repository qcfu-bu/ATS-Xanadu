#!/usr/bin/env python3
"""xform-prints.py — rewrite multi-arg prints/printsln calls to SEQUENCED
single-arg print calls, in ATS3 frontend sources.

WHY (see docs/02-self-hosting-status.md): multi-arg `prints(a, b, ...)`
resolves to the srcgen1-prelude gs_print_nN ALIAS-form defaults with a
QUANTIFIED hook impl, which the srcgen2 resolver cannot instantiate — the
selfhost binary bridges them to the runtime generic printer, which cannot
render frontend constructors (Go cons carry no names).  Sequenced
single-arg `print(x)` resolves per-value through the CONCRETE tmplib
g_print<T> instances; the printed BYTES are identical on the JS side.

    prints(a1, ..., an)   -> (print(a1); ...; print(an))
    printsln(a1, ..., an) -> (print(a1); ...; print(an); printsln())
    printsln()            -> unchanged

The lexer honors ATS strings ("...", with \\-escapes), char literals
('c' / '\\n'), nested (* *) comments, and // line comments; call sites
inside comments or strings are untouched.  Only whole-word matches with
no preceding identifier char (or $) are rewritten.
"""
import sys, re

NAMES = ("printsln", "prints")  # longest first


def lex_regions(src):
    """Yield (start, end, kind) for comment/string/char regions."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            yield (i, j, 'line')
            i = j
        elif c == '(' and src.startswith('(*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith('(*', j):
                    depth += 1
                    j += 2
                elif src.startswith('*)', j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            yield (i, j, 'blk')
            i = j
        elif c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                elif src[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            yield (i, j, 'str')
            i = j
        elif c == "'":
            # char literal: 'x' or '\x' (possibly multi like '\\n')
            j = i + 1
            if j < n and src[j] == '\\':
                j += 2
                while j < n and src[j] != "'":
                    j += 1
                j += 1
            elif j + 1 < n and src[j + 1] == "'":
                j += 2
            else:
                i += 1
                continue
            yield (i, j, 'chr')
            i = j
        else:
            i += 1


def in_region(pos, regions):
    for a, b, _ in regions:
        if a <= pos < b:
            return True
    return False


def find_close(src, i, regions):
    """src[i] == '(': index just past the matching ')'."""
    depth, n = 0, len(src)
    while i < n:
        if in_region(i, regions):
            for a, b, _ in regions:
                if a <= i < b:
                    i = b
                    break
            continue
        c = src[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced parens')


def split_args(src, a, b, regions):
    """Top-level comma split of src[a:b]."""
    args, depth, last = [], 0, a
    i = a
    while i < b:
        if in_region(i, regions):
            for x, y, _ in regions:
                if x <= i < y:
                    i = y
                    break
            continue
        c = src[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(src[last:i])
            last = i + 1
        i += 1
    args.append(src[last:b])
    return [x.strip() for x in args]


def transform(src):
    regions = list(lex_regions(src))
    out, i, n, count = [], 0, len(src), 0
    while i < n:
        m = None
        for nm in NAMES:
            if src.startswith(nm, i):
                m = nm
                break
        if (m and not in_region(i, regions)
                and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] in '_$'))):
            j = i + len(m)
            while j < n and src[j] in ' \t\n':
                j += 1
            if j < n and src[j] == '(':
                k = find_close(src, j, regions)
                args = split_args(src, j + 1, k - 1, regions)
                if len(args) == 1 and args[0] == '':
                    args = []
                if args:
                    parts = ['print(%s)' % a for a in args]
                    if m == 'printsln':
                        parts.append('printsln()')
                    out.append('(' + '; '.join(parts) + ')')
                    count += 1
                    i = k
                    continue
        out.append(src[i])
        i += 1
    return ''.join(out), count


def main():
    total = 0
    for path in sys.argv[1:]:
        with open(path) as f:
            src = f.read()
        new, cnt = transform(src)
        if cnt:
            with open(path, 'w') as f:
                f.write(new)
        print('%s: %d call(s) rewritten' % (path, cnt))
        total += cnt
    print('TOTAL: %d' % total)


if __name__ == '__main__':
    main()
