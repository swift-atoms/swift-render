# ~Copyable Body Support for Iterative Rendering

<!--
---
version: 2.0.0
last_updated: 2026-03-18
status: DECISION
tier: 2
---
-->

## Context

The iterative render machine (Strategy B from `cooperative-pool-stack-overflow.md` v6) requires extracting an owned body value from a borrowed view to store it on the heap for deferred dispatch. The default `_render` needs:

```swift
extension Rendering.View where Body: Rendering.View {
    static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
        let body = view.body                    // must be OWNED
        let ptr = UnsafeMutablePointer<Body>.allocate(capacity: 1)
        ptr.initialize(to: body)                // consuming — requires owned value
        context._stack.append(.render(pointer: ptr, witness: Thunk(Body.self)))
    }
}
```

**Blocker**: `view.body` on `borrowing Self` yields a **borrowed** value when `Body` is `~Copyable`. The compiler error: `'view.body' is borrowed and cannot be consumed`.

**Root cause** (verified in `swift-institute/Experiments/witness-noncopyable-default-forwarding/`, 15 variants): Protocol property access on `~Copyable` associated types dispatches through the witness table's `_read` coroutine, which yields a borrowed value. Protocol function calls dispatch through the witness table's function entry, which returns an owned value. This is a deliberate compiler design — `_read` is the resilient default for ~Copyable property access in opaque interfaces.

**Impact**: Without a fix, the iterative `_render` must be constrained to `where Body: Copyable`, silently excluding ~Copyable bodies from the stack overflow fix. This violates requirement R3 (`~Copyable` support) from the governing constraints.

## Question

Can the `body` property on `Rendering.View` be made to return an owned `~Copyable` value when accessed on a borrowed self, using compiler features available in Swift 6.2?

## Analysis

### Option A: `@_owned` on the protocol property

The Swift compiler provides `@_owned` — an experimental feature (`UnderscoreOwned`, `Features.def:621`) that overrides the default `_read` synthesis for ~Copyable properties, forcing `get` (owned return) semantics.

**Compiler source** (`TypeCheckStorage.cpp:1070-1087`):

```cpp
// Ownership determination precedence:
if (storage->getAttrs().hasAttribute<OwnedAttr>())
  return OpaqueReadOwnership::Owned;           // ← @_owned: force get (owned)

if (storage->getInnermostDeclContext()->mapTypeIntoEnvironment(
      storage->getValueInterfaceType())->isNoncopyable())
  return usesBorrowed(DiagKind::NoncopyableType); // ← default for ~Copyable: _read (borrow)
```

`@_owned` takes precedence over the ~Copyable default. The compiler generates a `get` accessor (returning owned) instead of `_read` (yielding borrowed) in the witness table.

**Application to `Rendering.View`**:

```swift
public protocol View: ~Copyable {
    associatedtype Body: View & ~Copyable
    @_owned @Builder var body: Body { get }
    static func _render(_ view: borrowing Self, context: inout Context)
}
```

One annotation. No protocol surface change. No feature flag needed — `UnderscoreOwned` is `EXPERIMENTAL_FEATURE(UnderscoreOwned, true)` (enabled by default in Swift 6.2).

**Compiler attribute validation** (`TypeCheckAttr.cpp:308-333`):

```
The @_owned attribute REQUIRES that a getter (Get accessor) exists.
The only known use-case for this attribute is for getters returning
noncopyable types that want to override the resilient '_read' that
is always generated, exposing 'get' that returns an owned value.
```

This is exactly our use case. `body` is a computed property with `{ get }`. `@_owned` overrides the implicit `_read` synthesis.

**Compatibility with `@Builder`**: `@_owned` controls accessor kind (compiler-level). `@Builder` transforms the getter body (semantic-level). They are orthogonal — `@_owned` tells the compiler HOW to dispatch the accessor, `@Builder` tells the compiler WHAT the getter body computes.

**Compatibility with conformances**: Concrete conformances that have Copyable body types already default to `get` (owned) because rule 4 only applies to ~Copyable return types. Conformances with ~Copyable body types would need `@_owned` on their `body` property too. No such conformances exist today.

| Property | Value |
|----------|-------|
| Removes Copyable constraint on iterative _render | **Yes** |
| Protocol surface change | **None** (additive annotation only) |
| Feature flag required | **No** (UnderscoreOwned enabled by default) |
| Conformance impact | **None** (Copyable bodies already use get) |
| Compatibility with @Builder | **Orthogonal** |
| Runtime cost | **None** (get vs _read is a compile-time dispatch decision) |

### Option B: Store VIEW instead of BODY ("store VIEW" approach)

**CONFIRMED** — experimentally validated in `iterative-render-machine` experiment.

Instead of storing the body (which requires owning a ~Copyable value), store the VIEW on the heap. The view is typically Copyable (user-defined struct with normal stored properties). The body is computed transiently during dispatch via `view.body` and flows directly as a borrow into `Body._render`. The body is never stored.

```swift
// Default _render: store VIEW (Self: Copyable), Body can be ~Copyable
extension Rendering.View where Body: Rendering.View, Self: Copyable {
    static func _render(_ view: borrowing Self, context: inout Rendering.Context) {
        let viewCopy = copy view
        let ptr = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        ptr.initialize(to: viewCopy)
        context._stack.append(.render(
            pointer: UnsafeMutableRawPointer(ptr),
            witness: Thunk(view: Self.self)  // composite thunk
        ))
    }
}

// Composite Thunk: stores VIEW type, dispatches Body._render via view.body
init<V: View & Copyable>(view _: V.Type) where V.Body: View {
    self.dispatch = { pointer, context in
        let view = pointer.assumingMemoryBound(to: V.self).pointee
        V.Body._render(view.body, context: &context)  // body is transient borrow
    }
    self.destroy = { pointer in
        pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
        pointer.deallocate()
    }
}
```

