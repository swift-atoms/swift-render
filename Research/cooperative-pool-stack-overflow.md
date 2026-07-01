# Cooperative Pool Stack Overflow During Static-Dispatch Rendering

<!--
---
version: 6.0.0
last_updated: 2026-03-18
status: IN_PROGRESS
tier: 2
---
-->

## Context

Complex `HTML.View` trees crash with SIGBUS (signal 10) when rendered on Swift's cooperative thread pool. The crash occurs at runtime during the static dispatch `_render` chain — **not** the dynamic Mirror-based dispatch path documented in `swift-pdf-html-rendering/Research/iterative-tuple-rendering.md` (which addresses `buildPartialBlock` binary nesting).

**Trigger**: `swift test --filter "renders Hakuna"` in `rule-besloten-vennootschap` — renders a Dutch aandeelhoudersregister (shareholder register) PDF with multiple `Certificaathouder` / `Aandeelhouder` templates.

**Relationship to prior research**: The `iterative-tuple-rendering.md` document covers a _different_ overflow caused by O(N) `_Tuple` nesting from `buildPartialBlock(accumulated:next:)` in the dynamic dispatch path. The present issue affects the _static_ dispatch path with flat variadic `buildBlock` (O(1) `_Tuple` nesting). The two are orthogonal.

### Crash Report Analysis

From `/Users/coen/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-03-17-153906.ips`:

| Field | Value |
|-------|-------|
| Exception | `EXC_BAD_ACCESS` / `KERN_PROTECTION_FAILURE` |
| Signal | SIGBUS (10) |
| Faulting address | `0x16f313ff8` — in STACK GUARD page |
| Thread | `com.apple.root.default-qos.cooperative` (thread 5) |
| Thread stack size | **544 KB** (`0x16f314000–0x16f39c000`) |
| Stack consumed | ~544 KB (SP hit guard page at bottom) |
| Top frame | `___chkstk_darwin` → `Rendering._Tuple.init(_:)` |

### Call Chain at Crash

```
___chkstk_darwin                              ← stack probe failed
Rendering._Tuple.init(_:)                     ← allocating tuple content
Rendering.Builder.buildBlock<each A>(_:)      ← builder creating flat _Tuple
  [Certificaathouder.persoonsgegevens.getter]  ← @HTML.Builder computed property
TableBody.callAsFunction<A>(_:)
WHATWG_HTML.Element.Tag<A>.init(for:content:)
Table.callAsFunction<A>(_:)
  [Certificaathouder.persoonsgegevens.getter]
Certificaathouder.body.getter                 ← body constructs view tree
Section.callAsFunction<A>(_:)
WHATWG_HTML.Element.Tag<A>.init(for:content:)
  [Certificaathouder.body.getter]
Rendering.View._render(_:context:)            ← default _render → body → _render
  [protocol witness for Certificaathouder]
_Tuple._render → render#1                    ← pack iteration
_Tuple._render                               ← iterating Document children
Rendering.View._render(_:context:)            ← Document._render
  [protocol witness for Document]
ISO_32000.HTML.pages(configuration:html:)     ← L3 rendering entry point
ISO_32000.Document.init(...)
Aandeelhoudersregister.pdf(gegevens:)
  [test: "renders Hakuna register to PDF"]
```

### Root Cause

The crash is **depth-induced**: cumulative stack usage from recursive `_render → body → _render` chains exceeds the cooperative pool's ~522 KB budget. The crash report's top frame (`_Tuple.init`) is the point where accumulated usage tips over the limit, not the sole cause.

Contributing factors:

1. **Rendering chain depth**: Each composite view adds an `_render → body.getter → [modifier._render × N] → container._render` cycle. With 6 CSS modifiers per level, that's 9 frames per nesting level. Each frame carries generic metadata, value witness tables, and the materialized body value.

2. **Per-frame cost in production**: PDF.HTML.Context operations (`_pushElement`, `_popElement`, `applyTagStyle`) are 100+ line functions with large local state — averaging ~11 KB per frame in debug builds. Even ~20 levels of view nesting produces ~50 frames × ~11 KB ≈ 550 KB.

3. **Per-frame cost in isolation**: Without context operations, each level costs ~2.8 KB. The mechanism is identical but overflow requires ~180 levels instead of ~20.

4. **Width as amplifier**: `_Tuple.init(_:)` allocates `(repeat each Content)` on a single frame. When children are large generic types (kilobytes each), this adds a significant final allocation that pushes already-near-limit usage over the edge. Width alone does not cause the overflow — it is the rendering chain depth that consumes the budget.

5. **Cooperative pool stack**: Only **544 KB** total (~522 KB available). Main thread (8 MB) handles the same view trees without issue.

### Key Measurements (Production)

| Metric | Value |
|--------|-------|
| Cooperative pool thread stack | 544 KB |
| Default `pthread_create` stack (macOS, `NULL` attrs) | **512 KB** |
| Main thread stack | 8,176 KB |
| Approximate frames to crash | ~50 |
| Average frame size (debug) | ~11 KB |

