# Template resolution in xats2go: adopting the pristine copy-per-instantiation model

*Status: 2026-08-26 — for review by Hongwei. Suites cited at the bottom.*

## Summary

Following Hongwei's feedback on the `g_print$out` / `fprint_ref` report, we
removed **all** of the ad-hoc template-resolution machinery the Go backend had
accumulated in `trtmp3b`/`trtmp3c`, and verified that the pristine resolver —
unmodified in its dispatch semantics — handles the hook/override cases
correctly. The failures that motivated the ad-hoc machinery turned out to be
(a) caused by one of our own earlier changes, and (b) in one residual case, an
**emitter** defect, not a resolver one.

Hongwei's model, as stated:

> It is very similar to method dispatching in OOP. Say, `foo<...>` is used at
> some location X; this use instance is resolved with the closest
> implementation of `foo<...>`; the implementation's code gets copied to the
> location X; the templates contained in the implementation's code need to be
> resolved recursively. … No sharing. Each instantiation site makes its own
> copy.

This is exactly what the pristine passes implement:

- `trtmp3b` annotates **only non-template code**. A template impl
  (`dimpl_tempq`) is register-only; its body's inner template applications
  remain plain `D3Etapq` nodes — no candidate list is ever attached at the
  definition site.
- At an instantiation, `trtmp3c`'s `f0_all1` walks a per-site copy of the
  chosen impl body (with the match's `svts` frame pushed). Every inner
  `D3Etapq` reaches `f0_tapq` → `tr3cenv_t3apq_resolve` — a **fresh query in
  the instantiation scope**, where `where`-block hooks registered during the
  walk are found first (stack order = closest implementation).
- `tmqstk_insert_decl` substitutes a registered `where`-impl through the
  enclosing instantiation's `svts` at registration time, so nested hook
  bodies (`foritm$work` registered inside `gseq_foldl`'s copy) are concrete
  when they are later matched.

## What was removed (all of it ours)

1. **`f0_timp` instantiation-scope re-resolution** (`trtmp3c_dynexp`): the
   blanket re-query of `TIMPLall1` *and* `TIMPLallx` nodes during body walks.
   Hongwei correctly identified the framing behind it as a misunderstanding —
   under the pristine model there is no stale annotation to re-query, because
   template bodies never get definition-scope annotations in the first place.
2. **Concrete-instance in-place resolution** (`trtmp3b/3c_decl00`, the
   `tqas`-nil branch): resolving a registered instance body (e.g.
   `g_print<strn>`) at *registration* scope. **This was the actual root cause
   of the `g_stdout` bug**: it baked the global `g_print$out<>() = g_stdout<>()`
   default into the registered body as an already-processed `TIMPLallx`,
   which a later `fprint_ref` instantiation could no longer rebind. The
   re-resolution machinery (1) existed to undo this — incompletely.
3. **`zzprefer0` concrete-first candidate reordering** (`trtmp3c_utils0`):
   compensated for queries that matched both a generic default and a concrete
   instance; with per-copy fresh queries, scope order already picks the
   closest impl.
4. **`D3Cerrck` recursion arms** (`trtmp3b/3c_decl00`): upstream passes
   errck-wrapped decls through unprocessed; we restored that behavior (it
   only affects diagnostics on already-erroneous programs).

## What remains changed in srcgen2/DATS (minimal, orthogonal to dispatch)

1. **Walker completeness** (`trtmp3b/3c_dynexp`): faithful recurse+rebuild
   arms for `D3Elval`, `D3Eeval`, `D3Elabck`, `D3Et2pck` (+ `D3Exazgn`,
   `D3Exchng` in 3c). These node kinds postdate the walkers; the pristine
   catch-all rewrote them to `d3exp_none2`, erasing any template instance
   nested inside. No resolution-semantics change — just not dropping nodes.
2. **`svts` composition at push** (`trtmp3c_myenv0`, `tmqstk_pshsvts`): each
   frame stores its `svts` pre-composed with all deeper frames (one
   `list_append` per push); `tmqstk_getsvts` stays a head-frame read. This
   is what lets `tmqstk_insert_decl`'s registration-time substitution and
   `t3apq_resolve`'s query substitution see the whole enclosing chain in a
   nested instantiation (e.g. `d3pat_d2v$foldl` → `gseq_foldl` →
   `foritm$work` → `foldl$fopr`, where `r0` belongs to an outer frame). It
   also removed what profiling showed as the hottest entry of the trtmp3c
   pass (per-query stack recomposition).

## The residual failures were all the emitter — one defect, three sightings

With the pristine resolver, every remaining undefined runtime name in a full
self-hosting build traced to a single emitter defect: the legacy "worker
forwarding" layer (built long ago to paper over the then-broken resolver)
emitted the **raw registered body** of `where`-block hook impls as named
local closures. A registered hook body legitimately contains unresolved
inner templates — they resolve only inside instantiation copies — so the raw
emission referenced non-existent runtime names, in closures nothing calls
(the resolved instantiation copies sit right next to them, correct). Three
sightings of the same disease:

1. prelude `foritm$work` (gseq000) → `Xats_foldl_fopr`;
2. compiler-source `map$fopr0` / `foldl$fopr` / `forall$test` hooks →
   `Xats_char_code`, `Xats_sub_char_char`, `Xats_g_lte` (nine sites in 451k
   emitted lines);
3. **xatslib** `foritm$work` (githwxi `genv000.dats`, `gseq_foritm$e1nv`) →
   `Xats_foritm_e1nv_work` — proving a prelude-only exclusion is not enough;
   the guard must be "compiler package source only" (both `prelude/` and
   `xatslib/` are library code with raw hook bodies).

The fix was to stop emitting raw hook bodies altogether (the one surviving
worker family is compiler-source `foritm$work`, which the `strn_foritm`
typed-loop consumer reads); the forwarding layer is measurably dormant —
zero live forwarding sites in the entire assembly. Diagnostic method worth
recording: the resolver was exonerated by tracing, with temporary probes,
that every query in the failing chain fired and returned candidates — the
unresolved references existed only in dead raw-body emissions alongside the
correctly resolved copies.

This is the JS-vs-Go asymmetry from the original report, seen from the other
side: the JS backend tolerates an unresolved instance at runtime; the Go
backend turns it into a hard link error. The Go build acted as the oracle
that found both our resolver-layer mistake and this emitter residue.

## The GO arm of libcats (Hongwei's request)

`srcgen1/xatslib/libcats/DATS/CATS/GO/libcats.dats` now exists, mirroring the
JS/NODE arm: `#extern` leaves `XATS2GO_g_stdout`, `XATS2GO_g_stderr`,
`XATS2GO_{strn,bool,char}_fprint`, `XATS2GO_gint_fprint${sint,uint}`,
`XATS2GO_gflt_fprint${sflt,dflt}`, each bound with a concrete `<>` impl.
`srcgen2/HATS/xatsopt_dpre.hats` includes it under `#if defq(_XATS2GO_)`,
and the Go driver (`xats2go_goemit01.dats`) adds `--_XATS2GO_`. For now the
driver keeps `--_XATS2JS_` as well: the GO arm registers **after** the
JS/NODE arm and therefore wins for the leaves it defines, while the JS arm
still covers `basics0` (file I/O etc.) until GO analogs are constructed —
at which point `--_XATS2JS_` is dropped from the Go driver.

Verified end-to-end on Hongwei's exact case: the emitted instance of
`fprint_ref<strn>(out, x)` contains the hook as a closure returning the
**`out` parameter** — `g_print$out<>()` resolves to the `where`-override, not
the global `g_stdout` default — and the print reaches the caller's channel
through `XATS2GO_strn_fprint`.

## The template-instance cache (zztic)

With copy-per-instantiation semantics established, an optimization became
available that is invisible to the semantics: two instantiations of the same
impl at **equal type arguments**, whose bodies resolved against **no
instantiation-local (`where`-block) impls**, produce identical copies — so
one walked body can be shared. This is the classic monomorphization dedup
(as in C++/Rust), made hook-aware:

- `trtmp3c` memoizes completed instance walks, keyed by the chosen impl's
  stamp plus type-argument equality (`tmpequal_d3cl_t2js`). Each entry
  records the **transitive resolution trace** — every `d2cst` its body's
  resolution queried — and an entry is neither created nor reused while an
  *embedded* impl for any traced cst is in scope (embedded = a decl frame
  registered mid-instantiation, detected by an svts frame below it in the
  tmqstk). That condition is precisely what keeps the cache from
  reintroducing the `g_print$out` class of bug; the probe of
  `fprint_ref<strn>(g_stderr<>(), …)` confirms the hook still binds the
  `out` parameter, byte-identically. The cache clears on every top-level
  registration, since a new global impl can change a later query's winner.
- Every walked instance body is rebuilt with a **fresh `D3Cimplmnt0`
  stamp** — shared entries reuse one stamp, unshared walks each get their
  own — and that stamp flows unchanged through intrep0/intrep1. The Go
  emitter then memoizes by it within the visible lexical scope: the first
  occurrence emits the func literal, later occurrences emit an alias to the
  first binding. Equal stamps guarantee equal bodies, so the only possible
  failure mode of the emission memo is a loud undefined-identifier build
  error, never wrong behavior.

Measured on the print-walker bellwether (`dynexp0_print0`): 3,195
instantiations, 1,282 served from cache (40%), 2 correctly blocked by the
hook guard; emitted module size −19.3%; diagnostics byte-stable. Across the
full self-host assembly the emitted source dropped ~450k → ~396k lines
(−12% overall; the emitter's own package −21%; total emitted bytes 20.5MB →
18.4MB). With the cache + package split, the whole compiler builds at `-l`
in 5.0s with the largest package object at 72MB — 56x under the goobj
limit. Full-scale verification with the cache live: sweep 193/193
byte-equal (the cache is deterministic through self-hosting), gate 12/12 +
psuite 75/75, regress 5/5, census green.

## Verification (final scoreboard, 2026-08-26)

All tiers green with the complete change set:

- `psuite`: **75/75** programs byte-equal vs the JS backend.
- `typecheck-sample` (15 compiler-grade modules): **0 real errors**.
- Full self-host rebuild: all **194 modules** re-emitted, assembled
  (449,878 lines), compiled and linked — **zero undefined runtime names**.
- `sweep`: **193/193** modules — the self-hosted binary reproduces the
  bundle's emissions **byte-equal** (the self-hosting proof).
- `gate`: **12/12** goarm rungs (bundle golden + binary byte-equal),
  including the foritm rung, + psuite 75/75 through the binary.
- `regress`: **5/5** differential diagnostic probes — identical F3PERR
  counts and byte-identical stdout/stderr, binary vs bundle.
- leaf census: ratchet green at 108 pinned runtime leaves; the delta vs the
  previous pin is exactly the intended GO-arm channel leaves.
- Bonus: an accidentally-committed per-node debug trace in
  `trxd3i0_dynexp.dats` (one rendered line per `d3exp`, ~90% of per-module
  stdout) was found and disabled — per-module emit time dropped ~31%.

## Build note: Go linker object-size limit (self-host assembly)

Building the 450k-line single-package self-host assembly with INLINING
enabled on go1.26.4 produces a package object exceeding 5GB; the goobj
format uses 32-bit offsets, so `go build` dies with a linker panic
(`slice bounds out of range` in `goobj.(*Reader).StringRef`) that looks like
corruption but is an object-size overflow. Root cause isolated by
measurement: the INLINER flattening ~42k nested instantiation closures into
giant functions whose liveness/stack-map metadata explodes — `all=-N -l`
gives a 27MB binary, and decisively, **`all=-l` (inlining off, every other
optimization on) yields a 129MB object** (40x smaller), links in 8.5s, and
the resulting binary compiles a compiler module in 2.3s — at parity with
the historical fully-optimized binary (this workload is allocation-bound,
so inlining buys nothing). `-l` is therefore the standing build mode
(`iterate.sh do_build`, override via `XGCFLAGS`).

On top of that, the assembly is now SPLIT into Go packages at build time
(`split-src.py`): zzbase (layout structs + CATS/GO floor + base shims),
zzfe2 (lexing/parsing + the trans01/12 layer), zzfe3 (dynexp3 → xatsopt),
zzcc (the D3→intrep0 lowering + i0varfst shims), zzgo (the emitter), main
(driver + master modinit). 679 cross-package symbols get an exported `Z_`
prefix and packages dot-import their computed per-file dependencies, so
per-module emissions stay byte-identical (sweep re-verified 193/193 with
the split binary); the renamer is string-literal-aware because the
emitter's own source carries fragments of the Go it emits. Package order
mirrors the ATS staload DAG and a backward reference aborts the split —
which immediately caught the one genuine knot: `xglobal` sits early in the
build list but hosts the pvsload machinery that *invokes* the pass chain,
while the parsing layer reads its globals (`the_XATSHOME`), so the
lexing/parsing and trans layers form one package.

Division of labor between the two measures, by measurement: at default
optimization the largest split package still compiles to a 4.31GB object
(the inliner is the pathology, and the module graph's knot bounds how
finely the frontend can split), so `-l` is the load-bearing fix; the split
is defense-in-depth — at `-l` the largest package object is ~80MB, ~50x
under the goobj limit — and buys incremental per-package compilation
(full split build: 5.0s).
