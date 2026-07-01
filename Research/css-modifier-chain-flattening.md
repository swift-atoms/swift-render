# CSS Modifier Chain Flattening

<!--
---
version: 1.0.0
last_updated: 2026-03-18
status: RECOMMENDATION
tier: 2
---
-->

## Context

Each `.css.property(value)` call wraps the view in `HTML.Styled<Content, P>`, adding one `Styled._render` frame to the call stack. A view with 6 CSS modifiers produces 6 nested `Styled` wrappers → 6 extra frames per view level. In the cooperative pool stack overflow reproduction (`cooperative-pool-stack-overflow` experiment), CSS modifiers account for 6 of the 9 frames per nesting level (~67% of per-level stack cost).

**Trigger**: Critical review of Options C/E identified that neither addresses `_render → body → _render` recursion depth. CSS modifier chains are a significant multiplier of that depth: flattening N modifiers into 1 wrapper would reduce per-level frame count from 9 to 3 — a potential 3× stack reduction.

**Relationship to Option F**: The v6 research (`cooperative-pool-stack-overflow.md`) proposes Option F (closure-based render queue) as the depth fix. Option F converts recursive `_render` calls into iterative closure dispatch, making per-level frame count irrelevant for stack depth. This investigation evaluates whether CSS flattening is still valuable given Option F.

## Question

Should CSS modifier chains be flattened from `Styled<Styled<Styled<Base, P1>, P2>, P3>` into a single wrapper `Styled<Base, AccumulatedStyles>`, and if so, how does this interact with the typed/class-based dual rendering path and with Option F?

## Analysis

### Current Architecture

**Type chain**: Each `.css.property(value)` produces a new generic wrapper:

```swift
// User code:
div.css.color(.red).padding(.px(16)).display(.flex)

// Concrete type:
HTML.CSS<HTML.Styled<HTML.Styled<HTML.Styled<Base, W3C_CSS_Color.Color>, W3C_CSS_BoxModel.Padding>, W3C_CSS_Display.Display>>
```

**`Styled` definition** (`swift-html-rendering/.../HTML.Styled.swift`):

```swift
extension HTML {
    public struct Styled<Content, P: W3C_CSS_Shared.Property> {
        public let content: Content
        public let property: P?
        public let style: HTML.Element.Style?  // pre-computed declaration string
        public let atRule: HTML.AtRule?
        public let selector: HTML.Selector?
        public let pseudo: HTML.Pseudo?
    }
}
```

Size per Styled wrapper: `Content` + `P` + `Style?` (~64-80 bytes) + 3 optionals ≈ sizeof(Content) + ~100-150 bytes overhead.

**`Styled._render`** — dual-path rendering:

```swift
public static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
    context.push.style()
    if let property = view.property {
        handled = context.apply(inlineStyle: property)  // typed path (PDF)
    }
    if !handled, let style = view.style {
        if let className = context.register(style: ...) {
            context.add(class: className)              // class path (HTML)
        }
    }
    Content._render(view.content, context: &context)    // recurses
    context.pop.style()
}
```

Two rendering paths:
1. **Typed path**: `context.apply(inlineStyle:)` passes the concrete `P` value to the context. PDF rendering uses this to interpret CSS properties semantically (e.g., `Color` → PDF color operator, `Padding` → layout inset).
2. **Class-based path**: Falls back to `context.register(style:)` which generates a CSS class name from the declaration string. HTML rendering uses this.

**The 529 property methods** (`swift-css-html-rendering/.../CSS HTML Rendering/`) each follow the same pattern — wrapping in `HTML.Styled<Base, SpecificPropertyType>`.

### Stack Impact

Each `Styled._render` adds one frame: push style, try apply, maybe register, call Content._render, pop style. For N modifiers on one view, the call chain is:

```
Styled<..., P6>._render  → push, apply P6, recurse
  Styled<..., P5>._render  → push, apply P5, recurse
    Styled<..., P4>._render  → push, apply P4, recurse
      Styled<..., P3>._render  → push, apply P3, recurse
        Styled<..., P2>._render  → push, apply P2, recurse
          Styled<..., P1>._render  → push, apply P1, recurse
            Tag._render  → actual element
```

6 frames just for CSS modifiers. In the isolated reproduction, this is 6 of 9 frames per level (~2.8 KB total, so ~1.9 KB for Styled frames alone).

### Option A: Type-Level Style Accumulation

Replace `Styled<Styled<..., P1>, P2>` nesting with a single wrapper holding multiple properties:

```swift
struct StyledN<Content, each P: Property> {
    let content: Content
    let properties: (repeat (each P)?)
    let styles: (repeat HTML.Element.Style?)
    // ...
}
```

**Problems**:

1. **Builder interaction**: `.css.color(.red).padding(.px(16))` is method chaining, not a result builder. Each method returns a new type. Accumulation would require a different API shape — either a builder for styles or a different chaining mechanism.

2. **Typed path loss**: The typed rendering path (`context.apply(inlineStyle: property)`) requires knowing `P` at compile time. A variadic pack `(repeat each P)` preserves this, but the pack iteration in `_render` would still produce N calls to `context.apply` — the frame count is reduced (1 instead of N), but the work is the same.

3. **Compile-time cost**: Variadic generic types with many parameters are expensive for the compiler (as observed in the generic nesting experiment that stalled compilation).

**Verdict**: Theoretically sound but the API change is invasive and the benefit is subsumed by Option F.

### Option B: Runtime Style Collection

Replace typed Styled wrappers with a single wrapper holding a `[Rendering.Action]` array:

```swift
struct StyledBatch<Content> {
    let content: Content
    let actions: [Rendering.Action]
}
```