### Isolated Reproduction

**Experiment**: `swift-rendering-primitives/Experiments/cooperative-pool-stack-overflow/`

Self-contained reproduction (no package dependencies) confirming the root cause. Mirrors the rendering infrastructure: `View` protocol with `_render → body → _render` recursion, `_Tuple` via variadic `buildBlock`, `Tag` (simulated HTML element), and `Styled` (simulated CSS modifier wrapper with ~96-byte `CSSProp`).

200 concrete nesting levels (N001–N200), each wrapping the previous in `Tag + 6× Styled`. At the leaf, a `WideLeaf` with 10 cells × 6 CSS modifiers each.

**Measured per-level stack cost**: ~2,656 bytes across 9 frames per level:

| Frame | Role |
|-------|------|
| `NNNN._render` | Default `View._render` — calls `body` |
| `NNNN.body.getter` | Materializes `Styled<Styled<Styled<Styled<Styled<Styled<Tag<NNNN-1>>>>>>>` |
| `Styled._render` × 6 | Each unwraps one CSS modifier layer |
| `Tag._render` | Unwraps the element container |

**Measured cooperative pool budget**: ~522 KB available at `Task.detached` entry (534 KB total minus runtime overhead).

| Depth | Stack used | Remaining | Result |
|-------|-----------|-----------|--------|
| 100 | 272 KB | 250 KB | OK |
| 150 | 401 KB | 120 KB | OK |
| 180 | >522 KB | — | **SIGBUS** |
| 200 | 531 KB | — | SIGBUS |
| 200 (main thread, 8 MB) | 531 KB | 7,637 KB | OK |

**Why the production crash occurs at only ~20 levels**: Production `PDF.HTML.Context` operations (`_pushElement`, `_popElement`, `applyTagStyle`) are 100+ line functions with large local state (`Element.Scope` — 13 fields, `PDF.Context.Style`, margin computation, table/list switch statements). These contribute ~11 KB per frame vs ~2.8 KB in the isolated reproduction. The mechanism is identical — cumulative `_render → body → _render` stack depth exceeds the cooperative pool budget.

**Key finding**: The overflow is NOT specific to `_Tuple.init` width (as initially hypothesized from the crash report). The crash at `_Tuple.init` in production is the point where cumulative stack usage — already near the limit from the `_render` chain — is pushed over the edge by the final allocation. The isolated reproduction confirms this: it overflows with zero-size view structs and a modest WideLeaf, purely from the depth of the `_render → body` chain.

## Question

How should the rendering infrastructure ensure complex view trees can render without stack overflow on the cooperative thread pool, while preserving: (1) static dispatch performance, (2) `~Copyable` context compatibility, (3) no `@escaping` in the rendering pipeline, (4) no existential boxing in the hot path, (5) pull-based `body` property for future browser rendering?

## Analysis

### Excluded: Thread-Based Approaches (Options A, B)

Thread-based approaches (larger stack via `IO.Blocking.Lane`, raw `pthread` trampoline) are **excluded**. They treat the symptom (insufficient stack budget) rather than the root cause (eager materialization of all children simultaneously). Rendering is one-shot PDF/HTML generation — the architecture should not require thread infrastructure to compensate for a data structure deficiency.

See v2.0.0 of this document for full analysis of Options A and B.

---

### Excluded: `@autoclosure @escaping` on `buildBlock`

Placing `@autoclosure @escaping` directly on `buildBlock` parameters fails in production because it captures non-escaping `@Builder` closure parameters from enclosing scopes:

```swift
struct Table<Content> {
    init(@Rendering.Builder _ content: () -> Content) { ... }  // content is non-escaping
}

var body: some HTML.View {
    Table { ... }  // @autoclosure @escaping wraps this → tries to capture non-escaping closure
}
```

The compiler considers the non-escaping `content` closure parameter to be "captured" by the escaping autoclosure, even when the closure is a literal. This is a fundamental limitation of Swift's escape analysis — `@autoclosure @escaping` cannot contain calls to functions with non-escaping closure parameters.

**Error**: `escaping autoclosure captures non-escaping parameter 'content'`

---

### Excluded: `@escaping` Closures in `_Tuple`

The `buildExpression` approach wraps each expression in `() -> T` closures stored in `_Tuple`. This requires `@escaping` on the closures because they're stored in a struct property. Two problems:

1. **Conceptually wrong**: The closures are created in `body.getter`, stored in `_Tuple`, consumed once in `_render`, and discarded. They don't truly escape. `@escaping` misrepresents their lifecycle.

