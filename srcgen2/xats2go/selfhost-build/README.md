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

## What the build reports

The `go build` undefined-symbol list is exactly the boundary the 18 emitter
modules call but do not themselves define: the FRONTEND functions (`d2con_get_*`,
`i0exp_*`, the `stkmap`/`topmap` symbol tables, …) plus any not-yet-added runtime
leaves. Each frontend symbol is filled by emitting its frontend module the same
way (frontend modules emit UNHANDLED-free; accessors emit as `*XatsCon` field
reads — see the docs). Closing the boundary = emitting those frontend modules
into this package + supplying the irreducible runtime leaves.

Generated artifacts (`emit/`, `src/`) are gitignored; reproduce with `assemble.sh`.
