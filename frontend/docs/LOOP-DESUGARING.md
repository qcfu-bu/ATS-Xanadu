# Loop & mutation desugaring — the control-flow-aware elaborator (v2, single-shot)

> Companion to **PYTHON-FRONTEND-PLAN.md** and **LOWERING-MAP.md**. This specifies
> the complete elaboration of the imperative surface — `let`/`mut`, `while`/`for`,
> `break`/`continue`/`return`, and loop-`else` — into the functional core the rest
> of the frontend already lowers. It is designed **once, complete**: control flow
> is handled from day one, so there is no v1-without-break to rip out later.
>
> Code is illustrative core/pseudocode; the L2 targets are named at the end.

---

## 0. Why this is safe to do in one shot

The classic objection to "loops as tail recursion" — that Node/V8 don't do TCO, so
deep loops overflow — **does not apply here.** The ATS3→JS backend:

- detects self-tail-calls: `d2var_tailq(d2v, ical)` tests whether a call's target
  *is* the enclosing fixpoint variable (`xats2js/srcgen2/DATS/intrep1_utils0.dats:374‑477`);
- emits every function body inside `while(true){ … }`
  (`js1emit_decl00.dats:797,856`), so a tail self-call becomes *reassign-params-
  and-loop*, not a growing call.

So however much `flow` plumbing we add, as long as the generated `loop` function's
self-call stays in **tail position**, it compiles to a real `while` loop with O(1)
stack. That single invariant (**§6**) is what we must preserve; everything else is
free to be as expressive as Lean's `do`-elaborator.

---

## 1. Surface additions

| Surface | Meaning |
|---|---|
| `let x = e` | immutable binding (default) |
| `let mut x = e` | mutable binding (reassignable) |
| `x = e` where `x` is `let mut` | reassignment (in-scope `let mut` only; else a diagnostic) |
| `while cond: <suite>` | conditional loop |
| `for x in iter: <suite>` | iterate a collection/iterator (`x` fresh & immutable per iteration) |
| `break` / `continue` | exit / skip-to-next-iteration of the **innermost** loop |
| `return e` | return `e` from the **enclosing function** (through any number of loops) |
| `while/for … : <suite> else: <suite>` | the `else` runs iff the loop exited **without** `break` |

Reassigning an immutable binding, or `break`/`continue` outside a loop, or `return`
outside a function, are **elaboration errors** (reported on the surface span).

Explicit `let mut` is the linchpin: it makes the set of mutated names *syntactically
evident* (and distinguishes declaration from reassignment), which is what lets the
elaborator decide precisely what to thread. See SURFACE-GRAMMAR.md §1.

---

## 2. The functional core (PyCore) we target

The elaborator's output is **PyCore**, a loop/mut/control-free core:

> literals · `var` · application · `lambda` · **immutable** `let` · tuple · record ·
> field projection · `if` · `match`/`case` · `datatype` · **recursive `fun` groups** ·
> `staload`.

PyCore is exactly what `pylower` already maps to L2 (LOWERING-MAP §1/§4). The
desugarer **eliminates** `mut`, every loop, and every `break`/`continue`/`return`.
There is no special L2 machinery for loops — the loop becomes an ordinary local
recursive function, which the backend then loops (§0).

---

## 3. The control model: a `flow` result threaded through blocks

A suite (statement list) does not "return a value" in the expression sense; it
**transforms mutable state and may raise a control signal.** Model that with a
result type carried in a tiny frontend runtime prelude (`pyrt`):

```
datatype flow(a:t@ype, r:t@ype) =   // a = the accumulator tuple ; r = the fn's return type
  | flow_next   of a    // fell off the end of the suite — normal completion, new state a
  | flow_cont   of a    // `continue` — go to the innermost loop's next iteration
  | flow_break  of a    // `break`    — exit the innermost loop, new state a
  | flow_return of r    // `return e` — exit the enclosing function with r
```

**Sequencing within one loop level** is the `flow` monad's bind — only `flow_next`
continues; the three control signals short-circuit (propagate unchanged):