2. **Compiler limitation in builder transform**: `buildOptional`/`buildEither` results bypass `buildExpression` and go directly to `buildBlock` as values. `buildBlock` receives a mix of closures (from `buildExpression`) and values (from control flow). Making control flow methods return closures too (`buildOptional<V>(_ v: V?) -> () -> V?`) triggers overload resolution failures in the result builder transform — the compiler cannot match function-typed VALUES from `buildEither` against the `@escaping () -> Content` parameter of single-element `buildBlock`.

See `swift-rendering-primitives/Experiments/lazy-tuple-builder/` for full validation of the mechanism in isolation (11 variants CONFIRMED) and documentation of the builder transform blockers.

---

### Option C: Heap-Allocate `_Tuple` Content (Boxing)

Replace `_Tuple`'s stack-allocated storage with heap-backed storage to reduce per-frame cost.

```swift
public struct _Tuple<each Content> {
    let box: _TupleBox<repeat each Content>
    public init(_ content: repeat each Content) {
        box = _TupleBox(repeat each content)
    }
}
final class _TupleBox<each Content> {
    let content: (repeat each Content)
    init(_ content: repeat each Content) {
        self.content = (repeat each content)
    }
}
```

| Property | Value |
|----------|-------|
| Fixes root cause | **Partially** — `_Tuple.init` frame is pointer-sized, but children still evaluated simultaneously on `body.getter` frame |
| Heap allocation overhead | 1 allocation per builder block |
| `~Copyable` compatible | **No** — class box requires Copyable elements |
| Static dispatch preserved | Yes |
| No `@escaping` | **Yes** — stores values, not closures |
| Fragility | Sufficiently complex views could still overflow at `body.getter` |

**Verdict**: Stopgap. Fixes the specific `_Tuple.init` crash but doesn't address `body.getter` frame pressure. Breaks `~Copyable` element support.

---

### Option E: Lazy `~Escapable` `_Tuple` (Pending Compiler Support)

The architecturally correct solution. `_Tuple` is `~Escapable`, stores `@escaping` closures, and uses `@_lifetime(immortal)` to opt out of lifetime tracking on the closure values (which are heap-allocated and independently reference-counted).

```swift
public struct _Tuple<each Content>: ~Escapable {
    public let content: (repeat () -> each Content)

    @_lifetime(immortal)
    public init(_ content: repeat @escaping () -> each Content) {
        self.content = (repeat each content)
    }
}
```

The `~Escapable` constraint means `_Tuple` cannot outlive the rendering scope — it's returned from `body.getter` and consumed in `_render`. The closures inside are `@escaping` (heap-allocated function pointers + context), but the container is lifetime-bounded.

**Why `~Escapable` matters**: `@escaping` is the price of storing closures in a Copyable struct. `~Escapable` makes that price honest — the struct declares it won't escape, so the `@escaping` closures are only reachable within the rendering scope.

**Validated storage pattern**: `swift-institute/Experiments/resumption-nonescapable-noncopyable/` — a `~Copyable, ~Escapable` struct stores an `@escaping @Sendable () -> Void` closure via `@_lifetime(immortal)`. All 7 variants CONFIRMED.

**Blockers**:

| Blocker | Status | Reference |
|---------|--------|-----------|
| `buildBlock` overload resolution in builder transform | BLOCKED | This document, "Compiler Limitation" |
| `Optional<~Escapable>` storage (needed for `buildOptional`) | BLOCKED | `pointer-nonescapable-storage` V6-V8 |
| Gap A: `@_lifetime(copy)` on closures | BLOCKED | `nonescapable-gap-revalidation-624` |
| `@_lifetime(immortal)` bypass | WORKS | `resumption-nonescapable-noncopyable` V1-V7 |

**Path forward**: File Swift compiler bug for `buildBlock` matching. Once resolved, implement at L1.

---

### Architectural Context: Pull-Based vs Push-Based Rendering

The rendering pipeline uses **pull-based** rendering: `body` returns a value (the view tree), which is then consumed by `_render`. The stack overflow is an implementation deficiency in how `_Tuple` materializes children, not a fundamental flaw of pull-based design.

**Why pull-based is correct for this ecosystem**:
- Future browser rendering (SwiftUI-like) requires diffable view trees — pull-based provides the materialized tree for comparison
- CSS layout (flexbox, grid) requires knowing ALL children before sizing — can't push-style
- Result builders ARE pull-based — `@resultBuilder` produces return values

**Why push-based is NOT the fix**:
- Push-based would eliminate the stack overflow but lose result builder syntax
- One-shot PDF/HTML rendering doesn't need the tree after traversal, but browser rendering will
- SwiftUI renders arbitrarily complex trees without stack overflow via a heap-allocated attribute graph — the fix is to make `_render` smarter, not to abandon pull-based

---

### Experimental Validation of Option C (v6)

A boxed `_BoxedTuple` variant was added to the `cooperative-pool-stack-overflow` experiment alongside the original inline `_Tuple` reproduction. The boxed variant uses an identical 200-level nesting chain (B001–B200) with `BoxedWideLeaf` at the leaf. The only difference: `_BoxedTuple.init` stores content in a heap-allocated `_TupleBox` class (8 bytes on the stack) instead of inline `(repeat each Content)` (~9.4 KB on the stack).

