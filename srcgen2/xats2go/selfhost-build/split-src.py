#!/usr/bin/env python3
"""
split-src.py — split the assembled single-package selfhost source into
multiple Go packages so no package object approaches the goobj 4GB
(uint32-offset) linker limit.

Consumes src/emitter_all.go (with //==ZZMOD:name==, //==ZZINIT==,
//==ZZLAYOUTS== markers from assemble.sh), src/zz_floor.go, src/zz_shims.go
(with //==ZZSHIMS:{base,main,cc}== markers) and src/zz_driver.go; produces

    src/zzbase/zzbase.go   layouts + CATS/GO floor + base shims
    src/zzfe1/zzfe1.go     frontend modules  xbasics .. xfixity
    src/zzfe2/zzfe2.go     frontend modules  staexp1 .. f2perr0_decl00
    src/zzfe3/zzfe3.go     frontend modules  dynexp3 .. xatsopt_utils0
    src/zzcc/zzcc.go       xats2cc lowering modules + i0varfst shims
    src/zzgo/zzgo.go       the emitter's own modules
    src/zz_driver.go       (rewritten)  package main: driver
    src/zz_init.go         package main: master modinit + main shims

and deletes emitter_all.go / zz_floor.go / zz_shims.go.

Mechanism: every cross-package symbol keeps a single global identity — a
lowercase crossing symbol is renamed with a `Z_` prefix (exported) at its
def site AND every reference, in every package; each package dot-imports
the earlier packages it actually references, so reference sites stay
unqualified.  Renaming is STRING/COMMENT-AWARE: the emitter's own source
contains fragments of the Go code it emits as string literals (zzs_/zzpzzs_
layout names etc.) which must NOT be rewritten, or the self-hosted binary's
emissions would diverge from the bundle's.

The module reference graph follows the ATS staload DAG (a module only calls
earlier modules), which the package order mirrors; any backward reference is
reported and the split ABORTS (an expressible-import-cycle would otherwise
surface as a confusing go build error).
"""
import os, re, sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
ASM = os.path.join(SRC, "emitter_all.go")
ASSEMBLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assemble.sh")

FE1_END = "xfixity"          # last module of zzfe1 (lexing/parsing layer)
FE2_END = "f2perr0_decl00"   # last module of zzfe2 (trans01/12/2a layer)

# NB the lexing/parsing block and the trans01/12 block form ONE package
# (zzfe2): xglobal sits early in the build list but hosts the pvsload
# machinery that INVOKES the pass chain (d1parsed_of_trans01 /
# d2parsed_of_trans12), while the parsing layer reads xglobal's globals
# (the_XATSHOME, the_xatsopt_include) — a genuine knot at package
# granularity, so the two layers merge.
OVERRIDE = {}

PKGS = ["zzbase", "zzfe2", "zzfe3", "zzcc", "zzgo", "main"]

# Go token alternation: strings/comments pass through untouched; identifiers
# are candidates.  Order matters (longest-match alternatives first).
TOK = re.compile(
    r'`[^`]*`'
    r'|"(?:\\.|[^"\\])*"'
    r"|'(?:\\.|[^'\\])*'"
    r'|//[^\n]*'
    r'|/\*.*?\*/'
    r'|[A-Za-z_][A-Za-z0-9_]*', re.S)

DEF = re.compile(r'^(?:func|var|type|const)\s+([A-Za-z_]\w*)', re.M)


def die(msg):
    print("!! split-src: " + msg, file=sys.stderr)
    sys.exit(1)


def read(p):
    with open(p) as f:
        return f.read()


def module_lists():
    """FRONTEND and CCMODS module names, parsed from assemble.sh itself so
    the partition can never drift from the assembly."""
    txt = read(ASSEMBLE)
    m = re.search(r'^FRONTEND="([^"]+)"', txt, re.M)
    c = re.search(r'^CCMODS="([^"]+)"', txt, re.M)
    if not (m and c):
        die("cannot parse FRONTEND/CCMODS from assemble.sh")
    return m.group(1).split(), c.group(1).split()


def parse_marked(text, marker_re):
    """[(name, chunk)] for //==<marker>:name== sections; text before the
    first marker is returned under the name None."""
    parts = re.split(marker_re, text)
    out = [(None, parts[0])]
    for i in range(1, len(parts), 2):
        out.append((parts[i], parts[i + 1]))
    return out


def idents(text):
    s = set()
    for m in TOK.finditer(text):
        t = m.group(0)
        if t[0].isalpha() or t[0] == '_':
            s.add(t)
    return s


def rename(text, crossing):
    def sub(m):
        t = m.group(0)
        if (t[0].isalpha() or t[0] == '_') and t in crossing:
            return 'Z_' + t
        return t
    return TOK.sub(sub, text)