```
fun flow_bind(m: flow(a,r), k: a -> flow(a,r)): flow(a,r) =
  case m of
  | flow_next(a)   => k(a)        // continue the suite with updated state
  | flow_cont(a)   => flow_cont(a)
  | flow_break(a)  => flow_break(a)
  | flow_return(r) => flow_return(r)
```

**The one compositional rule that makes nesting work:** a *loop boundary* consumes
its own `flow_cont`/`flow_break` and reframes them as iteration/exit, but
`flow_return` **passes straight through** every loop boundary up to the function
epilogue. An inner loop's `break` never touches an outer loop. This is encoded in
the loop combinators (§5).

### 3.1 Two modes — pay for control flow only when you use it

For each suite the elaborator computes three syntactic flags (stopping at inner
**function/lambda** boundaries for `return`, and binding `break`/`continue` to the
innermost enclosing loop):

- `may_return`, `may_break`, `may_continue`.

If a suite is **control-pure** (all three false), it elaborates to the
*allocation-free fast path*: a straight chain of immutable `let`s ending in the
updated accumulator tuple — **no `flow` value is ever built**. Only suites that
actually contain control ops use the `flow` representation. So the overwhelmingly
common counting/accumulating loop emits exactly the v1 shape; `break`/`continue`/
`return` loops pay one `flow` allocation per iteration (removable later — §8).

---

## 4. Accumulator-set analysis

For a loop `L`, the **accumulator set** `A(L)` is:

> every `mut` variable that is **declared in a scope enclosing `L`** and is
> **reassigned somewhere in `L`'s body** (including inside nested `if`s and nested
> loops, but *not* inside an inner `lambda`/`def` — see §7.1).

- `mut` vars declared *inside* `L`'s body are iteration-local → **not** threaded
  (they re-initialize each turn — correct Python semantics).
- variables only *read* are **free** (captured by the generated `loop` closure) →
  not threaded.
- nested loops compose: an inner loop is a sub-statement whose reassignments count
  toward the outer loop's `A`.

Computed in one bottom-up pass that returns, per statement, the set of *assigned
mut names*; intersect with *muts in scope at the loop header*. `A(L)` becomes both
the `loop` function's parameter tuple **and** its result state. Order the tuple
deterministically (declaration order) for stable codegen.

---

## 5. Elaboration

Convention: **straight-line and conditional code thread state by SSA rebinding**
(a reassignment `x = e` becomes a shadowing `let x = e`, so later reads see the new
value); **explicit accumulator tuples appear only at loop boundaries**, where the
generated `loop` must take state as parameters. The two combinators below are the
*semantics*; the implementation **inlines** them per loop site (generate a fresh
monomorphic `loop` with the body spliced in) so the body is not an indirect
closure call and §6 holds.

### 5.1 Statements (within a suite; `kont` = "elaborate the rest")

| Statement | Elaboration |
|---|---|
| `let x = e` | `let x = elab(e) in kont()` |
| `let mut x = e` | `let x = elab(e) in kont()` (mutability is a *binding-class* fact for the analyzer; the core binding is an ordinary immutable `let`) |
| `x = e` (reassign) | `let x = elab(e) in kont()` — shadowing rebind; reads in `kont` see new `x` |
| expression `e` | `let _ = elab(e) in kont()` (sequence; L2 `D2Eseqn`) |
| `if c: T else: F` | `flow_bind( if c then elabSuite(T) else elabSuite(F), λa. rebind(a); kont() )` — branches are flow-typed; a branch that breaks/returns skips `kont` |
| `return e` | `flow_return(elab(e))` — `kont` discarded |
| `break` | `flow_break(curAccs)` — `kont` discarded |
| `continue` | `flow_cont(curAccs)` — `kont` discarded |
| `while`/`for …` | the loop combinator (§5.2/§5.3), then `flow_bind(loopResult, λa. rebind(a); kont())` |
| end of suite | `flow_next(curAccs)` |

In control-pure suites the same rules apply with `flow_next`/`flow_bind` erased to
plain `let`-threading and the final state returned directly (fast path).

### 5.2 `while` (with optional `else`)