**Results (cooperative pool, debug build)**:

| Variant | Max survivable depth | Crash depth |
|---------|---------------------|-------------|
| Boxed `_BoxedTuple` | B176 | B177 |
| Inline `_Tuple` | ~N173 (estimated) | ~N174 (estimated) |

**Conclusion**: Boxing gains ~3 levels (~9 KB) of headroom. This is negligible — the difference between inline and boxed thresholds is within the `_Tuple.init` frame size (~9.4 KB) divided by per-level cost (~3.08 KB). **Option C addresses only width, not depth.** The `_render → body → _render` recursion chain exhausts the 544 KB stack budget independently of what happens at the leaf.

**Implication**: Neither Option C nor Option E solves the full problem. Both address `_Tuple` storage (width), but the dominant cause — recursive `_render` depth — is untouched. A complete solution must address **both axes**: depth (recursive `_render` chain) AND width (`_Tuple` materialization).

---

### Prior Art: OpenSwiftUI and Elementary

See `swift-rendering-primitives/Research/prior-art-view-tree-materialization.md` for full analysis.

**OpenSwiftUI** stores `TupleView` as an inline tuple (identical to our `_Tuple`) but never has the stack overflow problem because view values live in a **C++ attribute graph arena** accessed via 4-byte `UInt32` handles. The Swift stack carries handles, not values. Body evaluation is lazy (graph rule nodes). The attribute graph addresses both depth (lightweight per-frame cost) and width (heap-allocated storage).

**Elementary** stores children as inline tuples (hand-rolled `_HTMLTuple2`–`_HTMLTuple6` + variadic fallback). Fully eager, stack-allocated, recursive `_render` — **identical vulnerability to ours**. Has not surfaced because HTML element types are lightweight and server-side rendering typically uses larger stacks.

**Key insight**: The only framework that handles arbitrary depth AND width is OpenSwiftUI, via its heap-managed attribute graph. Our architecture needs an equivalent mechanism for one-shot rendering — something that bounds Swift call stack usage regardless of view tree shape.

---

### Option F: Iterative `_render` via Closure-Based Render Queue

Convert the recursive `_render → body → _render` chain into an iterative loop. Instead of recursing, each `_render` pushes a `(inout Rendering.Context) -> Void` closure onto a heap-allocated render queue. The closure captures the concrete type — static dispatch happens at closure creation, not at dequeue time. The loop processes one closure at a time with O(1) call stack depth.

**Why closures, not existentials**: A heterogeneous work stack of `any View` items would require existential boxing — violating the no-existentials constraint. Closures achieve the same result without existentials: each closure is a concrete function type `(inout Rendering.Context) -> Void`, and the static dispatch (`Body._render`) is resolved at the closure's creation site by the compiler. The closure's capture context is heap-allocated, but the function type is concrete.

**Conceptual mechanism**:

```swift
// Current recursive default _render:
extension Rendering.View where Body: Rendering.View {
    public static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
        Body._render(view.body, context: &context)  // recurses
    }
}

// Option F: push closure instead of recursing
extension Rendering.View where Body: Rendering.View {
    public static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
        let body = view.body  // materialized on this frame
        context.enqueue { (ctx: inout Rendering.Context) in
            Body._render(body, context: &ctx)  // static dispatch, resolved at compile time
        }
    }
}

// Rendering entry point: iterative loop
public static func render<V: View>(_ view: V, context: inout Rendering.Context) {
    V._render(view, context: &context)
    while let next = context.dequeue() {
        next(&context)  // each closure may enqueue more work
    }
}
```

**Key properties**:

| Property | Value |
|----------|-------|
| Fixes depth | **Yes** — O(1) call stack per view, O(N) heap |
| Fixes width | Combined with C/E: **Yes** |
| Static dispatch preserved | **Yes** — `Body._render` resolved at closure creation |
| No existentials | **Yes** — `(inout Context) -> Void` is a concrete function type |
| `@escaping` closures | **Yes, internal** — closures stored on the heap, but NOT at the public API boundary. User-facing `body` property and `@Builder` are unchanged |
| `~Copyable` view support | **Requires moving view into closure** — Copyable views can be copied; `~Copyable` views need consuming `_render` or unsafe pointer tricks |
| Pull-based preserved | **Yes** — `body` still returns a value; closures defer traversal, not construction |
| Heap allocation | 1 closure per composite view level |
| Implementation complexity | **Medium** — changes default `_render` and adds render loop at L3 entry points |

**Critical refinement: enqueue only at body boundaries**

Naively converting ALL `_render` calls to enqueue breaks LIFO bracketed operations. Consider `Styled._render`:

