# Existential Dispatch Under Strict Concurrency

<!--
---
version: 1.0.0
last_updated: 2026-03-02
status: DECISION
---
-->

## Context

During migration of `swift-renderable` to `swift-rendering-primitives`, the function
`_renderAsyncDynamic` fails to compile under `NonisolatedNonsendingByDefault` + strict
memory safety. The function uses a local async generic function for SE-0352 existential
opening, and the compiler treats it as `@concurrent` — flagging all captured values as
"sending task-isolated value to @concurrent local function".

This pattern is the **sole mechanism** for runtime async dispatch when opaque types
(`some HTML.View`) erase `Rendering.Async.Protocol` conformance at compile time.

## Question

How should `_renderAsyncDynamic` perform existential opening of
`any Rendering.Async.Protocol.Type` in an async context under
`NonisolatedNonsendingByDefault` without violating strict concurrency?

## Constraints

- `nonisolated(unsafe)` is **forbidden**
- `NonisolatedNonsendingByDefault` must be maintained
- `sending` and `@concurrent` are embraced where principled
- No `Sendable` constraints should propagate to `Rendering.Protocol` or its conformers
  unless semantically warranted
- The function must remain `@inlinable` for performance

## Analysis

### The Root Cause

Under `NonisolatedNonsendingByDefault` (SE-0461), module-level async functions default to
`nonisolated(nonsending)` — inheriting caller isolation. However, **local async functions**
are treated as `@concurrent` by the compiler, meaning they run on the global concurrent
executor. This creates an isolation boundary between the enclosing function (task-isolated)
and the local function (`@concurrent`).

The compiler error:
```
sending task-isolated 'markup' to @concurrent local function 'callRender'
risks causing data races between @concurrent and task-isolated uses
```

This is not a bug — local async functions are correctly identified as potentially escaping
the caller's isolation context. The fix must eliminate the isolation boundary crossing.

### Option A: Standalone Module-Level Function

Extract the local generic function to a standalone `@usableFromInline` function. All data
flows through parameters — no captures.

```swift
@usableFromInline
func _openedAsyncRender<A: Rendering.Async.Protocol, Sink: Rendering.Async.Sink.Protocol>(
    _: A.Type, markup: Any, into sink: Sink, context: inout Any
) async -> Bool {
    guard let m = markup as? A, var ctx = context as? A.Context else { return false }
    await A._renderAsync(m, into: sink, context: &ctx)
    context = ctx
    return true
}
```

Called via SE-0352 implicit existential opening:
```swift
let ok = await _openedAsyncRender(asyncType, markup: markup, into: sink, context: &anyCtx)
```

**Pros**:
- No captures → no sending violations
- Module-level function is `nonisolated(nonsending)` → inherits caller isolation
- SE-0352 opens `asyncType` (of type `any Rendering.Async.Protocol.Type`) automatically
- `@usableFromInline` satisfies `@inlinable` call requirement
- Clean separation of concerns

**Cons**:
- Type erasure via `Any` boxing for `markup` and `context`
- Helper function body not inlined (only `@usableFromInline`, not `@inlinable`)

### Option B: `nonisolated(nonsending)` on Local Function

Annotate the local function with `nonisolated(nonsending)` to explicitly declare it inherits
the caller's isolation:

```swift
nonisolated(nonsending)
func callRender<A: Rendering.Async.Protocol>(_ type: A.Type) async {
    guard let m = markup as? A, var ctx = anyCtx as? A.Context else { return }
    await A._renderAsync(m, into: sink, context: &ctx)
    anyCtx = ctx
}
```

**Pros**:
- Minimal change from original code
- Keeps existential opening logic co-located with usage
- Explicit about isolation intent
- No type erasure needed

**Cons**:
- Applies a function-level annotation to a local function (unusual pattern)
- Captures mutable state (`anyCtx`, `didRender`) across await — principled under
  `nonisolated(nonsending)` since no isolation boundary is crossed, but unusual

### Option C: `sending` Parameter on Outer Function

Mark `markup` as `sending` to transfer ownership:

```swift
func _renderAsyncDynamic<T: Rendering.Protocol, Sink: ...>(
    _ markup: sending T, ...
) async where T.RenderOutput == UInt8
```

**Result**: **Does not work.** The `sending` annotation transfers `markup`, but `anyCtx`
(a local `var`) is still captured by the local function. The compiler flags `anyCtx` as
"sending task-isolated to @concurrent local function". The core issue is the local function's
`@concurrent` isolation, not the parameter ownership.

### Option D: `@concurrent` on Outer Function with Sendable Constraints

Make `_renderAsyncDynamic` itself `@concurrent` and require `T: Sendable`:

```swift
@concurrent
func _renderAsyncDynamic<T: Rendering.Protocol & Sendable, Sink: ...>(
    _ markup: T, into sink: Sink, context: T.Context
) async -> T.Context where T.RenderOutput == UInt8, T.Context: Sendable
```

**Pros**:
- Explicitly concurrent — clear about execution semantics
- Local function inherits `@concurrent` — no boundary within

**Cons**:
- **Propagates `Sendable` to all rendering types** — every `Rendering.Protocol` conformer
  and its `Context` must be `Sendable`. This is architecturally wrong: rendering types
  are typically value types used within a single task, not shared across tasks.
- Changes `inout context` to return value — different API surface
- Forces all downstream code to deal with Sendable constraints

### Comparison

| Criterion | A: Standalone | B: nonsending local | C: sending param | D: @concurrent |
|-----------|:---:|:---:|:---:|:---:|
| Compiles clean | Yes | Yes | No | Yes |
| No Sendable propagation | Yes | Yes | N/A | No |
| Preserves inout API | Yes | Yes | N/A | No |
| Minimal code change | Medium | Minimal | N/A | Large |
| No type erasure | No | Yes | N/A | No |
| Principled correctness | Yes | Yes | N/A | Yes |
| Co-located logic | No | Yes | N/A | No |

## Outcome

**Status**: DECISION

**Choice**: **Option B — `nonisolated(nonsending)` on the local function.**

**Rationale**:

1. It is the most principled fix: `nonisolated(nonsending)` explicitly declares that the
   local function inherits the caller's isolation, which is exactly what we want — the
   existential dispatch runs in the same isolation domain as the caller.

2. Minimal change from the original code — a single annotation added.

3. No `Sendable` constraints propagated to the protocol hierarchy.

4. No type erasure (`Any` boxing) needed — the local function captures the concrete types.

5. The annotation is not unusual — it is the explicit form of what
   `NonisolatedNonsendingByDefault` makes the default for module-level functions. Applying
   it to a local function is simply making the intent explicit where the compiler cannot
   infer it.

**Alternative**: If the `nonisolated(nonsending)` annotation on local functions proves
problematic (e.g., future compiler changes), Option A (standalone function) is the fallback.
It is equally correct and well-supported by SE-0352.

## Experiment

Verified empirically at:
`Experiments/existential-dispatch/` — Swift 6.2.4, `NonisolatedNonsendingByDefault` enabled.

Results:
- Pattern 1 (standalone): Build complete, 0 errors, 0 warnings
- Pattern 2 (sending param): 1 error, 1 warning — `anyCtx` capture flagged
- Pattern 3 (nonisolated(nonsending) local): Build complete, 0 errors, 0 warnings
- Pattern 4 (@concurrent + Sendable): Build complete, 0 errors, 0 warnings

## References

- [SE-0461: Run nonisolated async functions on the caller's actor by default](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)
- [SE-0352: Implicitly Opened Existentials](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md)
- [SE-0430: `sending` parameter and result values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md)
- [SE-0414: Region-Based Isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md)
