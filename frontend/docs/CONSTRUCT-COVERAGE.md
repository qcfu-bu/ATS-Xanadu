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
| `d0ecl` (declarations)      | 30 / 34 |  4 |
| `d0exp` (dyn expressions)   | 28 / 29 |  1 |
| `d0pat` (patterns)          | 12 / 13 |  1 |
| `s0exp` (static/type exprs) | 15 / 18 |  3 |
| `g0exp` (static/guard exprs)|  5 / 8  |  3 |

> **2026-06-23 — Cluster E (+1 d0ecl `D0Cdyninit`, +3 d0exp `D0Efix0`/`D0Etry0`/`D0Eexists`):**
> `initialize "PATH"` (= `#dyninit`), `fix f(a): R => e`, `try:`/`except:` (the ATS→py emit half), and
> the expr-position `exists {W}(S)` (= `$exists`) now round-trip FAITHFUL (zero structural L2-diff,
> EXACT + triage; `frontend/TEST/l2diff/misc/`). d0ecl 27→30, d0exp 25→28 (the s0exp work above
> separately closed a d0exp/d0pat emitter). `D0Cmacdef` is the only Cluster-E DEFERRAL (no live stock
> L2 — the deployed parser does not parse `#macdef`). The 4 remaining d0ecl gaps are `D0Cmacdef`
> (deferred), `D0Cdatasort` (deferred, needs L1), `D0Cdynxgen`/`D0Cextcode` (rare/corpus-absent).

> **2026-06-23 — s0exp +7 (`S0Euni0`/`S0Eexi0`/`S0Eop1`/`S0Eop2`/`S0Estr`/`S0Echr`/`S0Eflt`):**
> The universal `{..} T` (`forall[..]`) and existential `[..] T` (`exists[..]`) type quantifiers, the
> static infix operators (`+ - * < <= > >= == !=` — rendered `lhs OP rhs`, e.g. a `[i | i>=0]` guard
> or a `Vec[A, n+1]` size), and the static literals (string/char/float — the `$extype("name")` /
> `$extbox("name")` C-name string) now round-trip. FAITHFUL (zero structural L2-diff) for:
> `$extype`/`$extbox` -> `S2Etext`; `[..]`/`{..}` over an applied abstract type (the basics0-dominant
> shape, e.g. `[l:a0] p1box(l)`); and the static INFIX OPERATOR const (`S2Ecst(>=)` / `S2Ecst(+)` —
> the pyfront's index-binop now resolves the RAW operator alias the way stock's fixity does, not the
> `*_i0_i0` target). Fixtures: `frontend/TEST/l2diff/s0exp/{extype1,quant1}.sats`. This cleared **99**
> of the 100 `# TODO(pp): s0exp` markers in `srcgen1/prelude/basics0.sats` (only the deferred
> `datasort` `unmapped d0ecl` remains). Quantifier LOWERING already existed (`PyTquant` ->
> `s2exp_uni0`/`s2exp_exi0`); the body is now impr-wrapped (`S2Eimpr`) to mirror stock's
> `trans12_s1exp_impr` (skipped when the body sort <= `view`). Surface: `forall[N: SInt | g] T`,
> `exists[M: SInt | g] T`, `Extype["c_name"]`, `Extbox["c_name"]`. STILL DIVERGENT (pre-existing,
> orthogonal): an INDEXED `SInt[k]` body (`the_s2exp_sint1` vs stock `sint`, the M5a/P8 mitigation)
> and an index-VAR used as a type-arg (the pyfront's `S2Ecast(int0->type)` coercion) — both affect
> ALL dependent types, not the quantifier/operator nodes themselves.

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
| `S0Euni0`     | `{..}` univ. type | ~6 | ~20 | DONE (PP+PR+LO+T) — `forall[..]` |
| `S0Eexi0`     | `[..]` exist. type | (with above) | | DONE (PP+PR+LO+T) — `exists[..]` |
| `S0Eop1/2`    | static prefix/infix ops | ~30 | ~33 | DONE (PP+PR+LO) — `lhs OP rhs` (guards + `n+1`) |
| `S0Estr/chr/flt` | static string/char/float literal | * | ~21 | DONE — the `$extype("name")`/`$extbox("name")` C-name (-> `S2Etext`) |
| `S0Eop3`      | static `op(...)` special form | low | low | DEFER (rare; not in basics0) |
| `S0Elams`/`S0Efimp` | static lambda / fn-impl type | low | low | DEFER (rare; not in basics0) |

### Cluster B — fixity DSL — ✅ DONE
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Cfixity` | `infixl`/`infixr`/`infix0`/`prefix`/`postfix` | ~57 (2 sats,5 dats) | 45 | ✅ PP+PR+LO+T |
| `D0Cnonfix` | `nonfix` | ~18 | 0 | ✅ PP+PR+LO+T |

**Cluster B landed.** The ATS fixity keywords are KEPT VERBATIM in the pythonic surface (project-owner
LOCKED): `infixl`/`infixr`/`infix0`/`prefix`/`postfix`/`nonfix` — only the SHAPE flips (`#infixl + of
50` ↔ `infixl 50 +`: keyword PRECEDENCE NAME(s)). Lexer: 6 keyword tokens APPENDED LAST in `ptnode`
(tags 83–88; the CATS scanner's `PYL__KW` maps the lexemes to the SAME tags — XATSCAPP discards the
constructor NAME, the TAG is the pattern-match discriminant, so a mid-datatype insert would desync
every later operator). Lowering BUILDS the stock L0 d0ecl and wraps it `D2Cd1ecl(D1Cd0ecl(D0Cfixity/
D0Cnonfix(...)))` — the EXACT shape stock's `f0_fixity`/`f0_nonfix` emit (the fixity ENV is a stock
trans01 side-effect; our parser owns precedence via its own FIXED Pratt table).

**Pratt-table verdict: the FIXED table SUFFICES — no source-configurability needed.** The hardcoded
operator-precedence table (`pyparsing_dynexp.dats:107-130`, normalized levels 1–8) matches
`srcgen1/prelude/fixity0.sats`'s RELATIVE ordering for every operator the corpus uses in EXPRESSION
position: mul(`*`/`/`/`%`/`//` of 60) > add(`+`/`-` of 50) > compare(`< <= > >=` of 40) > equal(`= !=`
of 30) > and(`&&` of 21) > or(`||` of 20), with `**` of 61 right-assoc highest among arithmetic. The
non-standard ATS operators (`::`,`@`,`++`,`<<`,`>>`,`&`,`^`,`:=`) never appear as INFIX operators in
the pythonic-shaped corpus (they are Python idioms / method calls), so the table never misses one.
SURFACE-GRAMMAR §5.6 makes this the design: "The parser owns precedence (Pratt) — no ATS fixity." The
fixity decls are therefore a faithful pass-through of the DECL, not a re-configuration of the table.