```swift
// Current (recursive, synchronous):
static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
    context.push.style()
    applyStyle(view, context: &context)
    Content._render(view.content, context: &context)  // synchronous — content fully rendered here
    context.pop.style()  // runs AFTER content completes
}
```

If `Content._render` enqueues instead of executing, `context.pop.style()` fires immediately — before the content is actually rendered. For nested `Styled` wrappers:

```
// BROKEN (all _render calls enqueue):
push outer style
enqueue(Content._render)     ← deferred, not executed
pop outer style              ← fires NOW, before content renders!
// ... queue processes content later, with wrong style stack
```

**Fix**: Only enqueue at **composite-view-with-body boundaries** — the default `_render` implementation that calls `body`. Custom `_render` implementations (`Styled`, `Tag`, `_Tuple`, all leaves) stay synchronous.

This works because the two sources of stack depth are structurally different:

1. **Composite chain** (`View._render → body → View._render → body → ...`): Unbounded depth. This is what overflows. Each hop crosses a body boundary → **enqueue here**.

2. **Per-level chain** (within one body: `Styled._render × N → Tag._render → _Tuple._render → children`): Bounded depth. Typically ≤15 frames per level. All stay synchronous — push/pop ordering is preserved.

Each segment between body boundaries: ~15 frames × ~3 KB ≈ 45 KB — well within 544 KB. The number of segments is arbitrary but they execute sequentially via the queue, not nested on the stack.

```swift
// ONLY the default _render (body-bearing views) enqueues:
extension Rendering.View where Body: Rendering.View {
    public static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
        context.enqueue { (ctx: inout Rendering.Context) in
            Body._render(view.body, context: &ctx)  // body + its synchronous chain
        }
    }
}

// Styled._render stays synchronous — NOT changed:
static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
    context.push.style()
    applyStyle(view, context: &context)
    Content._render(view.content, context: &context)  // direct call, not enqueued
    context.pop.style()  // correct: runs after content completes
}

// _Tuple._render stays synchronous — NOT changed:
static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
    repeat render(each view.content, &context)  // direct calls, not enqueued
}
```

The rendering entry point runs the queue:

```swift
// L3 entry point:
public static func render<V: View>(_ view: V, context: inout Rendering.Context) {
    V._render(view, context: &context)    // enqueues first body
    while let next = context.dequeue() {
        next(&context)                     // each body may enqueue more
    }
}
```

**Open design questions**:

1. **`body.getter` frame size**: Within an enqueued closure, `view.body` materializes the full return type on the closure's execution frame. For views with large body types, this single frame can be significant. However, it's bounded — only ONE `body.getter` frame exists at a time. Combined with the bounded per-level chain (~45 KB), the peak stack usage per segment is `sizeof(body) + 45 KB`. For practical view types, this is well under 544 KB.

2. **Queue ordering**: The render queue must be FIFO to preserve document order. When `_Tuple._render` iterates N children synchronously, each child's default `_render` (if the child is a composite view) enqueues in left-to-right order. FIFO dequeue preserves this order.