```
// A = A(loop) ; a0 = (initial values of those accumulators)
let
  fun loop(a: A): flow(A, R) =
    if not(cond[a]) then flow_next(a)            // condition false ⇒ normal completion
    else
      case elabSuite(body)[a] of                 // body inlined; produces a flow over A
      | flow_next(a')   => loop(a')              // fell through  ⇒ iterate     (TAIL)
      | flow_cont(a')   => loop(a')              // continue      ⇒ iterate     (TAIL)
      | flow_break(a')  => flow_break(a')        // break         ⇒ exit (mark "broke")
      | flow_return(r)  => flow_return(r)        // return        ⇒ propagate out
in
  // consume the loop's own break; reframe to the OUTER context (only next/return remain)
  case loop(a0) of
  | flow_next(a)   => seq(rebind(a), elseClause_or_next(a))   // completed ⇒ run `else`
  | flow_break(a)  => seq(rebind(a), flow_next(a))            // broke     ⇒ skip `else`
  | flow_return(r) => flow_return(r)
end
```

- Without an `else` clause, the `flow_next` and `flow_break` arms collapse to the
  same `rebind(a); flow_next(a)` — and if the body is **control-pure**, the whole
  thing degrades to the fast-path loop (no `flow`, no `case`):

  ```
  let fun loop(a: A): A = if cond[a] then loop(body_state[a]) else a
  in let a = loop(a0) in <rest with rebind(a)> end end
  ```

### 5.3 `for x in iter`

`x` is a fresh immutable binding per iteration; the iterator comes from the `pyrt`
`ForIn`-style protocol (`iter_open`/`iter_step`, overloaded for lists, ranges, …):

```
let
  val it = iter_open(elab(iter))
  fun loop(a: A): flow(A, R) =
    case iter_step(it) of
    | iter_done()        => flow_next(a)
    | iter_more(x, it')  =>                     // x bound fresh; it' threaded (or it is stateful)
      case elabSuite(body)[a] of
      | flow_next(a')  => loop(a')              // TAIL
      | flow_cont(a')  => loop(a')              // TAIL
      | flow_break(a') => flow_break(a')
      | flow_return(r) => flow_return(r)
in
  case loop(a0) of … (same break/else/return reframing as §5.2) end
```

**Fast path:** a control-pure `for` with one accumulator and a known container
collapses to a prelude fold, e.g. `a = list_foldleft(xs, a0, lam(a, x) => body_state)`.

### 5.4 Function epilogue

A function body is a suite that may `return` but cannot `break`/`continue` (those
need an enclosing loop). So its flow is just `{flow_next, flow_return}`. The
function value is the returned `r`, or — if control falls off the end — the suite's
tail value (the last expression, or unit):

```
fun f(params) =
  case elabSuite(fnbody)[a0] of
  | flow_return(r) => r
  | flow_next(_)   => tailValue          // last-expression value, or ( )
```

A **control-pure** function body (no `return`) skips the `case` entirely and is just
its tail expression — i.e. ordinary PyCore, indistinguishable from a hand-written
functional definition.

---

## 6. The load-bearing invariant: keep the self-call in tail position

The backend loops a function iff its recursive self-call is a tail call
(`d2var_tailq`, §0). In §5.2/§5.3 the `loop(a')` arms are the tails of the `case`,
which is the tail of `loop` — ✓. The elaborator must **never** place the generated
`loop`'s self-call in a non-tail spot (e.g. inside a `flow_bind`'s continuation, or
as an argument). Two concrete rules:

1. The `case elabSuite(body) of … flow_cont/flow_next ⇒ loop(a')` arms are emitted
   verbatim as the `case`'s tail — do not wrap them.
2. The body is **inlined** (spliced) into `loop`, not called as a separate closure;
   the body's own (non-`loop`) calls may be non-tail, that's fine.

A lint in the desugarer should assert the generated `loop` is self-tail-recursive
before handing PyCore to `pylower`, so a regression is caught at build time, not as
a mysterious stack overflow at runtime.

---

## 7. Semantic decisions (documented divergences from Python)

### 7.1 Closures capture mutated vars **by value** (the SSA value at capture)