**L2-diff FAITHFUL (0 triage diff vs stock):** `TEST/l2diff/fixity/fixity_decl.sats`
(`infixl`/`infixr`/`prefix`/`nonfix`) + `TEST/l2diff/fixity/fixity_more.sats` (`infix0` non-assoc,
multi-name `+ -` / `< <=`, postfix, alphanumeric `app`, prefix `! &`). `fixity0.sats` itself pyprints
all 33 fixity decls with **0 TODO(pp)** (including the relative-prec `prefix +(+1) +` / `infixl ||(+1)
&&` and operator-named `infixl || orelse` forms — the ATS→pythonic emit is faithful).

**Deferred (clean, non-corpus):** the pythonic→L2 RE-PARSE of the operator-RELATIVE precedence form
(`of OP(+N)` / `of OP`) reads the INT-precedence path only — it does not re-parse the `(+N)`/bare-OP
relative modifier (leaving a survivable poison node, never a crash). These forms appear ONLY in the
prelude `fixity0.sats` (`+(+1)`,`-(+1)`,`||(+1)`,`||`,`&&`); the gated corpus file `xglobal_ext000.dats`
has its fixity block STRINGIFIED (not live decls), so no gate exercises this. The stock parser ALSO
drops a `$`-prefixed fixity operand (`#prefix $raise of 0` → empty name list) — our emit matches stock
exactly there (faithful to the stock quirk).

### Cluster C — FFI / foreign binding
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Eextnam` | `$extnam(...)` | ~30 | **665** | PP+PR+LO+T — the dominant prelude construct |
| `D0Cextcode`| `%{ C %}` | 0 | 0 | defer (corpus-absent; error-clean if hit) |
| `D0Cdyninit`| `#dyninit` | ~95 | 0 | ✅ PP+PR+LO+T — `initialize "PATH"` (Cluster E) |

### Cluster D — records (boxed/flat/linear variants) — ✅ DONE
| construct | ATS syntax | srcgen2 | prelude | |
|---|---|---:|---:|---|
| `D0Ercd2` / `S0Ercd2` / `D0Prcd2` | `@{..}`/`${..}`/`~{..}` record value/type/pattern | ~10 | 1 | ✅ PP+PR+LO+T |