def main():
    if not os.path.exists(ASM):
        print(">> split-src: no emitter_all.go — nothing to split")
        return

    frontend, ccmods = module_lists()
    if FE1_END not in frontend or FE2_END not in frontend:
        die("partition boundary module missing from FRONTEND")
    fe1 = set(frontend[:frontend.index(FE1_END) + 1])
    fe2 = set(frontend[frontend.index(FE1_END) + 1:frontend.index(FE2_END) + 1])
    fe3 = set(frontend[frontend.index(FE2_END) + 1:])
    cc = set(ccmods)

    def pkg_of(mod):
        if mod in OVERRIDE: return OVERRIDE[mod]
        if mod in fe1: return "zzfe2"  # merged with the trans layer (see above)
        if mod in fe2: return "zzfe2"
        if mod in fe3: return "zzfe3"
        if mod in cc: return "zzcc"
        return "zzgo"  # the emitter's own DATS glob (first group in assembly)

    # ---- gather chunks per package -------------------------------------
    body = {p: [] for p in PKGS}

    asm = read(ASM)
    for name, chunk in parse_marked(asm, r'//==ZZ([A-Z]+:?\w*)==\n'):
        if name is None:
            continue  # the package-main header — synthesized anew below
        if name == "INIT":
            body["main"].append(chunk)
        elif name == "LAYOUTS":
            body["zzbase"].append(chunk)
        elif name.startswith("MOD:"):
            body[pkg_of(name[4:])].append(chunk)
        else:
            die("unknown assembly marker: " + name)

    floor_p = os.path.join(SRC, "zz_floor.go")
    if os.path.exists(floor_p):
        ftxt = read(floor_p)
        # strip its `package main` + import header; imports are recomputed.
        fbody = re.split(r'^import \([^)]*\)\s*$', ftxt, maxsplit=1, flags=re.M)
        body["zzbase"].append(fbody[1] if len(fbody) == 2 else
                              re.sub(r'^package main\s*', '', ftxt))

    shims_p = os.path.join(SRC, "zz_shims.go")
    if os.path.exists(shims_p):
        for name, chunk in parse_marked(read(shims_p), r'//==ZZSHIMS:(\w+)==\n'):
            if name is None:
                continue  # header
            body[{"base": "zzbase", "cc": "zzcc", "main": "main"}[name]].append(chunk)

    drv_p = os.path.join(SRC, "zz_driver.go")
    drv_lines = read(drv_p).split('\n')
    st = 0
    for i, ln in enumerate(drv_lines):
        if ln.startswith('func ') or (ln.startswith('var ') and not ln.startswith('var _')):
            st = i
            break
    drv_body = '\n'.join(drv_lines[st:])

    # ---- defs / crossing ------------------------------------------------
    texts = {p: '\n'.join(body[p]) for p in PKGS}
    texts["main"] = texts["main"] + '\n' + drv_body
    # never treat `init`/`main` as package symbols: renaming either would
    # silently break Go initialization/entry semantics.
    defs = {p: set(DEF.findall(texts[p])) - {'_', 'init', 'main'} for p in PKGS}
    idset = {p: idents(texts[p]) for p in PKGS}

    dup = set()
    for i, p in enumerate(PKGS):
        for q in PKGS[i + 1:]:
            dup |= (defs[p] & defs[q])
    if dup:
        die("symbol defined in TWO packages (partition broken): " +
            " ".join(sorted(dup)[:8]))

    crossing = set()
    deps = {p: set() for p in PKGS}
    order = {p: i for i, p in enumerate(PKGS)}
    back = []
    for p in PKGS:
        for q in PKGS:
            if p == q:
                continue
            used = defs[p] & idset[q]
            if not used:
                continue
            if order[q] < order[p]:
                back.append((q, p, sorted(used)[:6]))
            deps[q].add(p)
            crossing |= {u for u in used if not u[0].isupper()}
            # uppercase defs referenced cross-package need no rename but DO
            # need the dot-import (recorded in deps above).
    if back:
        for q, p, names in back:
            print(f"!! BACKWARD REF: {q} uses symbols of LATER package {p}: {names}",
                  file=sys.stderr)
        die("package order violated — adjust the partition")

    # ---- write packages -------------------------------------------------
    modname = "selfhostemit"

    def header(pkg, pretext):
        # per-FILE dot-imports (Go errors on an unused import per file, and
        # package main spans two files with different reference sets).
        # Computed on the PRE-rename text: defs[] holds original names.
        tids = idents(pretext)
        imps = []
        for d in PKGS:
            if d == pkg or d == "main":
                continue
            if defs[d] & tids:
                imps.append(f'import . "{modname}/{d}"')
        std = []
        if 'xatsgo.' in pretext:
            std.append('import "xatsgo"')
        if 'unsafe.' in pretext:
            std.append('import "unsafe"')
        for lib in ("fmt", "math", "reflect", "strconv", "strings"):
            if re.search(r'\b' + lib + r'\.', pretext):
                std.append(f'import "{lib}"')
        h = [f'package {"main" if pkg == "main" else pkg}', '']
        h += imps + std
        if 'import "xatsgo"' in std:
            h.append('var _ = xatsgo.XATSNIL')
        if 'import "unsafe"' in std:
            h.append('var _ unsafe.Pointer')
        return '\n'.join(h) + '\n\n'

    for p in PKGS:
        if p == "main":
            continue
        hdr = header(p, texts[p])
        txt = rename(texts[p], crossing)
        d = os.path.join(SRC, p)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, p + ".go"), 'w') as f:
            f.write(hdr + txt)

    init_pre = '\n'.join(body["main"])
    with open(os.path.join(SRC, "zz_init.go"), 'w') as f:
        f.write(header("main", init_pre) + rename(init_pre, crossing))
    with open(drv_p, 'w') as f:
        f.write(header("main", drv_body) + rename(drv_body, crossing))

    for p in (ASM, floor_p, shims_p):
        if os.path.exists(p):
            os.remove(p)

    sizes = {p: texts[p].count('\n') for p in PKGS}
    print(">> split-src: " + "  ".join(f"{p}:{sizes[p]}" for p in PKGS) +
          f"  crossing:{len(crossing)}")


if __name__ == "__main__":
    main()