A `lambda`/`def` defined inside a loop captures the *current SSA value* of an
enclosing `mut`, not a live cell. So:

```python
let mut fs = []
for i in range(3):
    fs = fs + [lambda: i]      # each closure captures THIS iteration's i
```

binds three closures returning `0,1,2` — **not** Python's late-binding `2,2,2`.
This is the usual desired behavior (it avoids the classic loop-capture bug) and
falls out of the functional model for free. It is a deliberate divergence; document
it. (A program that truly needs a shared mutable cell across closures uses ATS
`var`/`ref` — the escape hatch, plan §LOWERING `var`.)

This is also why §4 stops the assigned-set scan at inner-function boundaries: a
reassignment performed *inside* an inner `def`/`lambda` is that inner function's
business, not the loop's accumulator.

### 7.2 `break`/`continue` bind to the innermost loop; `return` to the function

Enforced by the combinator structure (§3/§5): the nearest loop consumes
`flow_break`/`flow_cont`; `flow_return` passes through. Labeled break is out of
scope; if ever wanted, it is an additive `flow_break of (label, a)` extension that
does **not** disturb this design.

### 7.3 Loop-`else`

Runs exactly on the condition-false / iterator-exhausted exit, skipped on `break`
(§5.2). This is free given the `flow_next` vs `flow_break` distinction at the loop
boundary.

### 7.4 Definite-assignment / use-before-init

`mut x` must be assigned before use on every path (a simple flow check). Reading a
`mut` that some path leaves uninitialized is an elaboration error — cleaner than
ATS's uninitialized-`var` story and gives a precise diagnostic.

---

## 8. Representation cost & the optimization that is *not* debt

The `flow` representation allocates one constructor per iteration in
control-bearing loops. That is correct and simple, and the **surface + semantics
are settled now**. The allocation is removable *without any surface or elaboration-
contract change* by a later lowering of `flow` into **join points / CPS** (jump to a
break-target / continue-target / return-target local function instead of
constructing and matching a sum) — Lean's actual encoding. Because it changes only
how `flow` is *compiled*, not what programs mean, swapping it in later is an
optimization, not rework. The control-pure fast path (§3.1) already allocates
nothing, so the common case is optimal from day one.

---

## 9. L2 lowering notes

Everything below is already covered by LOWERING-MAP; nothing new is needed:

- generated `loop` group → recursive `D2Cfundclst` (LOWERING-MAP §4.F); bind the
  `loop` name **before** its body so the self-call resolves to the same `d2var`
  (which is what `d2var_tailq` keys on, §6).
- `flow`/`iter` datatypes + `flow_bind`/`iter_*`/`list_foldleft` live in the
  **`pyrt`** prelude module; desugared output `staload`s it; its constructors and
  functions resolve through the ordinary `tr12env` fall-through (plan §4).
- `flow_next(a)` etc. → `D2Edapp` of the resolved constructor `d2con`; the `case`
  → `D2Ecas0` with `d2cls` arms; accumulator tuples → `D2Etup0` / tuple pattern
  `D2Ptup0`; sequencing → `D2Eseqn`; `if` → `D2Eift0`.
- every generated node carries the **surface span** of the construct it came from,
  so a type error inside a desugared loop body reports on the user's `while`/`for`
  line, and the `pyrt` machinery stays invisible in diagnostics (plan §6.3). For
  nodes with no surface origin (e.g. the synthesized `loop` binder) use
  `loctn_dummy()` so they are never reported.

---

## 10. Worked examples

### 10.1 Control-pure `while` → fast path (no `flow`)

```python
let mut i = 0
let mut acc = 0
while i < n:
    acc = acc + i
    i = i + 1
print(acc)
```
`A = {i, acc}`, `n` free. Emits:
```
let fun loop(i, acc) = if i < n then loop(i+1, acc+i) else (i, acc)
in let val (i, acc) = loop(0, 0) in print(acc) end end
```
→ backend → `while(true)` with `i`,`acc` reassigned each turn. Zero allocation.

### 10.2 `while true` + `break`

