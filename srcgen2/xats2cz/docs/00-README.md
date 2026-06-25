# xats2cz — survey & design foundation (3rd backend attempt)

`xats2cz` is the **third** attempt at a new ATS3 backend (after `xats2go` and
`xats2chez`). The first two foundered on an incomplete grasp of the ATS3
bootstrap pipeline and template resolution. This directory's docs exist so that
does not happen again: every claim here was **verified by re-running the
bootstrap from scratch and inspecting/executing real emitted code on 2026-06-25**,
not recalled.

## The premise (architecture for this attempt)
Reuse the `xats2js` frontend and `d3parsed → intrep0` stage (`trxd3i0`) verbatim,
then **emit Chez Scheme directly from intrep0** via a single new emitter `cz0emit`.
**DECISION (2026-06-25): there is no chez `intrep1` and no ANF/`trxi0i1cz` stage** —
intrep0 is already expression-shaped, type-erased, and carries the stamped,
body-bearing template instances, so the xats2js `intrep1` (which exists only to
ANF-flatten for an imperative target) is pure overhead on Chez. The goal is a
self-hosting ATS3 compiler running on Chez. No ad-hoc hacks/shims — the template
emission follows the verified `xats2js` rule (inline nested closures), see `03`.

## The documents
1. **`01-bootstrap.md`** — how `xats2js` bootstraps from the prebuilt JS seed: the
   bootstrapping equations, the two seeds, per-file separate-compile → namespace →
   concat, the frontend (`lib2xatsopt`) / backend (`lib2xats2js`) split, driver
   assembly, the verified from-scratch reproduction, and the Makefile map.
2. **`02-dependencies.md`** — the scattered dependency inventory: the HATS include
   chain, the prelude/xatslib compile-time source trees, and the runtime JS that
   `xats2cz` must re-provide in Scheme (the `XATS000_*` primitive floor).
3. **`03-ir-and-templates.md`** — intrep0 (expr IR) vs intrep1 (ANF IR), what
   `trxi0i1` does, and **how template instances are emitted to JS** — the crux:
   each instance is inlined as a *nested local closure* at its use site (no
   hoisting/lifting/monomorphization), which is what makes lexically-scoped
   template swapping and higher-order continuation hooks "just work". Includes a
   verified worked example and the direct mapping to Scheme.
4. **`04-template-resolution.md`** — THE root-cause doc for "failed to resolve
   symbol" (the bug that killed both prior attempts). The full resolution lifecycle
   (`D3Etapq`→`trtmp3b/3c`→`D3Etimp`→`I0Etimp`→inline), the three kinds of constant
   reference and how each must be emitted (the `d2cst_tempq` / `the_d2cstmap`
   discipline), the `pvsl00d`/`01d` prelude-store mechanism, the **empirically
   reproduced** failure chain (unresolved instance → `D3Eerrck` → `I1Dnone1` →
   dropped function → dangling caller), and the durable three-pillar fix (correct
   driver config + build fails loud on errcks + structural emitter discipline) — no
   hoist/lift/seed, no re-implementing dropped instances.

## The one-paragraph summary
A frozen JS seed (`xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js`) compiles each
ATS3 source file independently to JS; per-file `sed` namespacing
(`jsxtnm→jsx<NNN>tnm`, then `js1/js2/js3` at link) keeps the ~250 concatenated
files collision-free. The frontend lexes→parses→typechecks→**resolves templates**
to `d3parsed`; the backend lowers `d3parsed → intrep0(expr) → intrep1(ANF) → JS`.
Templates are already monomorphized by the frontend and stamped with a unique,
lexically-scoped id; the backend merely **emits each instance inline as a nested
closure** at its use site. For Chez this is even simpler than for JS (expression
language, native closures + TCO), so the chez backend = the same architecture with
intrep1 made expression-shaped and `js1emit` replaced by a Scheme emitter.

## Status / next
- DONE & verified: bootstrap survey, full from-scratch bootstrap, intrep0/intrep1
  + template-emission study, these docs.
- NOT yet started: the `cz0emit` intrep0→Scheme emitter, the Chez runtime floor
  (the `XATS000_*`/prelude primitives in Scheme), and the Makefile-based build
  harness (separate compilation + caching, position-based namespacing — see
  `01-bootstrap.md` §8). No `intrep1cz`/`trxi0i1cz` (see DECISION above).