Each `.css.property(value)` appends to the actions array instead of wrapping in a new type.

**Problems**:

1. **Typed path loss**: `Rendering.Action` is type-erased — `.style(register: declaration, ...)` stores the declaration string, not the typed `P` value. PDF rendering can no longer inspect the CSS property type for semantic interpretation.

2. **Array allocation**: One heap allocation per modifier chain, growing dynamically. Small-buffer optimization could mitigate for typical chains (≤6 properties).

3. **API change**: `.css.color(.red)` would need to return the same type (not a new generic wrapper), appending to the batch. This requires either mutation or copy-on-write — fundamentally different from the current functional chaining.

**Verdict**: Loses the typed rendering path. Not acceptable for PDF rendering.

### Option C: Hybrid — Flatten at Render Time

Keep the current type structure (`Styled<Styled<...>>` nesting) but change `Styled._render` to iteratively peel off all Styled layers before rendering content:

```swift
extension HTML.Styled: Rendering.View where Content: HTML.View {
    public static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
        // Apply this layer's style
        context.push.style()
        applyStyle(view, context: &context)

        // Check if content is also Styled — if so, iterate instead of recurse
        // ... but Content is a generic type parameter, not dynamically inspectable
        // without existential boxing or marker protocol
        Content._render(view.content, context: &context)
        context.pop.style()
    }
}
```

**Problem**: At compile time, `Content` is a fixed generic parameter. `Styled._render` cannot inspect whether `Content` is itself `Styled<...>` without:
- An existential check (`content as? any StyledProtocol`) — violates no-existentials
- A marker protocol with a method to extract the inner content — requires protocol changes across packages

This is the "iterative Styled unwinder" idea from the critical review. It's blocked by the same constraint that makes all dynamic dispatch approaches unacceptable.

**Verdict**: Not feasible without existentials or marker protocols.

### Interaction with Option F (Closure Render Queue)

Option F converts recursive `_render` calls to iterative closure dispatch. Under Option F, `Styled._render` would enqueue a closure for `Content._render` instead of calling it directly:

```swift
// Under Option F:
public static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
    context.push.style()
    applyStyle(view, context: &context)
    let content = view.content
    context.enqueue { (ctx: inout Rendering.Context) in
        Content._render(content, context: &ctx)
        ctx.pop.style()  // deferred pop
    }
}
```

With Option F, the 6 Styled layers produce 6 closures in the queue, each processed with O(1) stack depth. The cumulative stack cost of CSS modifiers drops from ~1.9 KB (6 recursive frames) to ~0 KB (6 closures on the heap, processed one at a time).

**CSS modifier flattening becomes unnecessary for stack safety under Option F.** The depth problem that flattening would solve is already solved by iterative dispatch.

### Remaining Value of Flattening (Post-Option F)

Even with Option F, flattening could provide:

| Benefit | Impact | Priority |
|---------|--------|----------|
| Fewer heap allocations (6 closures → 1) | Marginal — closures are small | Low |
| Simpler generic types (compiler perf) | Meaningful for large views | Low |
| Fewer push/pop style cycles | Marginal — push/pop are cheap | Low |
| Reduced total queue work items | Marginal — dequeue is O(1) | Low |

None of these are blocking or high-priority. They're performance micro-optimizations.

### Existing Flattening Mechanism

The infrastructure already has a runtime flattening mechanism:

- `Rendering.Action` enum captures all rendering operations (text, push/pop, style registration)
- `Rendering.Context.spliceActions([Rendering.Action])` bulk-appends pre-computed actions
- A "capturing context" can pre-render any view subtree into `[Rendering.Action]` and replay

This means any future flattening optimization can be done at the context level (pre-render styled chains into action buffers) without type-level changes. This path is available whenever the performance data justifies it.

## Outcome

**Status**: RECOMMENDATION

**Recommendation**: Do NOT pursue CSS modifier chain flattening as a stack overflow mitigation. Option F (closure render queue) subsumes the benefit.

### Rationale

1. **Option F addresses the depth problem directly.** Under iterative dispatch, CSS modifier nesting no longer contributes to stack depth. The 6 frames per modifier chain become 6 heap-allocated closures, processed one at a time with O(1) stack.

2. **Type-level flattening is invasive and lossy.** Accumulating properties into a single wrapper either loses the typed rendering path (breaking PDF's semantic CSS interpretation) or requires variadic generics (compiler cost, API change).

3. **Runtime flattening is blocked by no-existentials.** Iteratively peeling off Styled layers requires dynamic type inspection, which violates the governing constraints.

4. **Existing infrastructure supports future optimization.** The `Rendering.Action` + `spliceActions` mechanism provides a runtime flattening path without type changes, available whenever profiling identifies CSS modifier overhead as a bottleneck.

### When to Revisit

- If Option F is NOT implemented (constraints change, design is rejected) — flattening becomes the primary depth mitigation for CSS-heavy views
- If profiling shows CSS modifier closure overhead is significant post-Option F — consider action-based pre-rendering
- If the typed rendering path is deprecated (all rendering goes through declaration strings) — type-erased accumulation becomes viable

## References

- `cooperative-pool-stack-overflow.md` (v6) — root cause analysis, Option F proposal
- `prior-art-view-tree-materialization.md` — OpenSwiftUI attribute graph, Elementary inline tuples
- `swift-html-rendering/.../HTML.Styled.swift` — Styled type definition and _render
- `swift-css-html-rendering/.../CSS.swift` — CSS namespace wrapper
- `swift-css-html-rendering/.../CSS HTML Rendering/` — 529 property extension methods
- `swift-rendering-primitives/.../Rendering.Action.swift` — Action enum for runtime flattening
