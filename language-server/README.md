# ATS3 Language Server

An LSP server + VSCode client for **ATS3 (ATS-Xanadu)**.

**Status (2026-08-28): restarting from scratch on the Go backend.**  The
earlier JS-hosted and Chez-hosted servers are gone (purged — do not
revive).  The new server is written in ATS3 and compiled by the
**xats2go** Go backend (`srcgen2/xats2go/`) into a single native binary:
maximum ATS3, a minimal typed Go-extern floor (stdio bytes, clock,
process spawn), a single-threaded tail-recursive resident loop (the Go
backend has real TCO), and fresh-process-per-typecheck against the
one-shot compiler.

**Feature goals (priority order):** (1) type-error diagnostics → (2)
hover (type at cursor) → (3) go-to definition / type / implementation.

## Layout

- **`docs/`** — read first; still-valid compiler knowledge:
  - `ATS3-COMPILER-PRIMER.md` — the compiler pipeline, front-end API,
    diagnostics model, location indexing, type/symbol model.
  - `LSP-ARCHITECTURE-AND-PLAN.md`, `COMPLETION-PLAN.md`,
    `S2TYP-SURFACE-SYNTAX.md`, `COMPILER-RESET-API-PROPOSAL.md` —
    JS/Chez-era plans; the protocol/requirements analysis and the
    reset-API conclusion (in-process frontend reuse is unsafe; use a
    fresh process per check) carry over, the hosting story does not.
- **`client/`** — the TypeScript VSCode extension (working; will be
  pointed at the new server binary).
- **`fixtures/`** — real-file fixtures for latency measurement.
- **`go-server/`** — (to be created) the new ATS3 server: SATS/DATS
  modules, the CATS/GO extern floor, build script, and golden
  JSON-RPC-transcript tests.
