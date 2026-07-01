# Rendering Machine Integration — Handoff

## Status

Two experiments validated and committed on branch `rendering-machine` (worktree at `swift-rendering-primitives-machine/`):

| Commit | What | Result |
|--------|------|--------|
| `07c1dde` | `Rendering.Indirect` — heap box for modifier content | Depth 100 passes on 544 KB cooperative pool (was crashing at 32) |
| `f3882d8` | `render-machine` experiment — iterative execution with checkpoint/rollback | 11/11 tests pass: iterative rendering, keep-with-next page break, cooperative pool |

## What's done

### 1. `Rendering.Indirect<Content>` (production-ready, committed)

`Sources/Rendering Primitives Core/Rendering.Indirect.swift` — a 4-line `final class` that heap-allocates content. Breaks quadratic type-size growth in nested modifier chains. Ready for L3 consumption.

### 2. Render machine experiment (validated, committed)

`Experiments/render-machine/Sources/main.swift` — self-contained proof of concept. Key patterns:

**Iterative rendering** (same as current drain loop):
- Views push work onto `_stack: [Work]`
- Machine loop pops and dispatches
- Composite views store VIEW on heap via Thunk (the "store VIEW not BODY" approach)

**Checkpoint/rollback** (NEW capability):
- `beginSpeculative()` saves an `Events.Snapshot` (event count + page position)
- `checkFit(minimumRequired:)` at next block entry checks remaining page space
- If insufficient: rollback to snapshot, page break, replay speculative events on new page
- If sufficient: continue normally, discard snapshot

## What's NOT done — the production integration

### Phase 1: Production machine types in Rendering Primitives Core

The experiment's `Machine` struct needs to be adapted to work with the real `Rendering.Context` (witness struct with 32 closures). Key design decision:

**Option A — Machine replaces Context drain loop**: The machine IS the new `render()` method on `Rendering.Context`. The existing `_stack`, `Thunk`, and `Work` are replaced by machine equivalents. The 32 closures stay — the machine calls them.

**Option B — Machine wraps Context**: The machine is a separate type that owns a `Rendering.Context` and drives it. Less invasive but adds indirection.

