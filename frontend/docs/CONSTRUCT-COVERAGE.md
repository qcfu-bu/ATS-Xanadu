# L0 construct-coverage matrix (the proactive map)

> **Why this exists.** We were finding gaps reactively — run a file, see it break,
> patch the printer/parser/lowering, repeat — which means we never actually knew
> what was left, and each new corpus (the SATS, then the prelude) re-taught us its
> gaps one file at a time. This matrix is the antidote: the set of things ATS can
> express at L0 is **finite and written down** (the `d0ecl`/`d0exp`/`d0pat`/`s0exp`/
> `g0exp` datatypes in `srcgen2/SATS/{dynexp0,staexp0}.sats`). We enumerate every
> variant and audit coverage at each layer. The corpus then passes as a *consequence*
> of construct coverage, not as the thing that drives discovery.

Coverage layers, per construct:
- **PP**  — does `frontend/DATS/pyprint.dats` emit it faithfully (ATS L0 → pythonic)?
- **PR**  — does the pythonic parser accept the emitted form?
- **LO**  — does lowering produce the same L2 the stock parser produces?
- **T**   — is there a focused round-trip test for it?

Audit date: 2026-06-23. PP coverage is verified (constructor occurrence count in
pyprint.dats); usage counts are approximate (grep of source syntax) but
order-of-magnitude correct.

## Inventory + pyprint coverage (authoritative: `build-construct-coverage.sh`)
Run `bash frontend/build-construct-coverage.sh` to regenerate. As of 2026-06-23:

| datatype | emitted / total | missing |
|---|---|---|
| `d0ecl` (declarations)      | 27 / 34 |  7 |
| `d0exp` (dyn expressions)   | 23 / 29 |  6 |
| `d0pat` (patterns)          | 11 / 13 |  2 |
| `s0exp` (static/type exprs) |  7 / 18 | 11 |
| `g0exp` (static/guard exprs)|  5 / 8  |  3 |

~29 missing emitters total; the high-value clusters are below. A handful are minor
literal/internal variants (`S0Echr/flt/str`, `G0Echr/flt`, `D0Esarglst`, `D0Psarg`,
`D0Cdynxgen`, `D0CSTDCL`) — low priority, mostly rare or carried by other paths.
(Error-recovery nodes `*errck`/`*tkerr`/`*tkskp`/`*synext` are excluded — not source
constructs.)

## PP gaps — constructs with NO emitter in pyprint (verified: 0 occurrences)

These are the real, grammar-derived backlog. None of them bit the 153 green `.dats`
because those are implementation bodies; they are concentrated in `.sats` interfaces,
a few specialized `.dats`, and the prelude kernel — exactly the unexplored layer.

### Cluster A — static / sort kernel declarations (the interface + prelude kernel)
> **2026-06-23 — DONE (4/5):** `D0Csortdef`, `D0Cstacst0`, `D0Cabssort`, `D0Cabsopen` now round-trip
> FAITHFUL (zero structural L2-diff; fixtures in `frontend/TEST/l2diff/kernel/`). Surfaces:
> `@sort type N = SInt` (sortdef), `@static let c: SInt` (stacst0), `@sort type N` *no RHS* (abssort),
> `@open type T` (absopen). `D0Cdatasort` is DEFERRED — it embeds a full L1 `D1Cdatasort` node in
> the raw L2's first field (NOT vestigial; it shows as a structural diff), which the L0→L2-direct
> pyfront lowering does not build. See the deferral note at the end of this file.
>
| construct | ATS syntax | srcgen2 | prelude | layers needed |
|---|---|---:|---:|---|
| `D0Csortdef`  | `#sortdef`   | ~56 | 22 | DONE (PP+PR+LO+T) |
| `D0Cabssort`  | `#abssort`   | ~45 | 20 | DONE (PP+PR+LO+T) |
| `D0Cdatasort` | `datasort`   | ~50 |  1 | DEFERRED (needs L1) |
| `D0Cstacst0`  | `#stacst0`   |  *  | 57 | DONE (PP+PR+LO+T) |
| `D0Cabsopen`  | `#absopen`   | ~64 |  0 | DONE (PP+PR+LO+T) |
| `S0Euni0`     | `{..}` univ. type | ~6 | ~20 | PP+PR+LO+T |
| `S0Eexi0`     | `[..]` exist. type | (with above) | | PP+PR+LO+T |
| `S0Eop1/2/3`  | static prefix/infix/postfix ops | ~30 | ~33 | PP+PR+LO+T |
| `S0Elams`/`S0Efimp` | static lambda / fn-impl type | low | low | PP+PR+LO+T |

### Cluster B — fixity DSL
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Cfixity` | `infixl`/`infixr`/`prefix`/`postfix` | ~57 (2 sats,5 dats) | 45 | PP+PR+LO+T; also make our fixed Pratt table source-configurable |
| `D0Cnonfix` | `nonfix` | ~18 | 0 | PP+PR+LO+T |

### Cluster C — FFI / foreign binding
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Eextnam` | `$extnam(...)` | ~30 | **665** | PP+PR+LO+T — the dominant prelude construct |
| `D0Cextcode`| `%{ C %}` | 0 | 0 | defer (corpus-absent; error-clean if hit) |
| `D0Cdyninit`| `dynload` | ~95 | 0 | PP+PR+LO+T |