3. **L3 `_render` overrides**: PDF `_Tuple` conformance has spacing/layout logic. Since `_Tuple._render` stays synchronous (it doesn't cross body boundaries itself), L3 overrides work unchanged. The children they iterate may be composite views whose `_render` enqueues, but the iteration and spacing logic completes synchronously.

4. **`@escaping` constraint scope**: The closures are internal to the default `_render` — user-facing `body` properties and `@Builder` blocks are unchanged. `@escaping` is an implementation detail of the traversal, not at the API boundary.

5. **`~Copyable` views**: The closure captures `view.body` (which requires Copyable to capture). For `~Copyable` views, the body value would need to be moved into heap storage first (`Machine.Value.Arena` or `UnsafeMutablePointer`). This motivates Strategy B (machine-style) for the production implementation.

**Comparison with OpenSwiftUI**: OpenSwiftUI's attribute graph achieves the same stack behavior — graph construction stores heap-allocated nodes, traversal is iterative. Option F achieves the equivalent for one-shot rendering without a C++ attribute graph: closures serve as lightweight "graph nodes" that capture view values and static dispatch targets.

---

### Existing Infrastructure: Machine Primitives

The `swift-machine-primitives` and `swift-parser-machine-primitives` packages already implement an iterative tree traversal with an explicit frame stack — solving the exact same structural problem for parsing that we face for rendering. This is production infrastructure, not speculative.

**Core execution model** (`Parser.Machine.Run.swift`): A single `while true` loop with `Stack<Frame>` and `Value<Mode>.Arena`:

```swift
var current: Node<Input, Failure>.ID    // Currently executing node
var frames: Stack<Frame>                 // Continuation stack (heap)
var arena: Value<Mode>.Arena             // Intermediate value storage (heap)
var pendingHandle: Value.Handle?         // Result of last node

while true {
    if let handle = pendingHandle { /* process child result, pop frame */ }
    let node = program[current]
    switch node {
        // Each case: push frame + update current, OR set pendingHandle
    }
}
```

**Key abstractions**:

| Machine Abstraction | What It Does | Rendering Equivalent |
|---------------------|-------------|---------------------|
| `Machine.Frame` enum | Continuation state — no existentials, just enum cases | Render continuation (what to do after a child) |
| `Machine.Value<Mode>` | Type-erased value — `ObjectIdentifier` + raw pointer, no `Any` | Materialized body value |
| `Machine.Value.Arena` | Slot-based heterogeneous storage with handle-based access | Body value arena |
| `Transform.Erased<Mode>` | Witness struct — stores `Capture.RawID` + dispatch closure | `_render` witness |
| `Stack<Frame>` | Heap-allocated continuation stack | Render work stack |
| `Capture.Store` / `Capture.Frozen` | Build-time mutable → runtime immutable operation store | Not needed (rendering is one-shot) |

**Two implementation strategies** emerge:

**Strategy A — Closure queue** (simpler): Each `_render` pushes `(inout Context) -> Void` closures. The closure captures the body value + static dispatch target. No new infrastructure needed beyond a `Queue` or `Stack`.

**Strategy B — Machine-style** (structured): Each `_render` stores the materialized body in a `Value<Mode>.Arena` (type-erased) and pushes a `(Value.Handle, RenderWitness)` pair onto a work stack. The loop pops, retrieves the value, calls the witness. Uses the existing machine infrastructure.

**Trade-offs**:

| | Strategy A: Closures | Strategy B: Machine-style |
|---|---|---|
| Heap allocations | 1 closure context per view | 1 arena slot per view (amortized) |
| Cache locality | Scattered (each closure is its own allocation) | Contiguous (arena storage) |
| Infrastructure reuse | None (raw closures) | `Machine.Value`, `Machine.Value.Arena`, `Stack` |
| `~Copyable` body values | Requires moving into closure | Arena supports `~Copyable` via raw pointer storage |
| Complexity | Low | Medium |
| Debuggability | Opaque (closures are black boxes) | Inspectable (value handles, explicit frame types) |
| Parsing features (backtracking, memoization) | Not applicable | Available but not needed |

**Recommendation**: Strategy A (closures) for the initial implementation — lowest complexity, provably correct. Strategy B as a future optimization if cache locality or `~Copyable` body support becomes important.

**Regardless of strategy, the `Stack` and `Queue` primitives from `swift-stack-primitives` / `swift-queue-primitives` are directly reusable.** The graph primitives' iterative DFS/BFS patterns (`Graph.Traversal.First.Depth/Breadth`) demonstrate the exact loop structure needed.

**Buffer.Arena constraint**: `Buffer.Arena` is monomorphic (single `Element` type per arena). For heterogeneous body values, you'd either wrap in an enum (impossible — open set of view types) or use `Machine.Value<Mode>` which IS designed for heterogeneous storage via `ObjectIdentifier`-based type erasure. This is a key reason to prefer `Machine.Value.Arena` over `Buffer.Arena` if going with Strategy B.

**Verdict**: This is the most promising direction for a complete depth fix that satisfies all governing constraints. The closure-based approach (Strategy A) avoids existentials while preserving static dispatch. The machine-style approach (Strategy B) reuses existing infrastructure for better performance characteristics. Combined with Option C/E for width, either strategy addresses both axes. Key risk: `body.getter` frame size for very wide views (mitigated by the fact that only ONE such frame exists on the stack at a time).

---

### Comparison

| Criterion | C: Box _Tuple | E: ~Escapable _Tuple | F: Closure Render Queue |
|-----------|---------------|----------------------|------------------------|
| Handles arbitrary depth | **No** | **No** | **Yes** |
| Handles arbitrary width | Yes | Yes | With C/E: **Yes** |
| Fixes root cause | Width only | Width only | Depth (primary cause) |
| Static dispatch (100%) | Yes | Yes | **Yes** (resolved at closure creation) |
| No existentials | Yes | Yes | **Yes** (concrete function type) |
| `~Copyable` compatible | **No** (class box) | Yes (with `~Escapable`) | Deferred (~Copyable views don't exist yet) |
| No `@escaping` at API boundary | Yes | Yes (`~Escapable` bounds it) | **Yes** (`@escaping` is internal to traversal) |
| Builder transform compatible | Yes | **BLOCKED** | Yes (orthogonal) |
| Heap allocation | 1 per block | 1 per expression | 1 closure per composite view |
| Implementation complexity | Low | Medium (pending compiler) | Medium |
| Experimentally validated | **Yes — insufficient alone** | Mechanism only (V1-V10) | Not yet |

### Combined Approach

A complete solution likely requires **F + C** (short-term) or **F + E** (long-term):

- **F** addresses depth: iterative traversal bounds call stack to O(1) per view
- **C/E** addresses width: heap-allocated or lazy `_Tuple` content avoids large leaf frames
- Together they handle arbitrary view tree shapes on the 544 KB cooperative pool

## Outcome

**Status**: IN_PROGRESS

### Revised Assessment (v6)

The original framing (v1–v4) identified `_Tuple.init` width as the primary cause based on the crash report's top frame. The isolated reproduction (v5) and experimental validation of Option C (v6) revealed that **depth is the dominant cause**: the recursive `_render → body → _render` chain exhausts the stack budget before reaching the leaf. Width at the leaf (`_Tuple.init`) is an amplifier, not the root cause.

**Options C and E are necessary but insufficient.** They address `_Tuple` storage (the width axis) but do not bound the depth of the recursive rendering chain. A complete solution must also address depth — likely via an iterative rendering mechanism (Option F) that moves traversal state to the heap.

### Path Forward

1. **Experiment with Option F** (closure render queue): Validate the closure-based iterative `_render` in the `cooperative-pool-stack-overflow` experiment. Test that the same depth/width combinations that crash with recursive `_render` survive with iterative dispatch. Key variant: default `_render` enqueues a closure instead of recursing; rendering entry point runs the iterative loop.

2. **Ship F + C**: Option F addresses depth (the dominant cause). Option C addresses width (the amplifier). Together they handle arbitrary view tree shapes. Both are implementable today without compiler changes.

3. **Long-term: F + E**: When `~Escapable` builder support lands, replace Option C with Option E for `_Tuple` storage. This restores `~Copyable` element support while keeping the iterative traversal from Option F.

### Governing Constraints

#### Non-Negotiable Production Requirements

| # | Requirement | Rationale |
|---|------------|-----------|
| R1 | **Static dispatch (100%)** | No dynamic dispatch, no vtable lookups. Every `_render` call resolves at compile time. This is the foundation of the rendering architecture's performance model. |
| R2 | **No existentials** | No `any View`, no `Any`, no protocol-typed storage. Existentials erase type information and introduce heap allocation + witness table indirection. Contradicts R1. |
| R3 | **`~Copyable` support** | The `Rendering.View` protocol is `~Copyable`. View types, body types, and context are all `~Copyable`-capable. The solution must not regress this — no implicit Copyable constraints. |
| R4 | **No `@escaping` closures at API boundary** | User-facing APIs (`body` property, `@Builder` blocks, view initializers) must not require `@escaping`. Internal implementation may use `@escaping` if scoped to the traversal mechanism. |
| R5 | **No thread-based workarounds** | No larger stacks, no `pthread` trampolines, no `IO.Blocking.Lane`. Fix the root cause (data structure / traversal design), not the symptom (insufficient stack budget). |
| R6 | **Pull-based rendering** | `body` returns a value (the view tree). Future browser rendering (SwiftUI-like diffing) requires materialized trees. Push-based alternatives (streaming, visitor) are excluded for the core path. |
| R7 | **Arbitrary depth AND width** | Must handle view trees of any nesting depth and any sibling count without stack overflow on the 544 KB cooperative thread pool. Neither axis alone is sufficient. |
| R8 | **L1 fix** | The root cause is in `Rendering Primitives Core` (Layer 1). The fix must be at L1, not worked around at L3 entry points. L3 may need minor changes (e.g., calling a drain method) but the mechanism lives at L1. |
| R9 | **`borrowing Self` on `_render`** | The `_render` protocol method takes `borrowing Self`. This is a deliberate ownership choice — views may contain borrowed references. Any solution must work within this parameter convention. |
| R10 | **Preserve push/pop LIFO ordering** | Bracketed context operations (push style → render content → pop style) must execute in correct LIFO order. Deferred/queued rendering must not break this invariant. |

#### Current Protocol Surface (Immutable)

```swift
public protocol View: ~Copyable {
    associatedtype Body: View & ~Copyable
    @Builder var body: Body { get }
    static func _render(_ view: borrowing Self, context: inout Context)
}
```

#### Key Tension (v6)

R3 (`~Copyable`) + R7 (arbitrary depth) + R9 (`borrowing Self`) create a fundamental tension: to defer body rendering (solving depth), the body value must be stored on the heap. But `borrowing Self` prevents extracting a `~Copyable` body for storage — the compiler only allows the body to flow directly to another `borrowing` parameter (which is how the recursive `_render` works today).

Options under investigation:
- **Consuming variant**: Add `consuming` `_render` method or change parameter convention. Allows extracting body for heap storage. Breaks existing `_Tuple._render` pack iteration.
- **Unsafe pointer extraction**: Raw-copy the body from a borrowing reference to heap storage. Genuinely unsafe (double-destroy risk without lifetime manipulation).
- **Machine-style value arena**: Use `Machine.Value<Mode>` (ObjectIdentifier + raw pointer) for type-erased heap storage, with witness structs for render dispatch. Defers the `borrowing` → heap transition to unsafe internals with a safe public API.
- **Protocol evolution**: Add a second protocol method with `consuming` convention specifically for iterative rendering, keeping `borrowing _render` for synchronous leaf chains.

## References

### Primary Research

- **This document**: `swift-rendering-primitives/Research/cooperative-pool-stack-overflow.md` (v6, IN_PROGRESS)
- **Prior art survey**: `swift-rendering-primitives/Research/prior-art-view-tree-materialization.md` — OpenSwiftUI attribute graph, Elementary inline tuples. Validates that only heap-managed indirection (attribute graph) handles both depth and width.

### Experiments

- `swift-rendering-primitives/Experiments/cooperative-pool-stack-overflow/` — **Isolated reproduction (CONFIRMED)**. Self-contained, no dependencies. 200 nesting levels of `Tag + 6× Styled` wrappers. SIGBUS at depth ~177 on cooperative pool; passes on main thread. Measured ~3.08 KB/level, ~544 KB pool budget. **Option C boxed variant tested (v6)**: `_BoxedTuple` gains only ~3 levels of headroom (B176 OK vs ~N173 OK) — confirms depth, not width, is the dominant cause.
- `swift-rendering-primitives/Experiments/lazy-tuple-builder/` — Lazy `_Tuple` mechanism, 11 variants all CONFIRMED. Validates the closure-storage approach in isolation; documents builder transform blockers.
- `swift-rendering-primitives/Experiments/borrowing-pattern-matching/` — Borrowing patterns for `_render`, 8 variants CONFIRMED.
- `swift-institute/Experiments/resumption-nonescapable-noncopyable/` — `~Escapable` struct storing `@escaping` closures via `@_lifetime(immortal)`. 7 variants CONFIRMED. Key evidence for Option E.
- `swift-institute/Experiments/pointer-nonescapable-storage/` — `~Escapable` inline storage patterns, 16 variants. Confirms `Optional<~Escapable>` is BLOCKED (V6-V8). Enum workaround (V14-V15) for variable occupancy.
- `swift-institute/Experiments/nonescapable-gap-revalidation-624/` — Gap A (`@_lifetime(copy)` on closures) BLOCKED. `@_lifetime(immortal)` bypass CONFIRMED.
- `swift-institute/Experiments/conditional-escapable-container/` — Conditional `Escapable` conformance patterns. Multi-element containers BLOCKED by UnsafePointer Escapable requirement.
- `swift-institute/Experiments/escapable-lazy-sequence-borrowing/` — `~Escapable` lazy operators (map, filter) with `@_lifetime`. 9 variants CONFIRMED.
- `swift-institute/Experiments/tagged-escapable-accessor/` — Cross-package `~Escapable` propagation. Stored properties WORK; `_read` coroutines BLOCKED.

### Related (Different Issue)

- `swift-pdf-html-rendering/Research/iterative-tuple-rendering.md` — Dynamic dispatch path overflow from `buildPartialBlock` binary nesting. Orthogonal to this issue.

### Crash Artifacts

- Crash report: `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-03-17-153906.ips`
- Crashing view: `rule-besloten-vennootschap/Sources/Aandeelhoudersregister PDF/Register.Certificaathouder.swift`

### Infrastructure

- Rendering primitives: `swift-rendering-primitives/Sources/Rendering Primitives Core/Rendering.View.swift`
- `_Tuple`: `swift-rendering-primitives/Sources/Rendering Primitives Core/Rendering._Tuple.swift`
- Builder: `swift-rendering-primitives/Sources/Rendering Primitives Core/Rendering.Builder.swift`
- L3 rendering entry point: `swift-pdf-html-rendering/Sources/PDF HTML Rendering/PDF.HTML+EntryPoints.swift`

### Reusable Primitives (Option F)

- **Machine execution loop**: `swift-parser-machine-primitives/.../Parser.Machine.Run.swift` — iterative `while true` with `Stack<Frame>`, `Value.Arena`, no recursion
- **Type-erased values**: `swift-machine-primitives/.../Machine.Value.swift` — `ObjectIdentifier` + raw pointer, no existentials
- **Value arena**: `swift-machine-primitives/.../Machine.Value.Arena.swift` — slot-based heterogeneous storage with handle access
- **Witness structs**: `swift-machine-primitives/.../Machine.Transform.Erased.swift` — type-erased operations via `Capture.RawID` + dispatch closure
- **Frame enum**: `swift-machine-primitives/.../Machine.Frame.swift` — heterogeneous continuation types as enum cases
- **Iterative graph traversal**: `swift-graph-primitives/.../Graph.Traversal.First.Depth.swift` — DFS via `Stack<Node>` + `Bit.Vector` visited set
- **Stack/Queue**: `swift-stack-primitives/`, `swift-queue-primitives/` — work list data structures
- **Buffer arena**: `swift-buffer-primitives/.../Buffer.Arena.swift` — monomorphic slot-based allocation with generation tokens (NOT suitable for heterogeneous values — use `Machine.Value.Arena` instead)