**Recommendation: Option A.** The machine IS the evolution of the drain loop. The `_stack: [Work]` becomes `_stack: [Machine.Work]` with the added `Frame` cases. The `Thunk` stays (it's the type-erased dispatch mechanism). The `render()` method gains checkpoint support.

### Concrete types to add:

```
Sources/Rendering Primitives Core/
  Rendering.Machine.swift          — namespace
  Rendering.Machine.Frame.swift    — continuation enum (closeScope, speculative)
  Rendering.Machine.Checkpoint.swift — protocol for context-specific snapshots
```

The `Rendering.Machine.Frame` enum (from the experiment):
```swift
enum Frame {
    case closeScope(Events.Event)           // push/pop bracket
    case speculative(snapshot: Snapshot)     // checkpoint for rollback
}
```

For production, `Snapshot` must be generic — PDF.HTML.Context and HTML.Context have different state to snapshot. Define a protocol:
```swift
protocol Checkpoint {
    // Context-specific snapshot creation/restore happens via closures
    // on Rendering.Context, not via protocol methods.
}
```

Actually, the cleanest approach: add `snapshot` and `restore` closures to `Rendering.Context` (like the existing 32 closures). The machine calls `context.snapshot()` to get an opaque value, and `context.restore(snapshot)` to rollback. The PDF.HTML.Context factory sets up these closures to save/restore PDF state.

### Phase 2: Apply Indirect to L3

In `swift-foundations/swift-html-rendering/`:

| File | Change |
|------|--------|
| `HTML.Styled.swift:20` | `public let content: Content` → `public let content: Rendering.Indirect<Content>` |
| `HTML.Styled.swift:84` | `Content._render(view.content, ...)` → `Content._render(view.content.value, ...)` |
| `HTML.Styled.swift:45` | `self.content = content` → `self.content = Rendering.Indirect(content)` |
| `HTML._Attributes.swift:21` | Same pattern: content → Indirect |
| `HTML._Attributes.swift:45` | `Content._render(view.content, ...)` → `Content._render(view.content.value, ...)` |
| `HTML.Element.swift` | **Revert** the `_Storage` class. Tag goes back to inline: `let tagName: String; let isBlock: Bool; let isVoid: Bool; let isPreElement: Bool; let content: Content?` |

### Phase 3: Wire checkpoint for page-break-avoid

In `swift-foundations/swift-pdf-html-rendering/`:

The existing infrastructure (diagnosed by another agent):
- `PDF.HTML.Context.Deferred` — stores a render closure + measured height
- `PDF.HTML.Context.Snapshot` — saves context state
- `captureBreakFlags()` — exists but never called
- `deferredKeepWithNextRender` — never assigned (always nil)
- `_popStyle` only handles `forcePageBreakAfter`, ignores `avoidPageBreakAfter`
- `_pushElement` has deferred-heading logic but it never executes (deferred is always nil)

With the machine's checkpoint/rollback, the approach changes:
1. When `avoidPageBreakAfter` is detected in `Styled._render` (via `apply(inlineStyle:)`), the machine saves a checkpoint
2. Heading content renders speculatively
3. At the next `_pushElement` (block element), machine calls `checkFit`
4. If insufficient space: rollback, page break, replay

The existing `PDF.HTML.Context.Snapshot` and deferred infrastructure may be reusable, but the machine's checkpoint mechanism is simpler (snapshot/restore via closures on Rendering.Context).

## Key files to read

| File | Why |
|------|-----|
| `Experiments/render-machine/Sources/main.swift` | **START HERE** — the validated machine design |
| `Experiments/body-getter-stack-overflow/Sources/main.swift` | Indirect validation |
| `Sources/Rendering Primitives Core/Rendering.Context.swift` | Current drain loop (lines 340-396), Work enum, Thunk |
| `Sources/Rendering Primitives Core/Rendering.View.swift` | Default _render (iterative, stores VIEW) |
| `Sources/Rendering Primitives Core/Rendering.Thunk.swift` | Type-erased dispatch (two inits) |
| `Sources/Rendering Primitives Core/Rendering.Work.swift` | Current Work enum (render + action) |
| `Research/cooperative-pool-stack-overflow.md` | Full problem analysis |
| `Research/owned-body-accessor-for-noncopyable.md` | "Store VIEW not BODY" decision |

## Key files in other packages

| File | Why |
|------|-----|
| `swift-html-rendering/Sources/HTML Renderable/HTML.Styled.swift` | Needs Indirect content |
| `swift-html-rendering/Sources/HTML Renderable/HTML._Attributes.swift` | Needs Indirect content |
| `swift-html-rendering/Sources/HTML Renderable/HTML.Element.swift` | Revert _Storage workaround |
| `swift-pdf-html-rendering/Sources/PDF HTML Rendering/Rendering.Context +PDF.HTML.swift` | Factory that creates Rendering.Context for PDF — needs snapshot/restore closures |
| `swift-pdf-html-rendering/Sources/PDF HTML Rendering/PDF.HTML.Context+Rendering.swift` | _pushStyle/_popStyle — where avoidPageBreakAfter needs to trigger checkpoint |
| `swift-parser-machine-primitives/Sources/Parser Machine Core Primitives/Parser.Machine.Run.swift` | Reference: the parser machine execution loop this is adapted from |

## Verification checklist

1. `swift test` in `swift-rendering-primitives-machine/` — 102 tests pass
2. `body-getter-stack-overflow` experiment — depth 100 on cooperative pool
3. `render-machine` experiment — 11 tests pass (including checkpoint/rollback)
4. `swift build` in `swift-html-rendering/` — after Indirect changes
5. `swift build` in `swift-pdf-html-rendering/` — after checkpoint wiring
6. `swift test --filter "renders Hakuna"` in `rule-besloten-vennootschap/` — passes
7. Manual PDF inspection: heading + next content on same page

## Non-negotiable constraints

From `cooperative-pool-stack-overflow.md` governing constraints:
- R1: Static dispatch (100%) — no vtable lookups, no existentials
- R2: No existentials — no `any View`, no `Any`
- R3: ~Copyable support — view protocol is ~Copyable
- R4: No @escaping at API boundary — user-facing body/builder unchanged
- R9: `borrowing Self` on `_render` — deliberate ownership choice
- R10: Preserve push/pop LIFO ordering — bracket operations must be correct