### Cluster D — records (boxed/flat/linear variants)
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Ercd2` / `S0Ercd2` / `D0Prcd2` | `@{..}`/`${..}`/`~{..}` record value/type/pattern | ~10 | 1 | PP+PR+LO+T |

### Cluster E — macros + misc dyn exprs
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Cmacdef` | `macdef` | ~25 | 0 | PP+PR+LO+T |
| `D0Etry0`   | `try` (ATS→py direction) | 3 | 3 | PP only (py→L2 try already works) |
| `D0Eexists` | `$exists{..}` | low | low | PP+PR+LO+T |
| `D0Efix0`   | `fix`/`fix@` recursive lambda | low | low | PP+PR+LO+T |
| `D0Cdynxgen`/`D0CSTDCL` | (rare/internal) | — | — | investigate; likely defer |

\* `$extnam`/`#stacst` exact counts noisy under grep; treat as "present, needs support".

## Covered constructs (for completeness)
- `d0ecl` covered (PP present): `D0Cabsimpl D0Cabstype D0Cdatatype D0Cdefine
  D0Cdynconst D0Cexcptcon D0Cextern D0Cfundclst D0Cimplmnt0 D0Cinclude D0Clocal0
  D0Csexpdef D0Cstaload D0Cstatic D0Csymload D0Cvaldclst D0Cvardclst` — plus the
  in-flight **named-staload alias** (`#staload SYM = …` → `import "…" as SYM`).
- `d0exp`/`d0pat`/`s0exp`/`g0exp`: the base forms (id, app, tuple, annot, let, if,
  case, lam, where, lpar, raise, qual; con/var/idx/bin/fun/tup types; id/int/app
  guards) are covered — those carry the 153 green `.dats`.

## The proactive roadmap (implement by construct-class, not by file)
Each cluster is a self-contained round-trip feature: settle the pythonic surface,
add the pyprint emitter, the parser rule, the lowering (to the stock L2 — let the
compiler resolve), and ONE focused test per construct. Ordered by leverage:

1. **Cluster C — FFI (`$extnam`, `dynload`)** — unblocks the prelude (665 `$extnam`).
2. **Cluster A — static/sort kernel decls** — unblocks the SATS interfaces + prelude
   `basics0.sats` (the kernel where these are *declared*).
3. **Cluster B — fixity DSL** — `fixity0.sats` + source-configurable operator table.
4. **Cluster D — record variants** — boxed/flat/linear `@{}`/`${}`/`~{}`.
5. **Cluster E — macros + misc** — `macdef`, `try`-emit, `exists`, `fix`.

Once these land, the SATS and prelude pass because their *constructs* are covered —
and the matrix is re-runnable (the audit script in this doc's commit) to prove no
new construct slipped through. This replaces "is it done?" guesses with a grammar
checklist.

## Still to audit (next layers of this matrix)
PP coverage is the first gate (can't parse/lower what isn't emitted). The PR/LO
columns for the COVERED constructs are exercised by the green corpus, but the matrix
should be completed with a per-construct round-trip test so PR/LO are verified
independently, not inferred from corpus files.

## DEFERRED: `D0Cdatasort` (`datasort T = C1 | C2 of (...)`) — needs L1
The other four Cluster-A kernel decls lower L0→L2 directly (the pyfront frontend builds
`d2ecl` nodes straight from its PyCore IR, never constructing intermediate L1 `d1ecl`s,
mirroring how `D2Cdatatype`/`D2Cexcptcon` use a **vestigial** `d1ecl_none0(loc)` for their
L1 slot — trans23 binds but never reads it). `datasort` is different: stock's `f0_datasort`
(`trans12_decl00.dats:2580`) emits **`D2Cdatasort(d1cl, s2ts)`** whose FIRST field is the
**whole L1 `D1Cdatasort(T_DATASORT(); [D1TSTnode(...S1TCNnode...)])` declaration tree** — and
that field is **NOT vestigial in the raw L2** (the L2-DIFF compares the raw `d2parsed` BEFORE
the post-passes; the stock side carries the full L1 body inline, so emitting `d1ecl_none0`
would show as a structural divergence — exactly the `enum`→`D1Cnone0()` finding the L2-DIFF
report already documented). Reaching FAITHFUL therefore requires synthesizing the L1
`D1Cdatasort`/`D1TSTnode`/`S1TCNnode`/`S1Tid0`/`S1Tlist` nodes (plus fabricated `token`s for
each con) — genuine L1 machinery the pyfront lowering does not have. The pyprint emitter
emits a single `# TODO(pp): unmapped d0ecl` for it today (the lone such marker in
`basics0.sats`); the surface + L1-building lowering is the follow-up. Suggested surface when
done: `@sort enum tree: case Leaf | case Node(Tree, Tree)` (reuses `p_enumdecl`'s case-suite).
