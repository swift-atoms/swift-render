# Stage A Execution Brief — Render Domain Split

<!--
---
version: 1.0.0
last_updated: 2026-07-24
status: RECOMMENDATION
tier: 1
---
-->

> **This is a dispatch brief, not research.** It prepares execution of the Stage A refactor
> decided in `swift-institute/Research/render-machine-dissolution.md` (v1.1.0, DECISION).
> **Nothing here has been executed** — no source file in any package has been modified, and
> no build has been run beyond the read-only `dump-package` manifest queries cited in R3a.
> Reconnaissance is read-only and dated 2026-07-24; re-verify anything load-bearing per
> [RES-013a] before acting on it.
>
> **Evidence labelling.** Claims below are marked as either *verified by SwiftPM*
> (`dump-package` — authoritative) or *text scan* (grep/find — indicative, and wrong at least
> once in this brief's own drafting; see R3a). Counts from a text scan are labelled as such
> and should be re-derived from the build system before being relied on.
>
> Predecessor brief, same package, same shape: `Research/rendering-machine-handoff.md`.

## Scope

Implement the agreed first refactor. **Do not** re-open the architecture. The decision is
made; this is execution.

### In scope

1. **Split rendering into clearer domains.** Generic composition (`Builder`, `_Tuple`,
   `Pair`, `Conditional`, `Group`, `Empty`) stays under `Render`. Document-specific concepts
   (`View`, `Context`, `Action`, `Push`, `Pop`, `Break`, `Semantic`, `Style`, `Speculative`)
   move under `Render.Document`.
2. **Separate backend from traversal engine.** `Render.Document.Context` becomes only the set
   of operations a backend implements. A new `Render.Document.Traversal` owns the work stack,
   drain loop, deferred closes, ordering, and cleanup.
3. **Preserve behaviour.** Rendering order, stack safety, `Pair` semantics, nested scopes, and
   exact-once destruction unchanged. `Work` and `Thunk` are moved and clarified, not replaced.
4. **Remove the obsolete abstraction.** Delete the empty `Render.Machine` namespace; replace
   its one frame case with an honest document-owned representation.
5. **Keep SVG independent.** SVG keeps its own `View` and `Context`, still reuses the shared
   builder and composition types.
6. **Fix Embedded blockers.** Replace the `Any` inline-style API; remove the dynamic
   `as? HTML.AnyView` path; replace the existential HTML element metatype; add a real Embedded
   build check.
7. **Verify before deleting.** Characterization tests first; build Render, HTML, PDF, SVG and
   downstream; remove code only after the replacement works and a clean build proves the old
   code dead.

### Explicitly out of scope — do not expand into these

| Excluded | Where it lives instead |
|---|---|
| The larger Machine redesign (`Machine.Node` decomposition, `Capture.Mode`, `Machine.Value`) | Tier 3 of the decomposition programme; separate dispatch |
| Checkpoint / savepoint abstraction (`Input.Protocol` re-home, `Render.Speculative` conformance) | Tier 1 investigation; separate dispatch |
| Erased owned-payload / ownership factoring (axis 9) | Tier 2 investigation; separate dispatch |
| Any `swift-effect-primitives` integration | Settled negative; never |
| Generic `Work` executor / render-neutral traversal target | Stage B, evidence-gated |
| `Render.Indirect` → `Ownership.Immutable` migration | Ownership census; separate dispatch |
| `Effect.Handler.Sync` correction | Separate dispatch (4 consumers) |

If execution surfaces a reason to touch any excluded item, **stop and escalate** rather than
widening scope.

---

## Reconnaissance

### R1 — File inventory and target assignment

`Sources/Render Primitive/` — 29 files, 1069 LoC. Proposed assignment:

| → Render Composition Primitives | LoC | → Render Document Primitives | LoC |
|---|---|---|---|
| `Render.swift` (namespace) | 10 | `Render.View.swift` | 50 |
| `Render.Builder.swift` | 47 | `Render.Context.swift` | 261 |
| `Render._Tuple.swift` | 51 | `Render.Work.swift` | 15 |
| `Render.Pair.swift` | 60 | `Render.Thunk.swift` | 46 |
| `Render.Conditional.swift` | 35 | `Render.Action.swift` | 17 |
| `Render.Group.swift` | 27 | `Render.Action.Push.swift` | 13 |
| `Render.Empty.swift` | 19 | `Render.Action.Pop.swift` | 13 |
| | | `Render.Action.Break.swift` | 8 |
| | | `Render.Push.swift` | 63 |
| | | `Render.Pop.swift` | 63 |
| | | `Render.Break.swift` | 33 |
| | | `Render.Style.swift` | 48 |
| | | `Render.Semantic{,.Block,.Inline,.List}.swift` | 32 |
| | | `Render.Speculative.swift` | 30 |
| | | *new* `Render.Document.Traversal.swift` | — |

**Deleted:** `Render.Machine.swift` (10), `Render.Machine.Frame.swift` (16).

**Unresolved, decide before moving:**

- `Render.Indirect.swift` (55) — excluded from both targets pending the ownership census.
  **Interim: leave it where it is.** Moving it twice is worse than moving it late. It has 4
  consumer references.
- `Array+Render.swift` (27), `Optional+Render.swift` (19) — these are `Render.View`
  *conformances* on stdlib types. The conformed-to protocol moves to the document target, so
  **the conformances move with it** ([MOD-004] constraint isolation). Same-package, so no
  `@retroactive` ([API-IMPL-018]).
- `Render.Empty` conforms `Render.View` inline (`Render.Empty.swift:3`) — it is listed under
  composition but carries a document-protocol conformance. **Split it:** the type stays in
  composition, the `Render.Document.View` conformance moves to the document target as
  `Render.Empty+Render.Document.View.swift` ([API-IMPL-007]). Same for `Render.Group`
  (`Render.Group.swift:26`), `Render._Tuple` (`:23`), `Render.Pair` (`:25`),
  `Render.Conditional` (`:19`).

**STRUCTURAL ACCEPTANCE CRITERION — principal decision, 2026-07-24.**

> The composition types remain in the composition target, but **all `Render.Document.View`
> conformances must live in the document target.** Treat that separation as a structural
> acceptance criterion.

The composition target must not depend on the document target. A build in which
`Render Composition Primitives` compiles with `Render Document Primitives` absent is the
mechanical proof; a split that leaves any conformance behind is not done, however green the
tests are.

### R2 — Consumer call-site census

**TEXT SCAN** (grep over `Sources/`, 2026-07-24) — indicative, not authoritative. 202
references to moving symbols across 5 packages. Re-derive from compiler diagnostics during
step 5 rather than trusting these counts; a text scan cannot see conditional compilation,
and it counts occurrences in comments (`swift-authentication`'s 2 hits are comments, already
excluded below).

| Package | Moving-symbol refs | Note |
|---|---|---|
| `swift-markdown-html-render` | 105 | largest; mostly `Render.Action` (action-recording pipeline) |
| `swift-html-render` | 46 | |
| `swift-pdf-html-render` | 33 | |
| `swift-pdf-render` | 16 | |
| `swift-authentication` | 2 | **comments only — not a real consumer** |
| `swift-svg-render` | **0** | uses `Builder` / `_Tuple` / `Conditional` only |
| `swift-render-async-primitives` | **0** | uses its own `Render.Async` + composition only |

Per-symbol: `Action` 94, `Context` 44, `View` 30, `Semantic` 14, `Style` 13, `Push` 4,
`Pop` 4, `Break` 4, `Speculative` 1. Non-moving: `Empty` 12, `Builder` 11, `_Tuple` 6,
`Conditional` 5, `Indirect` 4, `Group` 2.

**Consequence for scope item 5:** SVG and render-async are *unaffected by the rename*. Point 5
is nearly free — verify, don't engineer.

**Migration aid:** a `Render.Document` namespace plus deprecated typealiases at the old paths
would let consumers migrate incrementally. **Recommended against** — [API-NAME-004] forbids
unification typealiases, and 202 sites is a mechanical sweep, not a staged migration. Do it in
one pass per package, in dependency order.

### R3 — Characterization test coverage: **the critical gap**

**TEXT SCAN.** 134 `@Test` declarations across 8 files — **but only 105 of them are in a
compiled target; see R3a.** Existing coverage is good on ordering and composition:

| File | Tests | Covers |
|---|---|---|
| `Context Tests.swift` | 42 | every context operation, `interpret`, push/pop/break/style |
| `Composition Tests.swift` | 25 | `_Tuple`/`Conditional`/`Pair`/`Optional`/`Array`/`Group`/`Empty` ordering; **F-001 bracket-nesting regressions** (`Pair with bracketed child…`, `nested Pair with bracketed grandchildren preserves sibling structure`) |
| `Builder Tests.swift` | 18 | `buildBlock`/`buildOptional`/`buildEither`/`buildArray` |
| `Snapshot Tests.swift` | 16 | document-level output |
| `Performance Tests.swift` | 13 | 1000-element arrays, 10_000-iteration loops |
| `View Tests.swift` | 10 | leaf/composite/text |
| `NonCopyable Tests.swift` | 8 | `~Copyable` views |
| `Render.Indirect Tests.swift` | 2 | |

The last two rows are the **undeclared** suites (R3a) — 29 tests that have never compiled in
this package. Discount them from the safety net until step 0.5 wires them.

**Two of the five behaviours scope item 3 requires preserved have NO test coverage:**

1. **Exact-once destruction.** Grep across `Tests/` for `deinit` / `destroy` / `cleanup` /
   `leak` / `exactly.?once` returns **zero matches**. `Render.Context._cleanupStack()` — which
   destroys orphaned `.render` pointers — is untested. A refactor that moves `Work`/`Thunk`
   into `Traversal` could double-destroy or leak with every existing test still green.
2. **Arbitrary depth / stack safety.** The only "deep" test is
   `deeply nested Groups produce flat events`, which is a *composition* assertion, not a
   stack-depth one. Nothing exercises the 544 KB cooperative-pool bound that
   `cooperative-pool-stack-overflow.md` R7 exists for.

**NORMATIVE — principal decision, 2026-07-24.** Before any structural change, add
characterization tests **against the current source** for:

1. **exact-once destruction of deferred render payloads;**
2. **cleanup of orphaned work on abnormal traversal exit;**
3. **genuinely deep traversal, sufficient to exercise the cooperative-pool stack constraint;**
4. **existing `Pair` and deferred-close ordering.**

Item 4 has partial coverage already (`Composition Tests.swift` F-001 regressions, listed
above) — extend rather than duplicate. Items 1–3 have none.

Suggested shape:

- A deinit-counting view fixture that increments a shared counter on destruction; assert
  count == construction count after a normal render, after a render with bracketed scopes,
  and after an abnormal exit (item 2 — determine what "abnormal" is representable as, given
  the drain loop has no failure path today; a `fatalError`-free early return or an
  interrupted-mid-drain shape is the likely construction).
- A depth test at 1_000+ nesting levels and a width test at 10_000+ siblings, run on the
  cooperative thread pool (544 KB), asserting no crash — not merely asserting event order.

`Tests/Support/Render Primitives Test Support.swift` (201 LoC) is where the fixtures belong —
but see R3a first: the existing test *target* layout has a defect that affects where new
tests can safely live.

### R3a — Test-target masking: 29 of the 134 tests are in no target at all

**Verified by SwiftPM's own manifest parser** (`swift-build package dump-package`), not by a
text scan. `swift-render-primitives` declares exactly four targets:

```
regular  Render Primitive                 path=None
regular  Render Primitives                path=None
regular  Render Primitives Test Support   path=Tests/Support
test     Render Primitives Tests          path=Tests/Render Primitives Tests
```

`Tests/Testing/Render Primitives Performance Tests/` (13 `@Test`, 202 LoC) and
`Tests/Testing/Render Primitives Snapshot Tests/` (16 `@Test`, 285 LoC) are **in no declared
target**, and there is **no nested `Package.swift` under `Tests/`** (`find Tests -name
Package.swift` → empty). SwiftPM's default path resolution for a target named
`X` is `Tests/X`, not `Tests/Testing/X`, so even a name-matched default would not reach them.

**This corrects a claim made earlier in this brief's own drafting.** The characterization
baseline is **105 compiled tests, not 134**. The 29 uncompiled tests include the entire
snapshot suite — i.e. document-level output comparison, the thing most likely to catch an
ordering regression during the refactor — and the entire performance suite, which contains
the only 1000-element and 10_000-iteration exercises in the package.

**Consequences for Stage A:**

- The snapshot suite cannot be used as a refactor safety net until it is in a target. Wiring
  it is arguably step 0.5, before the new characterization tests.
- Do **not** add the new tests under `Tests/Testing/` — they would be invisible for the same
  reason. Put them in the declared `Tests/Render Primitives Tests/` target, with fixtures in
  `Tests/Support`.
- Whether the `Tests/Testing/` files still *compile* after however long they have been
  unbuilt is unknown. Expect drift; budget for it.

**Ecosystem scale — TEXT SCAN, method validated against SwiftPM on one package, not itself
authoritatively confirmed.** 19 packages across `swift-primitives` and `swift-foundations`
have a `Tests/Testing/` directory; **2** have a nested `Package.swift` (`swift-svg`,
`swift-tests`). Grep for `Tests/Testing` in the parent manifests of six sampled packages
(render-primitives, html-render, css-html-render, markdown-html-render, svg-render,
async-primitives) returns **0** in all six; positive control — the same grep pattern does find
the two genuinely declared `path: "Tests…"` entries in render-primitives. `dump-package`
independently confirmed `swift-html-render` (6 targets, 1 test target,
`Tests/HTML Rendering Core Tests`) and `swift-css-html-render` (3 targets, 1 test target)
— neither reaches its `Tests/Testing/` files, which number 38 and 14 respectively.

This is **out of scope for Stage A** beyond the two local consequences above, but it is an
ecosystem finding that belongs on the board: the [INST-TEST-*] nested-package pattern
(testing-institute skill) appears to be widely intended and narrowly applied. Whoever owns
that should confirm the count authoritatively per package rather than trusting this scan.

### R4 — Embedded blockers: precise surface, and a scope question that must be answered first

**The stated requirement is that the *HTML* rendering engine builds under Embedded.**
Measured against that target, the surface is much smaller than feared:

`swift-html-render` — **exactly two real blockers** (everything else the grep surfaced is
doc-comment prose or `fatalError("Body is Never…")` strings):

| Site | Construct | Assessment |
|---|---|---|
| `HTML.AnyView.swift:39` | `if let anyView = base as? HTML.AnyView` | **Mechanical.** The cast is an *idempotency* optimization (re-wrapping an `AnyView` returns it rather than double-boxing). Add a concrete overload `public init(_ base: HTML.AnyView) { self = base }`; Swift's overload resolution prefers the concrete over the generic `init<T: HTML.View>`. Preserves flattening, removes the cast. **Verify by test** that re-wrapping still doesn't double-box. |
| `HTML.Element.swift:48` | `-> (any WHATWG_HTML.Element.\`Protocol\`.Type)?` | **Mechanical.** The single caller (`HTML.Element.swift:222-226`) consumes **only two Bools**: `elementType.categories.contains(.phrasing)` and `elementType.content.model == .nothing`. Return a small concrete descriptor (or `(isBlock: Bool, isVoid: Bool)?`) instead of a metatype. The switch body stays; only the return type changes. |

`swift-html-render` has **zero** `Mirror` uses.

**The `Any` inline-style channel is the hard one, and its cost depends entirely on a scope
decision.** `Render.Context.swift:47/67/121` declares it; the flow is:

```
HTML.Styled.swift:77           context.apply(inlineStyle: property)      ← producer (html-render)
Render.Context.swift:121       public func apply(inlineStyle: Any) -> Bool  ← L1 channel
PDF.HTML.Context+Rendering.swift:235  apply(inlineStyle property: Any)   ← consumer (pdf-html-render)
  :250, :357, :382             Mirror(reflecting: property)             ← 3 Mirror sites
  :262+                        unwrapped is W3C_CSS_BoxModel.Width, …   ← dynamic is-casts
```

So the `Any` exists to let HTML's typed CSS property values reach PDF's context without
html-render depending on pdf-render. The consumer side is a **Mirror-based runtime dispatch
subsystem in `swift-pdf-html-render`** — an order of magnitude more work than the L1 signature.

**RESOLVED — principal decision, 2026-07-24. Option A.**

> The required Embedded surface for Stage A is **`swift-render-primitives`** (including the
> new composition/document target structure) **plus the ordinary `swift-html-render` path**.
> `swift-pdf-html-render` is **not** part of the Stage A Embedded guarantee. Its Mirror-based
> CSS dispatch is a separate follow-on dispatch and **must not** expand this refactor into a
> PDF-HTML/CSS redesign.
>
> However, **do not preserve the `(Any) -> Bool` inline-style channel in Render L1 merely for
> `swift-pdf-html-render`.** During implementation, trace that dependency and move the dynamic
> style-dispatch responsibility *upward* into `swift-pdf-html-render` or the appropriate
> integration layer. The Embedded-compatible Render/HTML path must not expose `Any`, `Mirror`,
> dynamic casts, or existential metadata.

Rationale of record: the requirement concerns the HTML rendering architecture;
`swift-pdf-html-render` is a separate HTML-to-PDF interpretation pipeline; pulling it in would
convert a decomposition refactor into a CSS dispatch redesign; and the exclusion is a scope
boundary, not a permanent exemption — it is recorded as a follow-on dispatch below.

**Consequence for implementation.** Removing `Any` from L1 is not a deletion — the hook has a
live non-Embedded consumer that must keep working. The order is: (1) trace every producer and
consumer of the channel (R4 flow diagram above); (2) determine whether the responsibility can
leave L1 entirely; (3) re-home it into `swift-pdf-html-render` or a CSS/PDF integration layer;
(4) only then remove the L1 operation. Preserving an Embedded-incompatible escape hatch in L1
for the benefit of a higher-layer consumer is the outcome to avoid ([ARCH-LAYER-014] — the
capability is mis-homed; re-home the capability, do not lift the constraint).

**Do not** replace `Any` with a raw-pointer channel. It would avoid the spelling while
recreating an open unsafe type channel, and would be chosen only because the compiler accepts
it.

**Embedded build check.** `Experiments/embedded-rendering-context/Package.swift:11` already
carries `.enableExperimentalFeature("Embedded")` and is the shape to reuse. The experiment
validated a representative slice; what is missing is a *continuously enforced* check over the
production path. Add it as a CI job or a build target compiling the actual document + HTML
path, so the property cannot silently regress again.

### R5 — Build and verification order

All builds through the coordinator. Verified present and executable:
`/Users/coen/Developer/swift-institute/Scripts/swift-build` (`package build|test|resolve`,
`workspace`, `impact`, `status`).

```bash
/Users/coen/Developer/swift-institute/Scripts/swift-build package test --package-path /Users/coen/Developer/swift-primitives/swift-render-primitives
```

Dependency order (verified from manifests):

1. `swift-render-primitives` (L1)
2. `swift-render-async-primitives`, `swift-html-render`, `swift-pdf-render`, `swift-svg-render`
   — all depend only on render-primitives; independent of each other
3. `swift-pdf-html-render` (needs html-render + pdf-render), `swift-markdown-html-render`
   (needs html-render)

No downstream consumers in `rule-law` / `rule-institute`. The only other hit is
`swift-institute/Experiments/member-import-visibility-body-conflict`, an experiment.

`swift-build impact` may identify the consumer set mechanically — worth running first rather
than trusting this list.

---

## Execution order

Each step gated on the previous. **Do not proceed past a red gate.**

| # | Step | Gate |
|---|---|---|
| 0 | Run `swift-build impact`; confirm the consumer set matches R2 | consumer list agreed |
| 0.5 | **Wire the undeclared test targets** (R3a) — get the snapshot suite into a target so it can serve as the refactor safety net; expect compile drift | snapshot + performance suites compile and run |
| 1 | **Write the four characterization tests** (R3) against the *current* code | new tests green on unmodified source |
| 2 | Commit the working pre-refactor state ([ARCH-LAYER-009] guard 1: git-recoverable) | clean commit |
| 3 | Embedded repairs: `HTML.AnyView` overload; `elementType` descriptor; trace and re-home the `Any` channel out of L1 per the R4 decision | html-render builds; Embedded check added and green; L1 free of `Any` |
| 4 | Target split: create the two targets + umbrella; move files per R1; split the conformances off the composition types | composition target compiles **with the document target absent** (structural acceptance criterion) |
| 5 | `Render.Document.*` rename; sweep consumers in dependency order (R5) | each package builds; 202 sites resolved |
| 6 | Extract `Render.Document.Traversal`; `Context` becomes witness-only | full test matrix green, incl. step-1 tests |
| 7 | Delete `Render.Machine` + `Render.Machine.Frame`; replace the frame case | clean build proves dead ([ARCH-LAYER-009] guard 2) |
| 8 | Full verification: build + test every package in R5 order; Embedded check | all green |

`Render.Thunk` is **not** removed at step 7 — it is moved and clarified. Arbitrary-depth
traversal still requires deferred ownership and typed dispatch. Only `Render.Machine` and
`Render.Machine.Frame` are proven dead by this refactor.

## Decisions of record (principal, 2026-07-24)

1. **Embedded surface scope** — RESOLVED, Option A. See R4. `swift-pdf-html-render` excluded;
   the `Any` channel is nonetheless removed from L1 by re-homing the responsibility upward.
2. **Characterization tests** — RESOLVED. Four items, normative, before any structural change.
   See R3.
3. **Conformance separation** — RESOLVED. Structural acceptance criterion. See R1.

## Open questions, non-blocking

4. **`Render.Indirect` interim placement** — recommend leaving in place pending the ownership
   census; moving it twice is worse than moving it late. Confirm at step 4.
5. **Naming of the work-item type and the deferred-close case.** `Render.Document.Traversal`
   is settled; `Render.Document.Work` is the natural pairing but the deferred-close case's new
   spelling (replacing `Render.Machine.Frame.closeScope`) is undecided. Decide at step 6, not
   before — the shape the traversal takes should inform it.
6. **Whether `swift-markdown-html-render`'s 105 sites** land in the same sweep or a follow-up.
   Recommend same sweep, separate commit per package.

## Follow-on dispatches created by this brief's scope boundaries

- **`swift-pdf-html-render` Embedded compatibility.** Excluded from the Stage A guarantee by
  decision 1. Its Mirror-based CSS dispatch (`PDF.HTML.Context+Rendering.swift:250, 357, 382`
  plus dynamic `is`-casts) is a separate architectural item. The exclusion is a scope
  boundary, not a permanent exemption.
- **Ecosystem test-target masking.** R3a: 19 packages with `Tests/Testing/` directories, 2
  with a nested `Package.swift`. Needs an authoritative per-package confirmation
  (`dump-package`, not grep) and then a remediation decision.
- **`Render.Indirect` → ownership census.** Unchanged from the research document.

## References

- `swift-institute/Research/render-machine-dissolution.md` (v1.1.0, DECISION) — the decision
  this executes; §Traversal contract is normative for step 6
- `Research/cooperative-pool-stack-overflow.md` — R1–R10 governing constraints
- `Research/unified-rendering-context-architecture.md` (v2.2.0, DECISION) — composition
  decoupling; Embedded validation E1–E8
- `Research/rendering-machine-handoff.md` — predecessor brief, same shape
- `Experiments/embedded-rendering-context/` — the Embedded check to generalize
