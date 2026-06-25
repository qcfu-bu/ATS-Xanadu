# ATS3 LSP — Contract artifacts (checker ↔ server)

Machine-checkable formalization of the **checker→server JSON bundle** defined in
`../docs/LSP-ARCHITECTURE-AND-PLAN.md` §4. Owned by the architect; both WS-1a (checker) and
WS-1b (server) build against it. Do not change the shape without updating §4 and bumping `schema`.

## Files
| File | Purpose |
|---|---|
| `bundle.schema.json` | JSON Schema (draft-07) for the bundle. The authoritative shape. |
| `validate-bundle.js` | Dependency-free validator. `node validate-bundle.js <bundle.json> [--expected <exp.json>]`. Exit 0 = OK. |
| `fixtures/sample-bad.dats` | Canonical broken file: a `type-mismatch` (line 0) + an `unbound-identifier` (line 1). |
| `fixtures/sample-bad.expected.json` | Expected bundle for it (after dedup). |
| `fixtures/sample-ok.dats` / `.expected.json` | Clean file → empty diagnostics. |
| `fake-checker.js` | Stand-in checker with the SAME CLI as the real one; lets WS-1b develop the server before WS-1a lands. |

## What is canonical vs advisory
- **Canonical (asserted by `--expected`):** per-diagnostic `code` + `severity` + `range`, as a
  multiset (order-independent). Schema validity of the whole bundle.
- **Advisory (NOT asserted):** `message` wording and `nerror` (the compiler's raw error count may
  exceed the number of deduped diagnostics). The real checker authors its own messages.

## Coordinates (the load-bearing detail)
0-based throughout; `line` = `nrow`, `character` = `ncol` (byte column, ASCII-correct in v1).
For `fixtures/sample-bad.dats` (`val x: int = "hello"` / `val y: int = nonexistent_var`):
- `"hello"` literal → line 0, characters **13–20** (half-open; includes both quotes).
- `nonexistent_var` → line 1, characters **13–28**.
See primer §5 for the "internal 0-based / printed 1-based" trap — the checker must use the
internal `postn` accessors, never the printed form.

## Typical use
```sh
# validate a bundle the real checker produced:
node validate-bundle.js /tmp/out.json --expected fixtures/sample-bad.expected.json
# the CLI contract every checker (real or fake) implements:
node fake-checker.js fixtures/sample-bad.dats --uri file:///x/sample-bad.dats --json-out /tmp/out.json
```