```python
let mut total = 0
while true:
    let line = read_line()
    if line == "": break
    total = total + length(line)
return total
```
`may_break` ⇒ flow mode. Body produces `flow_break(total)` on empty line,
`flow_next(total')` otherwise; `loop`'s `flow_break` arm exits to `flow_next`; the
function epilogue turns the trailing `return total` into `flow_return`.

### 10.3 Nested loops + early `return` (return threads through both)

```python
def find(grid, target):
    let mut i = 0
    for row in grid:
        let mut j = 0
        for cell in row:
            if cell == target:
                return (i, j)     # flow_return — passes through BOTH loops
            j = j + 1
        i = i + 1
    return (-1, -1)
```
Inner loop `A = {j}`, outer loop `A = {i}` (`j` is inner-iteration-local). The
inner `case` maps `flow_return(r) => flow_return(r)`; the outer loop does the same;
the function epilogue matches `flow_return((i,j)) => (i,j)`. No loop label needed;
the structure delivers the right target.

### 10.4 `for … else` (search-success vs not-found)

```python
for x in xs:
    if pred(x): break
else:
    handle_not_found()
```
The `break` exit takes the `flow_break ⇒ flow_next, skip else` arm; exhausting `xs`
takes `flow_next ⇒ run else`. Exactly Python's loop-else.

---

## 11. Scope & sequencing

This elaborator is a **PyAST → PyCore** pass between parsing (M2) and lowering (M3).
Because it is complete (all of `let`/`mut`/`while`/`for`/`break`/`continue`/
`return`/`else` from the start), the milestone change to PYTHON-FRONTEND-PLAN is
small:

- **M2.5 — Elaborator + `pyrt`.** Implement §4 analysis, §5 rules, the §6 tail-
  position lint, and the `pyrt` prelude (`flow`, `flow_bind`, the iterator
  protocol, `list_foldleft`). Test in isolation with a PyCore pretty-printer
  *before* wiring lowering.
- Fold the surface additions (§1) into the plan's §7 table and the grammar doc.
- The differential oracle (plan §11) extends naturally: a desugared loop must
  produce the same result/JS as the hand-written tail-recursive ATS3 version.

The §8 join-point optimization is explicitly **post-v2** and non-breaking — record
it as a known future improvement, not a TODO that blocks correctness.

---

*Open items — RESOLVED 2026-06-20 (architect rulings after the M2.5 spike):*

(i) **Iterator protocol = THREADED / pure** (not stateful). `iter_step(it)` returns
`done | more(x, it')`; `it'` threads as part of the loop's accumulator state, so it stays
a tail-call argument (preserves §6) and the pass stays re-entrant (no `var`/`ref` cell).
v1 containers: **lists** (`it` = the list; step = cons/nil) and **`range`** (`it` =
current index). No stateful iterators in v1. *(The M2.5 elaborator currently emits the
stateful shape — switch to threaded; an M2.5 refinement, due before `for`-loops lower.)*

(ii) **2-parameter `flow(a,r)`: VERIFIED** — the M2.5 Step-0 spike typechecks + codegens
+ runs it. The combinators (`flow_bind`, loop dispatch) are **INLINED per loop site** as
an explicit `case`, so there is **no generic `flow_bind` function** to instantiate (the
stock backend crashes on generic-template instantiation). The parametric `flow` *datatype*
stays in `pyrt`, used at concrete types per site. User-level generics (`def f[A]`) are a
separate M5/M7 concern.

(iii) **Definite-assignment (use-before-init, §7.4): DEFERRED** to a post-M3 additive
pass. v1 ships target-validation only (a reassignment must target an in-scope `let mut`);
a `mut` read before init falls through to a downstream type error — the precise diagnostic
is polish.

(iv) **Guarded `match` arms: carry the guard in PyCore** (`PCArm` gains an optional
guard); do **not** desugar a guard to an inner `if`. A failed guard must fall through to
the **next** arm (ML/ATS semantics) — an inner-`if` cannot. M4 lowers a guarded arm to
ATS's native guarded clause (`d2cls` `D2GPTgua`), which has correct fall-through. *(M2.5
refinement, due before `match` lowering in M4.)*
</content>