**Cluster D landed.** The box/flat/linear/ref kind is packed into the `T_TRCD20(n)` token int
(`lexing0.sats:172`); stock decodes it to a `trcdknd` at `staexp2.dats:1525` (`s2exp_r1cd`) /
`trans23_dynexp.dats:2230` (`f0_rcd2`). The pythonic surface round-trips the EXACT int via a prefix
**record-kind decorator** on the brace literal (a BIJECTION on the ints, reusing `@boxed`/`@linear`/
`@unboxed` + new `@vbox`/`@rec`/`@ref`; the bare `{..}` stays flat int 0, so the existing single
record form is byte-stable):
| surface | TRCD20 int | trcdknd | sigil it round-trips |
|---|---:|---|---|
| `{..}` (bare) | 0 | TRCDflt0 (flat) | `@{..}` |
| `@vbox {..}` | 1 | TRCDbox1 | `#{..}` |
| `@rec {..}` | 2 | TRCDbox0/1 | `$rec{..}` |
| `@boxed {..}` | 3 | TRCDbox0 | `$rectx{..}`/`$rec_t0` |
| `@linear {..}` | 4 | TRCDbox1 (vtbx) | `$recvx{..}`/`$rec_vt` |
| `@ref {..}` | 5 | TRCDbox2 | `$recrf{..}`/`$rec_rf` |

L2-diff FAITHFUL (0 triage diff vs stock): VALUE (`@{}`/`$rectx`/`$recvx`/`#{}`,
`TEST/l2diff/rcd/rcd_value.dats`) + TYPE flat/boxed (`TEST/l2diff/rcd/rcd_type.sats`). PATTERN
(`TEST/l2diff/rcd/rcd_pattern.pdats`) parses + lowers nerror=0 (flat int 0 + boxed int 3), producing
the exact stock `D2Prcd2(T_TRCD20(knd), -1, [D2LAB...])` shape — but stock's parser has **no
`T_TRCD20` pattern case** (`@{..}` patterns are unparseable in stock; `parsing_dynexp.dats:p1_d0pat_atm`
only has `T_TRCD10`), so there is no stock surface to diff against; faithfulness is proven by the node
shape matching `trans12_dynexp.dats:1525` (`f0_r1cd`). The `D2Prcd2` env-binding (`tr12env_add0_d2pat`'s
`D2Prcd2` arm) calls `tr12env_add0_l2d2plst`, which is DECLARED (`trans12.sats:610`) but NEVER DEFINED
in the deployed `lib2xatsopt.js` (dead code — never reached in stock); pylower works around it by
extracting the field sub-patterns and binding them with the working `tr12env_add0_d2patlst`.

**Deferred (clean, niche):** a LINEAR record TYPE inside a typedef RHS — `type X = $recvx{..}`. Stock's
`f0_sexpdef` wraps the vtbx-sorted `S2Etrcd(TRCDbox1)` in an `S2Ecast(...; vtbx; type)` coercion (via
`s2exp_stpize`, `trans12_decl00.dats:1439`) which the pyfront sexpdef lowering does not replicate; the
record STRUCTURE matches stock exactly, only the typedef-level cast wrapper is missing. No such linear
record-type aliases appear in the corpus (the value/pattern `$recvx` forms ARE faithful).

### Cluster E — macros + misc dyn exprs — ✅ DONE (4/5; `macdef` deferred)
> **2026-06-23 — DONE (4/5):** `D0Cdyninit`, `D0Efix0`, `D0Etry0`, `D0Eexists` now round-trip
> FAITHFUL (zero structural L2-diff, EXACT + triage; fixtures in `frontend/TEST/l2diff/misc/`).
> `D0Cmacdef` is DEFERRED (no live stock L2 — the deployed parser does not parse `#macdef`).
>
| construct | ATS syntax | pythonic surface | stock L2 | |
|---|---|---|---|---|
| `D0Cdyninit`| `#dyninit "PATH"` | `initialize "PATH"` | `D2Cdyninit(T_SRP_DYNINIT(); G1Estr("PATH";len))` | ✅ PP+PR+LO+T |
| `D0Efix0`   | `fix f(a): R => e` | `fix f(a): R => e` | `D2Efix0(T_FIX(0); fid; F2ARGdapp(-1;..); s2res; F1UNARRWdflt(); body)` | ✅ PP+PR+LO+T |
| `D0Etry0`   | `try E with \| p => h` | `try:`/`except p:` | `D2Etry0(T_TRY(); body; [D2CLScls(..)])` | ✅ PP+PR+LO+T |
| `D0Eexists` | `$exists{W}(S)` | `exists {W} (S)` | `D2Enone1(D1Eexists(T_DLR_EXISTS(); [D1Esarg([S1Eint(W)])]; D1El1st([D1Eint(S)])))` | ✅ PP+PR+LO+T (int-literal form) |
| `D0Cmacdef` | `#macdef NAME = body` | (`macro NAME = ..`) | — (errck poison; unparsed) | DEFERRED (needs L1) |
| `D0Cdynxgen`/`D0CSTDCL` | (rare/internal) | — | — | defer (corpus-absent) |

