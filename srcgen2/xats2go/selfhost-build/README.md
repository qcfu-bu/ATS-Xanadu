# selfhost-build — multi-module Go assembly of the emitter

Toward full self-hosting (see `../docs/01-cats-go-prelude.md`): emit every
emitter module to Go and assemble them into ONE Go package, then drive
`go build` to map the remaining emitter→frontend boundary.

## Run

```
bash assemble.sh                 # emit the 18 srcgen2/DATS emitter modules,
                                 # strip per-module package/import/main,
                                 # concatenate -> src/emitter_all.go (+ go.mod)
cd src && go build ./...         # undefined symbols = the frontend ABI surface
```

## Why this assembles cleanly

- **Cross-module linkage**: every function is stamp-mangled (`byref_add_2781`),
  and the stamp is the d2cst/d2var stamp from the shared SATS — so a call in one
  module and the definition in another get the SAME name. Verified: `byref_add_2781`
  is identical in `go1emit_byref0` (def) and `go1emit_styp0`/`go1emit_dynexp` (callers).
- **No duplicate definitions**: stamp-mangling makes every package-level func name
  unique across the 18 modules (verified: 0 collisions), so they concatenate into
  one package without redefinition errors.

## What the build has surfaced (in order)

1. **Package-level globals (FIXED).** Compiling even a single module failed first
   on `undefined: goxtnm16` — a module-private `a0ref` side-table global
   (`local val the_X_ref = a0ref_make_1val(...)`) was never emitted (the
   `I1Dlocal0` was skipped), while the package functions that read it were
   hoisted. Fixed by emitting module-level globals as package-level `var` +
   `func init()` (PASS-1.5 / PASS-2-main; see the docs). Regression-clean: 12
   byte-equal rungs + 75 JS-suite.

2. **The type-boundary tail (CURRENT frontier).** With globals defined, the next
   errors are all one class — an `any` value meeting a CONCRETE context needs a
   `.(T)` assertion the dynamic source omits but static Go requires:
   - `return <a0ref_get result>` where the func returns a concrete `bool`/...;
   - `Xats_as_con(x).Args[0].F0` — a tuple projection off a datacon field (`any`);
   - `nient_memq(any, ...)` wanting `*XatsCon`; `x = any` wanting `string`.
   These pervade the emitter's NON-go-arm self-emission (far more boundaries than
   the simple oracle programs). Closing them needs a systematic emitted-type
   tracking + boundary-coercion pass (thread the return/param/field type; record
   `any`-returning results), done per-class with rung/suite verification.

3. **Frontend symbols + runtime leaves.** Beyond byref0, the cross-module
   undefined list is the FRONTEND functions (`d2con_get_*`, `i0exp_*`, the
   `stkmap`/`topmap` symbol tables) — filled by emitting their frontend modules
   into this package (they emit UNHANDLED-free; accessors emit as `*XatsCon`
   field reads) — plus a few runtime leaves (`Xats_stamp_cmp` added; FILR model
   + `castlin10` pending).

Generated artifacts (`emit/`, `src/`, `probe/`) are gitignored; reproduce with
`assemble.sh`.