The constraint shifts from `Body: Copyable` to `Self: Copyable`:

| Approach | Constraint | ~Copyable bodies | ~Copyable views |
|----------|-----------|-------------------|-----------------|
| Store body (old) | `Body: Copyable` | **No** | No |
| Store view (new) | `Self: Copyable` | **Yes** | No (need custom `_render`) |

| Property | Value |
|----------|-------|
| Removes `Body: Copyable` constraint | **Yes** |
| ~Copyable body support | **Yes** — body never stored, flows as borrow |
| Protocol surface change | **None** |
| Feature flag required | **No** |
| Available today | **Yes** (Swift 6.2.4) |
| Conformance impact | **None** (views are typically Copyable structs) |
| ~Copyable views | Need custom `_render` (no production ~Copyable views exist) |
| Runtime cost | Stores view instead of body — similar size for typical views |

**Verdict**: Solves the problem today. No compiler features needed. No protocol changes. Full `~Copyable` body support with `var body` property retained.

---

### Option C: Change `body` from property to function

Protocol function access returns owned through the witness table's function entry (not `_read`):

```swift
public protocol View: ~Copyable {
    associatedtype Body: View & ~Copyable
    @Builder func body() -> Body
    static func _render(_ view: borrowing Self, context: inout Context)
}
```

This would return an owned value without `@_owned`.

| Property | Value |
|----------|-------|
| Removes Copyable constraint | **Yes** |
| Protocol surface change | **Breaking** (property → function) |
| Conformance impact | **All conformances must change** |
| API impact | `view.body` → `view.body()` everywhere |
| Result builder compatibility | Works (`@Builder func body() -> ...`) |

**Verdict**: Correct but unnecessarily invasive. Every view type in every package must change from `var body` to `func body()`. `@_owned` achieves the same result with zero API change.

### Option C: Dual-method protocol (`_enqueue` + `_render`)

Add `consuming` method for iterative path:

```swift
static func _enqueue(_ view: consuming Self, context: inout Context)
```

| Property | Value |
|----------|-------|
| Removes Copyable constraint | **Yes** |
| Protocol surface change | **Doubles it** (new protocol requirement) |
| Conformance impact | **All leaf types must implement _enqueue** |
| Consuming pack destructuring | **Uncertain** (Swift 6.2 support for `repeat consume each`) |

**Verdict**: Over-engineered. Doubles the protocol surface for a problem that `@_owned` solves with one annotation.

### Comparison

| Criterion | A: @_owned | B: Store VIEW | C: func body() | D: Dual method |
|-----------|-----------|---------------|----------------|----------------|
| ~Copyable bodies | **Yes** | **Yes** | Yes | Yes |
| ~Copyable views | **Yes** | No (need custom) | Yes | Yes |
| Protocol surface change | None | **None** | Breaking | Doubled |
| Conformance changes | None | **None** | All | All leaf types |
| Available today (6.2.4) | **No** | **Yes** | Yes | Uncertain |
| Implementation effort | 1 annotation | **1 Thunk init** | Cross-ecosystem | Cross-ecosystem |

## Outcome

**Status**: DECISION

### Chosen: Option B — Store VIEW, not BODY

**Experimentally validated** in `iterative-render-machine` experiment (15 tests pass, including ~Copyable body through iterative path, cooperative pool survival at depth 200).

The default iterative `_render` stores the VIEW (`Self: Copyable`) on the heap. The body is computed transiently via `view.body` during dispatch and flows as a borrow into `Body._render`. The body is never stored. This enables full `~Copyable` body support today on Swift 6.2.4 with:

- No protocol changes
- No compiler features (`@_owned` not needed)
- No `func body()` (property retained)
- No dual-method protocol
- No unsafe pointer tricks on the body value

The constraint `Self: Copyable` (instead of `Body: Copyable`) is correct: views are user-defined structs with normal stored properties (Copyable). Bodies are the ~Copyable-capable associated types that the protocol is designed to support.

### Future: `@_owned` (when available)

`@_owned` (`UnderscoreOwned`, commit `458b62c9ed0` on `swiftlang/swift` main) would enable storing the BODY directly with zero constraint on Self. When it ships (not in 6.2.4, not in release/6.3), adding `@_owned @Builder var body` to the protocol would allow ~Copyable VIEWS in addition to ~Copyable bodies. This is a strict improvement over Option B but not blocking.

### Experimental evidence

- `iterative-render-machine/` — 15 tests all pass:
  - `~Copyable body (iterative, no custom _render)`: NCComposite (Copyable) with NCLeaf (~Copyable) body → iterative path, correct events
  - `~Copyable body in Tag scope`: nested in push/pop bracket, correct LIFO ordering
  - All existing tests (Copyable body, push/pop, siblings, depth 200) unchanged

## References

- `swiftlang/swift/include/swift/Basic/Features.def:621` — `EXPERIMENTAL_FEATURE(UnderscoreOwned, true)`
- `swiftlang/swift/lib/Sema/TypeCheckStorage.cpp:1070-1087` — ownership determination precedence
- `swiftlang/swift/lib/Sema/TypeCheckAttr.cpp:308-333` — @_owned attribute validation
- `swiftlang/swift/lib/AST/StorageImpl.cpp:33-47` — OpaqueReadOwnership → ReadImplKind mapping
- `swiftlang/swift/test/SILGen/owned_attr.swift` — compiler test case
- `swift-institute/Experiments/witness-noncopyable-default-forwarding/` — protocol property vs function ownership
- `swift-rendering-primitives/Research/cooperative-pool-stack-overflow.md` (v6) — governing constraints R3, R9