**Cluster E landed (4/5).** Two new lexer keywords APPENDED LAST in `ptnode` (tags 89/90; CATS
`PYL__KW` maps them): `initialize` (→ `D2Cdyninit`, mirrors `#include`'s parse/elab/lower) and `fix`
(→ `D2Efix0`, mirrors the lambda path plus a self-name `d2var` bound first for recursion, `npf=-1`,
and the optional `: R` result type). The expression-position `exists {W}(S)` REUSES the existing
`PT_KW_EXISTS` token, disambiguated from the TYPE-level `exists[..]` quantifier (`PyTquant`) by
POSITION — only an EXPR-position `exists` reaches the new `p_exists_expr`. The `try` half was
EMITTER-only: py→L2 (`PyEtry` → `PCEtry` → `D2Etry0`) already round-tripped, so only the ATS→py
pyprint (`D0Etry0` → `try:`/`except:`) was added.

**`D0Eexists` is a stock POISON node** — the deployed `trans12_dynexp` never lowers `$exists` (the
`_(*otherwise*) => d2exp_none1` fallthrough), so the stock L2 is `D2Enone1(D1Eexists(..))`, a raw L1
node wrapped in the "not-lowered" wrapper. The pyfront builds the EXACT L1 tree (`D1Esarg`/`S1Eint`/
`D1El1st`/`D1Eint`) and wraps it `d2exp_none1` — faithful for the int-literal corpus form
(`$exists{1}(1)`, test10). A GENERAL (non-literal) witness/scope would need s0exp→s1exp + d0exp→d1exp
L1 lowering the pyfront lacks (it goes straight to L2) — out of scope, and never used in the corpus.

**`D0Cmacdef` is DEFERRED (clean, non-corpus).** The DEPLOYED stock parser
(`parsing_decl00.dats` + the `tread01` reader the `trans02_from_fpath` pipeline uses) has NO `#macdef`
case — `D0Cmacdef` is constructed only in the alternate `pread00_decl00.dats` reader, NOT wired into
the deployed compiler. So `#macdef NAME = body` does not parse in deployed ATS3: it produces a chain
of `D0Ctkerr`/`D0Ctkskp` poison nodes (8 errors for `#macdef m1 = 1`), so there is no faithful stock
L2 to round-trip against. Even on the pread00 path, macdef lowers to `D2Cd1ecl(D1Cmacdef(.., dedf))`
where `dedf` is a `D1Cexp` — an L1 MACRO TREE (`trans01_d0exp` of the body) that the pyfront's
L0→L2-direct lowering cannot build (the SAME L1-machinery gap that defers `datasort`). See
`frontend/TEST/l2diff/misc/macdef1.dats` for the deferral marker.

\* `$extnam`/`#stacst` exact counts noisy under grep; treat as "present, needs support".

## Covered constructs (for completeness)
- `d0ecl` covered (PP present): `D0Cabsimpl D0Cabstype D0Cdatatype D0Cdefine
  D0Cdynconst D0Cexcptcon D0Cextern D0Cfixity D0Cfundclst D0Cimplmnt0 D0Cinclude
  D0Clocal0 D0Cnonfix D0Csexpdef D0Cstaload D0Cstatic D0Csymload D0Cvaldclst
  D0Cvardclst` — plus the in-flight **named-staload alias** (`#staload SYM = …` →
  `import "…" as SYM`).
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
3. ~~**Cluster B — fixity DSL**~~ ✅ DONE — `fixity0.sats` round-trips (33 decls, 0 TODO(pp)); the
   FIXED Pratt table suffices for the corpus (no source-configurability built — verdict above).
4. **Cluster D — record variants** — boxed/flat/linear `@{}`/`${}`/`~{}`.
5. ~~**Cluster E — macros + misc**~~ ✅ DONE (4/5) — `initialize` (`#dyninit`), `fix` (`D0Efix0`),
   `try`-emit (`D0Etry0`), `exists` (`$exists`, int-literal form) all FAITHFUL; `macdef` DEFERRED
   (deployed parser does not parse `#macdef` — no live stock L2; needs an L1 macro tree).

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
