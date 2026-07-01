# Prior Art: View Tree Materialization Strategies

<!--
---
version: 1.0.0
last_updated: 2026-03-18
status: DECISION
tier: 2
---
-->

## Context

The cooperative pool stack overflow documented in `cooperative-pool-stack-overflow.md` (v4) is caused by `_Tuple.init` materializing all children simultaneously on a single stack frame. Before implementing Option C (box `_Tuple`) as a stopgap, we survey how other Swift rendering frameworks handle the same structural problem: composing N children of arbitrary generic depth via a result builder and traversing them during rendering.

**Trigger**: Need to validate that Option C is the right interim fix and that Option E (~Escapable closures) is architecturally sound as the long-term solution, by comparing against existing practice.

**Packages surveyed**:
- [OpenSwiftUI](https://github.com/OpenSwiftUIProject/OpenSwiftUI) — open-source re-implementation of Apple SwiftUI's view graph
- [Elementary](https://github.com/elementary-swift/elementary) — server-side HTML rendering library

## Question

How do other Swift rendering frameworks store composed children, traverse them during rendering, and (if at all) mitigate stack overflow from wide/deep view trees?

## Analysis

### OpenSwiftUI

**Source**: `OpenSwiftUIProject/OpenSwiftUI`, audited 2026-03-18.

#### Storage

`TupleView` stores children as an **inline Swift tuple** — identical to our `_Tuple`:

```swift
@frozen
public struct TupleView<T>: PrimitiveView, View {
    public var value: T  // T = (Text, Image, Spacer, ...)
}
```

No heap boxing, no closure indirection, no array. `@frozen` guarantees ABI-stable inline layout.

#### Builder

Uses variadic `buildBlock` with parameter packs — identical to our approach:

```swift
@_disfavoredOverload
public static func buildBlock<each Content>(
    _ content: repeat each Content
) -> TupleView<(repeat each Content)> where repeat each Content: View {
    TupleView((repeat each content))
}
```

No `buildPartialBlock`. Single-child passthrough, zero-child `EmptyView`.

#### Traversal

**This is where OpenSwiftUI fundamentally diverges.** SwiftUI does NOT render by recursively calling `body`. Instead, it uses a **static protocol witness graph construction** pattern:

1. Every `View` has `static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs`
2. `_GraphValue<V>` wraps `Attribute<V>`, which is a **32-bit handle** (`UInt32`) pointing into a C++ attribute graph arena
3. User view bodies are lazily evaluated via `StaticBody`/`DynamicBody` rule nodes — the `body` property is invoked only when the graph demands it
4. `TupleView._makeViewList` iterates children via runtime tuple metadata (`TupleTypeDescription`) and creates **derived attribute handles** via byte-offset projections:

```swift
let view = view.value.unsafeOffset(at: offset, as: V.self)
// Returns Attribute<V> — another UInt32 handle, not the V value
```

**Key insight**: During graph construction, the Swift call stack carries only `Attribute<V>` handles (4 bytes each) and metadata — never the actual view values. The view values live in the C++ attribute graph's heap-managed arena. The `body` property is a lazy rule that's evaluated when the graph is pulled, not when the tree is constructed.

#### Stack overflow mitigation

**None explicit.** OpenSwiftUI relies entirely on the attribute graph indirection: the Swift stack never holds materialized view trees, only lightweight handles. The graph construction recursion (`_makeView` → `Body._makeView`) IS on the call stack, but each frame carries only handles and metadata, not full generic view types.

The C++ AttributeGraph framework manages all actual storage via arena/slab allocation.

---

### Elementary

**Source**: `elementary-swift/elementary`, audited 2026-03-18.

#### Storage

Hand-rolled tuple structs for 2–6 children, variadic generic fallback for 7+:

```swift
// Arity 2-6: concrete structs
public struct _HTMLTuple2<V0: HTML, V1: HTML>: HTML {
    public let v0: V0
    public let v1: V1
}
// ... through _HTMLTuple6

// Arity 7+: variadic (non-Embedded only)
@available(iOS 17, *)
public struct _HTMLTuple<each Child: HTML>: HTML {
    public let value: (repeat each Child)
}
```

All inline, stack-allocated. Source comment: *"variadic generics perform significantly worse than the hand-rolled tuples"* — the concrete structs are preferred even when variadic generics are available.

#### Builder

Classic `buildBlock` overloads (arity 0–6 + variadic). No `buildPartialBlock`. For >6 children in Embedded mode, users must nest `Group` blocks.

#### Traversal

**Push-based token streaming** — structurally similar to our `_render`, but with `consuming` ownership:

```swift
// _HTMLTuple4._render:
V0._render(html.v0, into: &renderer, with: copy context)
V1._render(html.v1, into: &renderer, with: copy context)
V2._render(html.v2, into: &renderer, with: copy context)
V3._render(html.v3, into: &renderer, with: copy context)
```

Same pattern as our `repeat render(each view.content, &context)`. Each child is visited sequentially at the same call stack depth. The recursion comes from component nesting (`body` → `Content._render`).

**Eager materialization**: children are constructed at init time (`self.content = content()`), same as ours.

#### Stack overflow mitigation

**None.** Elementary relies on two structural properties:

1. **Flat tuples** (not nested pairs) — caps per-block width at 6 concrete children, limiting per-frame tuple size
2. **Shallow real-world HTML trees** — HTML documents tend to be wide, not deeply nested with heavy styling generics

Elementary has the same vulnerability as our rendering primitives. The difference is that WHATWG elements + CSS modifiers produce deeply nested generic types (`Styled<Styled<Element.Tag<_Tuple<...>>>>`) that are individually large, whereas Elementary's `HTMLElement` types are relatively lightweight.

---

### Comparison

| Criterion | Our `_Tuple` | OpenSwiftUI `TupleView` | Elementary `_HTMLTuple` |
|-----------|-------------|------------------------|------------------------|
| **Storage** | Inline tuple | Inline tuple | Inline tuple (hand-rolled 2–6, variadic 7+) |
| **Builder** | Variadic `buildBlock` | Variadic `buildBlock` | Overloaded `buildBlock` (2–6) + variadic |
| **Where values live** | Stack (Swift) | Heap (C++ attribute graph arena) | Stack (Swift) |
| **Traversal** | `_render` recursion | `_makeView` graph construction | `_render` token streaming |
| **Body evaluation** | Eager (in `body.getter`) | Lazy (graph rule node) | Eager (in `init`) |
| **Per-child stack cost** | Full generic type size | 4 bytes (UInt32 handle) | Full generic type size |
| **Stack overflow mitigation** | None (crashes) | Implicit via attribute graph | None (not yet observed) |
| **Heap allocation** | None | 1 graph node per view | None (except arrays/closures) |
| **`~Copyable` support** | Yes (protocol) | No | No (`consuming` but Copyable) |

### Key Finding

**The three frameworks use identical tuple storage and builder strategies.** The divergence is in the rendering architecture:

1. **OpenSwiftUI** never has the problem because view values live in a heap-managed attribute graph. The Swift stack only carries 4-byte handles. This is a consequence of SwiftUI's reactive/incremental rendering model — the graph exists for diffing, not for stack overflow mitigation.

2. **Elementary** has the same vulnerability we do. It hasn't surfaced because: (a) HTML element types are lightweight compared to WHATWG + CSS modifier chains, (b) server-side HTML rendering typically runs on main thread or dedicated threads with larger stacks, (c) the hand-rolled arity-6 cap limits per-frame tuple size.

3. **Our rendering primitives** hit the problem because of the specific combination of: deeply nested generic types (WHATWG elements + CSS modifiers → kilobytes per child), moderate width (8 children), moderate depth (~50 frames), and the 544 KB cooperative pool stack.

**No framework uses laziness (closures) for child storage.** OpenSwiftUI achieves laziness at the graph level (body is a lazy rule), but `TupleView.value` is an eager inline tuple. Elementary is fully eager. Our Option E (~Escapable closures) would be novel in this space.

## Outcome

**Status**: DECISION

### Validation of Option C (Box `_Tuple`)

Option C is **architecturally analogous to what OpenSwiftUI's attribute graph does** — move the heavy data from the Swift stack to the heap, keeping a lightweight handle (pointer vs. UInt32) on the stack. The difference is granularity:

| Approach | Granularity | Per-frame cost |
|----------|-------------|---------------|
| OpenSwiftUI attribute graph | Per-child node | 4 bytes per child |
| Option C (box entire tuple) | Per-tuple | 8 bytes per tuple (one pointer) |
| Option E (~Escapable closures) | Per-child closure | 8 bytes per child (closure pointer) |

Option C is coarser-grained but sufficient: the crash is in `_Tuple.init` allocating the full tuple on one frame. Boxing the tuple reduces that frame from kilobytes to 8 bytes. The `body.getter` still has all children on the stack as locals, but that's a theoretical concern — the observed crash is in `_Tuple.init`.

### Validation of Option E as Long-Term Target

Option E (~Escapable closures) would achieve what no surveyed framework does: **per-child lazy materialization**. During `_render`, only one child exists on the stack at a time. This is strictly better than OpenSwiftUI's approach for one-shot rendering (no graph infrastructure needed) and eliminates both the `_Tuple.init` crash AND the theoretical `body.getter` pressure.

The prior art survey confirms Option E is novel but well-motivated: it achieves the stack safety of OpenSwiftUI's attribute graph without the architectural complexity of a C++ arena.

### No Architectural Changes Needed

Neither OpenSwiftUI nor Elementary suggests we should change our rendering architecture (pull-based, static dispatch, `_render` recursion). The builder strategy (variadic `buildBlock`, no `buildPartialBlock`) is validated by both frameworks. The fix is localized to `_Tuple`'s storage — exactly what Options C and E address.

## References

### Primary Sources

- OpenSwiftUI: `Sources/OpenSwiftUICore/View/TupleView.swift`, `ViewBuilder.swift`, `CustomView.swift`
- Elementary: `Sources/Elementary/Core/HtmlBuilder+Tuples.swift`, `HtmlBuilder.swift`, `_HtmlRendering.swift`

### Related Research

- `cooperative-pool-stack-overflow.md` (v4) — root cause analysis and option enumeration
- `swift-pdf-html-rendering/Research/iterative-tuple-rendering.md` — orthogonal `buildPartialBlock` nesting issue
- `swift-rendering-primitives/Experiments/lazy-tuple-builder/` — Option E mechanism validation (V1-V10 CONFIRMED)
